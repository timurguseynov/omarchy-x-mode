#include "snap.hpp"
#include "dragSession.hpp"
#include "globals.hpp"

#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/config/shared/complex/ComplexDataTypes.hpp>
#include <hyprland/src/config/shared/actions/ConfigActions.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/view/Group.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/helpers/time/Time.hpp>


#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <unordered_map>

using namespace Snap;

eKind Snap::kindFromString(std::string_view s) {
    if (s == "left")
        return eKind::Left;
    if (s == "right")
        return eKind::Right;
    if (s == "top")
        return eKind::Top;
    if (s == "bottom")
        return eKind::Bottom;
    if (s == "top-left")
        return eKind::TopLeft;
    if (s == "top-right")
        return eKind::TopRight;
    if (s == "bottom-left")
        return eKind::BottomLeft;
    if (s == "bottom-right")
        return eKind::BottomRight;
    if (s == "maximize")
        return eKind::Maximize;
    if (s == "almost-maximize")
        return eKind::AlmostMaximize;
    return eKind::None;
}

const char* Snap::kindToString(eKind k) {
    switch (k) {
        case eKind::Left: return "left";
        case eKind::Right: return "right";
        case eKind::Top: return "top";
        case eKind::Bottom: return "bottom";
        case eKind::TopLeft: return "top-left";
        case eKind::TopRight: return "top-right";
        case eKind::BottomLeft: return "bottom-left";
        case eKind::BottomRight: return "bottom-right";
        case eKind::Maximize: return "maximize";
        case eKind::AlmostMaximize: return "almost-maximize";
        case eKind::None: return "";
    }
    return "";
}

// Overridden while naming the zone a window occupied before the frame
// changed. Null means read the live config.
static int s_gapOverride    = -1;
static int s_borderOverride = -1;
static int s_insetOverride  = -1;

int Snap::gapOut() {
    if (s_gapOverride >= 0)
        return s_gapOverride;
    static auto PGAPSOUTDATA = CConfigValue<Config::IComplexConfigValue>("general:gaps_out");
    auto* const PGAPSOUT     = sc<Config::CCssGapData*>(PGAPSOUTDATA.ptr());
    if (!PGAPSOUT)
        return 8;
    return sc<int>(PGAPSOUT->m_top);
}

int Snap::border() {
    if (s_borderOverride >= 0)
        return s_borderOverride;
    static auto PBORDER = CConfigValue<Config::INTEGER>("general:border_size");
    return sc<int>(*PBORDER);
}

void Snap::assumeFrame(int gap, int border, int inset) {
    s_gapOverride    = gap;
    s_borderOverride = border;
    s_insetOverride  = inset;
}

// The dock inset usable() takes off the frame's right edge.
static double frameInset() {
    if (s_insetOverride >= 0)
        return s_insetOverride;
    return sc<double>(g_pGlobalState->config.xModeDockInset->value());
}

int Snap::chromeH(PHLWINDOW w) {
    if (w && w->m_ruleApplicator && g_pGlobalState) {
        if (w->m_ruleApplicator->m_otherProps.props.contains(g_pGlobalState->nobarRuleIdx))
            return 0;
    }
    int h = sc<int>(g_pGlobalState->config.barHeight->value());
    bool tabs = !w || (w->m_group && w->m_group->size() > 0);
    if (!tabs && w && w->m_ruleApplicator && g_pGlobalState->alwaysTabbarRuleIdx)
        tabs = w->m_ruleApplicator->m_otherProps.props.contains(g_pGlobalState->alwaysTabbarRuleIdx);
    if (tabs)
        h += sc<int>(g_pGlobalState->config.tabHeight->value());
    return h;
}

CBox Snap::monitorBox(PHLMONITOR mon) {
    if (!mon)
        return {};
    return {mon->m_position.x, mon->m_position.y, mon->m_size.x, mon->m_size.y};
}

// The top the bar reserves. The bar is a layer-shell surface and is gone for a
// moment while the shell restarts, so a snap in that window saw a zero top and
// sized the window to the full screen height. Remember the last non-zero top
// per monitor and fall back to it for a few seconds: long enough to cover a
// restart, short enough that a bar the user really moved away (bottom/left/
// right, or none) stops applying and the top goes back to what the monitor
// reports. A hardcoded height would leave a phantom inset over a bottom bar.
static std::unordered_map<std::string, std::pair<double, Time::steady_tp>> s_lastBarTop;

