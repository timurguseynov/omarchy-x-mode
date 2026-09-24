#include "snap.hpp"
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

#include <algorithm>
#include <cmath>
#include <cstring>

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

int Snap::gapOut() {
    static auto PGAPSOUTDATA = CConfigValue<Config::IComplexConfigValue>("general:gaps_out");
    auto* const PGAPSOUT     = sc<Config::CCssGapData*>(PGAPSOUTDATA.ptr());
    if (!PGAPSOUT)
        return 8;
    return sc<int>(PGAPSOUT->m_top);
}

int Snap::border() {
    static auto PBORDER = CConfigValue<Config::INTEGER>("general:border_size");
    return sc<int>(*PBORDER);
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

CBox Snap::usable(PHLMONITOR mon) {
    if (!mon)
        return {};
    const double left   = mon->m_reservedArea.left();
    // The top bar reserves its height, but it is a layer-shell surface that is
    // gone for a moment while the shell restarts during install. Snapping in
    // that window saw a zero top and sized windows to the full screen height.
    // Fall back to the bar's own reserved height so a half stays a half.
    const double top    = std::max(mon->m_reservedArea.top(), 24.0);
    // x-mode.lua publishes the dock card plus half of gaps_out. Rectangle's
    // visibleFrame excludes a right-edge dock before any fraction is taken, so
    // a left half and a right half split this narrower frame and never overlap.
    const double right  = mon->m_reservedArea.right() + sc<double>(g_pGlobalState->config.xModeDockInset->value());
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

static CBox applyGaps(const CBox& box, bool innerL, bool innerR, bool innerT, bool innerB) {
    const int gap  = gapOut();
    const int half = gap / 2;
    const int b    = border();
    const int left = (innerL ? half : gap) + b;
    const int right = (innerR ? half : gap) + b;
    const int top = (innerT ? half : gap) + b;
    const int bottom = (innerB ? half : gap) + b;
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

std::optional<CBox> Snap::contentBox(eKind kind, PHLMONITOR mon, PHLWINDOW w) {
    auto box = zoneBox(kind, mon);
    if (!box)
        return std::nullopt;
    const int chrome = chromeH(w);
    box->y += chrome;
    box->h -= chrome;
    return box;
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
        if (std::abs(got.x - box->x) <= slop && std::abs(got.y - box->y) <= slop &&
            std::abs(got.w - box->w) <= slop && std::abs(got.h - box->h) <= slop)
            return kind;
    }
    return eKind::None;
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