static double resolvedTop(PHLMONITOR mon) {
    const double top = mon->m_reservedArea.top();
    if (top > 0) {
        s_lastBarTop[mon->m_name] = {top, Time::steadyNow()};
        return top;
    }
    const auto it = s_lastBarTop.find(mon->m_name);
    if (it != s_lastBarTop.end() &&
        std::chrono::duration_cast<std::chrono::seconds>(Time::steadyNow() - it->second.second).count() < 10)
        return it->second.first;
    return top;
}

double Snap::barTop(PHLMONITOR mon) {
    return mon ? resolvedTop(mon) : 0.0;
}

CBox Snap::usable(PHLMONITOR mon) {
    if (!mon)
        return {};
    const double left   = mon->m_reservedArea.left();
    const double top    = resolvedTop(mon);
    // x-mode.lua publishes the dock card plus half of gaps_out. Rectangle's
    // visibleFrame excludes a right-edge dock before any fraction is taken, so
    // a left half and a right half split this narrower frame and never overlap.
    const double right  = mon->m_reservedArea.right() + frameInset();
    const double bottom = mon->m_reservedArea.bottom();
    const CBox   box    = monitorBox(mon);
    return {box.x + left, box.y + top, box.w - left - right, box.h - top - bottom};
}

static CBox fractionalRect(const CBox& frame, const char* hside, const char* vside, double hf, double vf) {
    const int w = sc<int>(std::floor(frame.w * hf + 0.0001));
    const int h = sc<int>(std::floor(frame.h * vf + 0.0001));
    int       x = sc<int>(frame.x);
    int       y = sc<int>(frame.y);
    if (hside && std::strcmp(hside, "right") == 0)
        x = sc<int>(frame.x + frame.w - w);
    if (vside && std::strcmp(vside, "bottom") == 0)
        y = sc<int>(frame.y + frame.h - h);
    return {x, y, w, h};
}

// The border is drawn outside the window box and reserves its own space, so it
// is taken off every side of the frame once. The gap is inset on top of that: a
// full outer gap on the screen edges, half on an edge shared with the window
// next to it, so two snapped windows end up exactly one gap apart.
static CBox applyGaps(const CBox& box, bool innerL, bool innerR, bool innerT, bool innerB) {
    const int gap  = gapOut();
    const int half = gap / 2;
    const int b    = border();
    const int left = b + (innerL ? half : gap);
    const int right = b + (innerR ? half : gap);
    const int top = b + (innerT ? half : gap);
    const int bottom = b + (innerB ? half : gap);
    return {box.x + left, box.y + top, box.w - left - right, box.h - top - bottom};
}

std::optional<CBox> Snap::zoneBox(eKind kind, PHLMONITOR mon) {
    if (!mon || kind == eKind::None)
        return std::nullopt;

    const CBox frame = usable(mon);

    if (kind == eKind::AlmostMaximize) {
        const double pct = sc<double>(g_pGlobalState->config.xModeAlmostMaximizePercent->value()) / 100.0;
        const int    w   = sc<int>(std::floor(frame.w * pct + 0.5));
        const int    h   = sc<int>(std::floor(frame.h * pct + 0.5));
        return CBox{frame.x + std::floor((frame.w - w) / 2.0 + 0.5), frame.y + std::floor((frame.h - h) / 2.0 + 0.5), w, h};
    }

    struct SZone {
        const char* hside;
        const char* vside;
        double      hf;
        double      vf;
        bool        innerL, innerR, innerT, innerB;
    } z{};

    switch (kind) {
        case eKind::Left: z = {"left", nullptr, 0.5, 1, false, true, false, false}; break;
        case eKind::Right: z = {"right", nullptr, 0.5, 1, true, false, false, false}; break;
        case eKind::Top: z = {nullptr, "top", 1, 0.5, false, false, false, true}; break;
        case eKind::Bottom: z = {nullptr, "bottom", 1, 0.5, false, false, true, false}; break;
        case eKind::TopLeft: z = {"left", "top", 0.5, 0.5, false, true, false, true}; break;
        case eKind::TopRight: z = {"right", "top", 0.5, 0.5, true, false, false, true}; break;
        case eKind::BottomLeft: z = {"left", "bottom", 0.5, 0.5, false, true, true, false}; break;
        case eKind::BottomRight: z = {"right", "bottom", 0.5, 0.5, true, false, true, false}; break;
        case eKind::Maximize: z = {nullptr, nullptr, 1, 1, false, false, false, false}; break;
        default: return std::nullopt;
    }

    return applyGaps(fractionalRect(frame, z.hside, z.vside, z.hf, z.vf), z.innerL, z.innerR, z.innerT, z.innerB);
}

// When a window cannot shrink to its zone (the client minimum is bigger, e.g.
// kdenlive is 1027 wide on a 938 half), the zone's far edge is the one that
// overhangs. A right/bottom snap keeps that edge put and grows toward the
// screen interior; every other zone keeps its left/top edge and overhangs right
// /down. See contentBox.
static bool zoneSnapsRight(Snap::eKind kind) {
    switch (kind) {
        case Snap::eKind::Right:
        case Snap::eKind::TopRight:
        case Snap::eKind::BottomRight: return true;
        default: return false;
    }
}

static bool zoneSnapsBottom(Snap::eKind kind) {
    switch (kind) {
        case Snap::eKind::Bottom:
        case Snap::eKind::BottomLeft:
        case Snap::eKind::BottomRight: return true;
        default: return false;
    }
}

// A left/right/maximize zone covers the work area's full height, so a window in
// it is identified by where it sits horizontally and by its size: y is where the
// window happens to sit, not which zone it is. kindOf matches those without the
// vertical bound, which is what keeps the pack's own re-lay-out recognising a
// window that a drag left a little lower (snap_zone_tolerance_reload_test). A
// zone whose height is what places it -- top, bottom, a quarter -- needs y.
static bool zoneFullHeight(Snap::eKind kind) {
    switch (kind) {
        case Snap::eKind::Left:
        case Snap::eKind::Right:
        case Snap::eKind::Maximize: return true;
        default: return false;
    }
}

std::optional<CBox> Snap::contentBox(eKind kind, PHLMONITOR mon, PHLWINDOW w) {
    auto box = zoneBox(kind, mon);
    if (!box)
        return std::nullopt;
    const int chrome = chromeH(w);
    box->y += chrome;
    box->h -= chrome;

    // A client can refuse to shrink below its own minimum (kdenlive is 1027
    // wide). Hyprland then grows a floating box around its centre, which walks
    // the left edge of a left snap off-screen (observed at x=-43 on a 1920
    // monitor). Grow the target to the minimum here and keep the snapped edge
    // put, so the window overhangs the far side of the zone instead.
    if (w) {
        if (const auto MIN = w->minSize(); MIN) {
            const int minW = sc<int>(MIN->x);
            const int minH = sc<int>(MIN->y);
            if (box->w < minW) {
                if (zoneSnapsRight(kind))
                    box->x += box->w - minW; // keep the right edge
                box->w = minW;
            }
            if (box->h < minH) {
                if (zoneSnapsBottom(kind))
                    box->y += box->h - minH; // keep the bottom edge
                box->h = minH;
            }
        }
    }
    return box;
}

// The sizes a Super+Alt+arrow steps through on one side, in Rectangle's order:
// a half, two thirds, a third.
static constexpr double CYCLE_HF[] = {0.5, 2.0 / 3.0, 1.0 / 3.0};
// How far a window may sit from a cycle size and still be the one on it. The
// press before this size placed it, so only a layout round can have moved it.
static constexpr int    CYCLE_SLOP = 32;

std::optional<CBox> Snap::cycleBox(bool right, double hf, PHLMONITOR mon, PHLWINDOW w) {
    if (!mon || hf <= 0)
        return std::nullopt;

    const CBox frame = usable(mon);
    if (frame.w < 1 || frame.h < 1)
        return std::nullopt;

    // A full-height slice against the side, the edge shared with the window next
    // to it taking the half gap -- the insets a zone takes (see the Lua
    // cycle_geom this replaces: a left cycle is inner *right*).
    CBox box = applyGaps(fractionalRect(frame, right ? "right" : "left", nullptr, hf, 1), right, !right, false, false);

    const int chrome = chromeH(w);
    box.y += chrome;
    box.h -= chrome;

    // Same growth as a zone (contentBox): a client that cannot shrink to this
    // size keeps the anchored edge and overhangs, and this exact box is what
    // cycle() then looks for.
    if (w) {
        if (const auto MIN = w->minSize()) {
            if (box.w < MIN->x) {
                if (right)
                    box.x += box.w - MIN->x; // keep the right edge
                box.w = MIN->x;
            }
            if (box.h < MIN->y)
                box.h = MIN->y;
        }
    }

    return box;
}

bool Snap::cycle(PHLWINDOW w, bool right) {
    if (!xModeEnabled() || !w)
        return false;

    const auto mon    = w->m_monitor.lock();
    const auto TARGET = w->layoutTarget();
    if (!mon || !TARGET || !TARGET->floating())
        return false;

    const CBox          got   = TARGET->position();
    std::optional<CBox> boxes[3];
    for (size_t i = 0; i < 3; i++)
        boxes[i] = cycleBox(right, CYCLE_HF[i], mon, w);

    const auto near = [](double a, double b) { return std::abs(a - b) <= CYCLE_SLOP; };
    for (size_t i = 0; i < 3; i++) {
        const auto& box = boxes[i];
        if (!box)
            continue;
        // Anchored on the edge the cycle holds put: the left edge for a left
        // cycle, the right edge for a right one.
        const bool anchored = right ? near(got.x + got.w, box->x + box->w) : near(got.x, box->x);
        if (!anchored || !near(got.y, box->y) || !near(got.w, box->w) || !near(got.h, box->h))
            continue;
        const auto& next = boxes[(i + 1) % 3];
        if (!next)
            return false;
        return applyContent(w, *next);
    }

    return false;
}

eKind Snap::zoneAtCursor(const Vector2D& cursor, PHLWINDOW dragged, bool activeDrag) {
    (void)dragged;
    (void)activeDrag;
    if (!xModeEnabled())
        return eKind::None;
    const auto mon = State::monitorState()->query().vec(cursor).run();
    if (!mon)
        return eKind::None;

    const CBox box   = monitorBox(mon);
    const double relx = cursor.x - box.x;
    const double rely = cursor.y - box.y;
    const int    margin = std::max(1, sc<int>(g_pGlobalState->config.xModeSnapMargin->value()));
    const int    corner = std::max(margin, sc<int>(g_pGlobalState->config.xModeSnapCorner->value()));
    const int    shortE = std::max(corner, sc<int>(g_pGlobalState->config.xModeSnapShortEdge->value()));

    // Rectangle: corners are squares. Quarters live only there, not in the
    // outer thirds of a fat edge strip.
    const bool inLeftCornerBand  = relx < margin + corner;
    const bool inRightCornerBand = relx > box.w - margin - corner;
    const bool inTopCornerBand   = rely < margin + corner;
    const bool inBotCornerBand   = rely > box.h - margin - corner;

    if (inLeftCornerBand && inTopCornerBand)
        return eKind::TopLeft;
    if (inRightCornerBand && inTopCornerBand)
        return eKind::TopRight;
    if (inLeftCornerBand && inBotCornerBand)
        return eKind::BottomLeft;
    if (inRightCornerBand && inBotCornerBand)
        return eKind::BottomRight;

    const bool onLeft  = relx < margin;
    const bool onRight = relx > box.w - margin;
    // Maximize only when the cursor is in the reserved top (the bar) plus a
    // small slop. If there is no bar and gaps_out is 0, reserved top is 0 and
    // this collapses to the screen edge + slop — like Rectangle on macOS.
    const int topBand = std::max(sc<int>(mon->m_reservedArea.top()), 24)
        + std::max(0, sc<int>(g_pGlobalState->config.xModeSnapTopSlop->value()));
    const bool onTop = rely < std::max(margin, topBand);

    if (onTop)
        return eKind::Maximize;

    // Compound on the side edges: short strips at the top/bottom of the edge
    // pick a top/bottom half (if enabled); the rest of the edge is a left/right half.
    const bool topHalf    = g_pGlobalState->config.xModeSnapTopHalf->value();
    const bool bottomHalf = g_pGlobalState->config.xModeSnapBottomHalf->value();
    if (onLeft) {
        if (topHalf && rely < shortE)
            return eKind::Top;
        if (bottomHalf && rely > box.h - shortE)
            return eKind::Bottom;
        return eKind::Left;
    }
    if (onRight) {
        if (topHalf && rely < shortE)
            return eKind::Top;
        if (bottomHalf && rely > box.h - shortE)
            return eKind::Bottom;
        return eKind::Right;
    }

    return eKind::None;
}

bool Snap::applyContent(PHLWINDOW w, const CBox& content) {
    if (!w || content.w < 1 || content.h < 1)
        return false;

    if (Fullscreen::controller()->isFullscreen(w))
        Fullscreen::controller()->setFullscreenMode(w, Fullscreen::FSMODE_NONE, std::nullopt, true);

    const auto TARGET = w->layoutTarget();
    if (!TARGET)
        return false;

    if (!TARGET->floating())
        Config::Actions::floatWindow(Config::Actions::eTogglableAction::TOGGLE_ACTION_ENABLE, w);

    // Same path as Lua place(): layout resize+move. Direct setPositionGlobal after
    // toggleGroup configured the client to 0x0; a forced sendWindowSize then made
    // the border blink until the pointer left the window.
    Config::Actions::resize(content.size(), false, w);
    Config::Actions::move(content.pos(), false, w);
    return true;
}

void Snap::moveDrag(PHLWINDOW w, Vector2D pos) {
    if (!w)
        return;
    const auto TARGET = w->layoutTarget();
    if (!TARGET || !TARGET->floating())
        return;

    const auto each = [&](auto fn) {
        if (w->m_group) {
            for (const auto& m : w->m_group->windows()) {
                if (const auto win = m.lock())
                    fn(win);
            }
        } else
            fn(w);
    };

    // Damage the old content+chrome. Deco damage after the move only covers the
    // titlebar strip, so without this the surface stays one mouse-move behind.
    each([](PHLWINDOW win) { g_pHyprRenderer->damageWindow(win, true); });

    auto box = TARGET->position();
    box.x    = pos.x;
    box.y    = pos.y;
    box.round();

    TARGET->setPositionGlobal(box, Layout::TARGET_UPDATE_NO_CLIENT_CONFIGURE);

    // setBox writes the animation goal; warp current to it this frame so the
    // compositor-drawn chrome and the surface share a pixel.
    each([&](PHLWINDOW win) {
        win->positionAnimation()->setValueAndWarp(box.pos());
        win->sizeAnimation()->setValueAndWarp(box.size());
    });

    TARGET->warpPositionSize();

    // Damage the new content+chrome this frame (not on the next motion).
    each([](PHLWINDOW win) { g_pHyprRenderer->damageWindow(win, true); });
}

Snap::eKind Snap::kindOf(PHLWINDOW w, int slop) {
    if (!w)
        return eKind::None;
    const auto mon = w->m_monitor.lock();
    const auto TARGET = w->layoutTarget();
    if (!mon || !TARGET)
        return eKind::None;

    const CBox got = TARGET->position();
    static constexpr eKind KINDS[] = {
        eKind::Left, eKind::Right, eKind::Top, eKind::Bottom,
        eKind::TopLeft, eKind::TopRight, eKind::BottomLeft, eKind::BottomRight,
        eKind::Maximize, eKind::AlmostMaximize,
    };
    for (const auto kind : KINDS) {
        const auto box = contentBox(kind, mon, w);
        if (!box)
            continue;
        if (std::abs(got.x - box->x) <= slop && std::abs(got.w - box->w) <= slop && std::abs(got.h - box->h) <= slop &&
            (zoneFullHeight(kind) || std::abs(got.y - box->y) <= slop))
            return kind;
    }
    return eKind::None;
}

// True when either fullscreen flag is set. A client-fullscreen window (a video
// player, a game) keeps the compositor's flag clear, and fitting it would push a
// screen-sized surface below the bar and off the bottom.
static bool anyFullscreen(PHLWINDOW w) {
    const auto modes = Fullscreen::controller()->getFullscreenModes(w);
    return modes.internal != Fullscreen::FSMODE_NONE || modes.client != Fullscreen::FSMODE_NONE;
}

void Snap::clampToWorkArea(PHLWINDOW w, bool force) {
    if (!xModeEnabled() || !w || !w->m_isFloating || !w->m_isMapped || anyFullscreen(w))
        return;
    // The ordinary pass leaves a hidden window alone (a group tab, a swallow).
    // The forced pass is the unplug restore: Hyprland's floating algorithm can
    // mark an off-screen window hidden, and skipping it would leave it there.
    if (!force && w->isHidden())
        return;
    // A drag clamps itself and is allowed to hang off an edge; refitting it here
    // would pull it back on every mouse move.
    if (g_pDragSession && g_pDragSession->owns(w))
        return;

    // A group shares one layout target. Hyprland translates that target once
    // per member, and fitting each member would page the same box again. The
    // current tab carries the chrome; its pass covers the group.
    if (force && w->m_group) {
        const auto cur = w->m_group->current();
        if (cur && cur != w)
            return;
    }

    // setPositionGlobal below calls back into the bar's updateWindow, which is
    // what calls this. The box is already written by then, so the inner pass has
    // nothing to add; bailing out is what keeps a one-pixel rounding gap from
    // recursing.
    static int depth = 0;
    if (depth)
        return;
    struct Depth {
        int& n;
        explicit Depth(int& n) : n(n) { ++n; }
        ~Depth() { --n; }
    } hold(depth);

    const auto MON    = w->m_monitor.lock();
    const auto TARGET = w->layoutTarget();
    if (!MON || !TARGET || !TARGET->floating())
        return;

    // usable() is the monitor minus the reserved area (the top bar) and the dock.
    const CBox frame = usable(MON);
    if (frame.w < 1 || frame.h < 1)
        return;

    // chromeH, not the positioner's reserved top. Reserved adds the border
    // decoration (it reserves every edge) on top of the bar, and a no_bar rule
    // is visible to chromeH as soon as the window has it, while the decoration
    // keeps reporting a titlebar until updateRules hides it.
    const int chrome = chromeH(w);
    const int edge   = gapOut() + border();
    CBox      box    = TARGET->position();

    // A window halfway out of fullscreen still carries the fullscreen box after
    // its flags have cleared: the monitor's origin and the monitor's size. Fitting
    // that records it as the floating one, so Hyprland's own restore on exit hands
    // the fullscreen box straight back. Size alone is not enough to recognise it.
    // A fresh window opens centred and taller than the work area, often exactly as
    // tall as the monitor, and that one has to be shrunk or its titlebar stays
    // over the bar.
    const CBox mon = monitorBox(MON);
    if (box.w >= mon.w - 1 && box.h >= mon.h - 1 && std::abs(box.x - mon.x) <= 1 && std::abs(box.y - mon.y) <= 1)
        return;

    // Don't shrink past the client's own minimum. Forcing a smaller box and then
    // sendWindowSize makes the client configure straight back, and the next pass
    // fights it. A window that cannot shrink keeps the edge its snap anchored.
    double maxW = std::max(1.0, frame.w - edge - edge);
    double maxH = std::max(1.0, frame.h - edge - edge - chrome);
    if (const auto MIN = w->minSize()) {
        if (MIN->x > 1)
            maxW = std::max(maxW, MIN->x);
        if (MIN->y > 1)
            maxH = std::max(maxH, MIN->y);
    }

    // A shrink keeps the centre: Hyprland resizes around it, so the top-left the
    // clamp pulls back has to be the one after the shrink, not the one before.
    // `tooBig` is what the rest of the fit is for: a box that had to be shrunk is
    // one Hyprland grew around its centre, so it has to be put back inside.
    const bool tooBig = box.w > maxW || box.h > maxH;
    if (box.w > maxW) {
        box.x += (box.w - maxW) / 2.0;
        box.w = maxW;
    }
    if (box.h > maxH) {
        box.y += (box.h - maxH) / 2.0;
        box.h = maxH;
    }

    const double minTop = frame.y + edge + chrome;

    // The chrome stays below the reserved top unconditionally: that strip is the
    // window's handle, and the bar would cover it. This is what stops a fresh
    // window -- Hyprland opens it centred, often exactly as tall as the monitor,
    // from climbing over the bar.
    if (box.y < minTop)
        box.y = minTop;

    // Everything else is the fit for a box that was too big. A box that already
    // fits is left exactly where the user (a titlebar drag) or the app put it.
    // Fitting it anyway moved a window nobody asked to move, and it ran from the
    // next updateWindow -- an unrelated, later event -- so a snapped window
    // dragged a little down jumped back into its snap when another window opened.
    if (tooBig) {
        const double maxBottom = frame.y + frame.h - edge;
        if (box.h <= maxBottom - minTop && box.y + box.h > maxBottom)
            box.y = maxBottom - box.h;

        const double minLeft  = frame.x + edge;
        const double maxRight = frame.x + frame.w - edge;
        // A window wider than the frame (the client minimum beat the zone) keeps
        // the x its snap wrote. Pulling it back inside would walk a left snap off
        // the left edge, which is the case contentBox grows the target to avoid.
        if (box.w <= maxRight - minLeft) {
            if (box.x < minLeft)
                box.x = minLeft;
            else if (box.x + box.w > maxRight)
                box.x = maxRight - box.w;
        }
    }

    // The forced pass from monitor removal. A window can sit past any edge,
    // and its box still fits by size, so the block above skipped it.
    //
    // One that is completely off the left (or the top) is a whole number of
    // screens away: Hyprland translates a float by the monitor origin only,
    // and moving the surviving monitor applies that delta again, so a left
    // half and a right half keep their offset inside a screen but land on
    // the wrong one. Step back by whole monitor sizes first. Pinning both to
    // the near edge would stack them. A window that still overlaps this
    // monitor is not on another screen — the right side of a wider one hangs
    // off this edge — and the clamp below pulls that overhang in. Size is
    // left alone (a window too wide for the narrower monitor was already
    // shrunk above). A window wider than the frame keeps its right edge:
    // pulling it in would walk a left snap off the left edge.
    if (force) {
        if (mon.w > 1 && box.x + box.w <= mon.x) {
            const double pages = std::floor((box.x - mon.x) / mon.w);
            box.x -= pages * mon.w;
        }
        if (mon.h > 1 && box.y + box.h <= mon.y) {
            const double pages = std::floor((box.y - mon.y) / mon.h);
            box.y -= pages * mon.h;
        }

        const double maxBottom = frame.y + frame.h - edge;
        if (box.h <= maxBottom - minTop && box.y + box.h > maxBottom)
            box.y = maxBottom - box.h;

        const double minLeft  = frame.x + edge;
        const double maxRight = frame.x + frame.w - edge;
        if (box.x < minLeft)
            box.x = minLeft;
        else if (box.w <= maxRight - minLeft && box.x + box.w > maxRight)
            box.x = maxRight - box.w;
    }

    const CBox got     = TARGET->position();
    const bool moved   = std::abs(got.x - box.x) >= 1 || std::abs(got.y - box.y) >= 1;
    const bool resized = std::abs(got.w - box.w) >= 1 || std::abs(got.h - box.h) >= 1;
    if (!moved && !resized)
        return;

    // Direct, not Actions::move: that goes through moveTarget, which calls back
    // into updateWindow, and the bar calls this from there. Windows do not animate
    // (x-mode disables windowsMove), so warping the current value is invisible.
    // setPositionGlobal would also configure the client; a move must not, and a
    // shrink reports the size once. The forced pass is the exception: a page
    // shift leaves size alone, so the client (X11 especially) keeps the old
    // coordinates until sendWindowSize. updateToplevel re-enters the surface on
    // the monitor the window sits on now. Neither raises: a click does that.
    box.round();
    TARGET->setPositionGlobal(box, Layout::TARGET_UPDATE_NO_CLIENT_CONFIGURE);

    const auto sync = [&](PHLWINDOW win) {
        if (!win)
            return;
        win->positionAnimation()->setValueAndWarp(box.pos());
        win->sizeAnimation()->setValueAndWarp(box.size());
        if (force) {
            if (win->isHidden())
                win->setHidden(false);
            win->sendWindowSize(true);
            win->updateToplevel();
        }
    };
    if (w->m_group) {
        for (const auto& m : w->m_group->windows())
            sync(m.lock());
    } else
        sync(w);
    // Hit-test uses GEOMETRIC_CURRENT plus the decoration cache. Warp the
    // target so the titlebar sits on the paged box this frame; a click can
    // then raise without us raising here.
    if (force)
        TARGET->warpPositionSize();
    if (!force && resized)
        w->sendWindowSize(true);
}

bool Snap::applyKind(PHLWINDOW w, eKind kind) {
    if (!xModeEnabled() || !w || kind == eKind::None)
        return false;

    const auto mon = w->m_monitor.lock();
    if (!mon)
        return false;
    const auto box = contentBox(kind, mon, w);
    if (!box)
        return false;
    return applyContent(w, *box);
}
