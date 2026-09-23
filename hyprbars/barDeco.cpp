#include "barDeco.hpp"

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/state/LayerState.hpp>
#include <hyprland/src/desktop/state/ViewHitTester.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/view/Group.hpp>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/helpers/MiscFunctions.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/managers/KeybindManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/config/ConfigManager.hpp>
#include <hyprland/src/config/shared/animation/AnimationTree.hpp>
#include <hyprland/src/config/shared/parserUtils/ParserUtils.hpp>
#include <hyprland/src/config/supplementary/executor/Executor.hpp>
#include <hyprland/src/config/shared/actions/ConfigActions.hpp>
#include <hyprland/src/animation/AnimationManager.hpp>
#include <hyprland/src/protocols/LayerShell.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include "globals.hpp"
#include "dragSession.hpp"
#include "snap.hpp"
#include "BarPassElement.hpp"

#include <climits>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <format>

// One physical mouse press is delivered to every bar. Record which press we
// already handled so a later bar cannot act on the same click (see
// onMouseButton).
static uint32_t g_lastPressTime   = 0;
static uint32_t g_lastPressButton = 0;

using namespace Render::GL;

void keepGroupFocusOnClose(PHLWINDOW w) {
    if (!w)
        return;

    const auto GROUP = w->m_group;
    if (!GROUP || GROUP->size() <= 1 || GROUP->current() != w)
        return;

    GROUP->moveCurrent(false); // previous tab
    if (const auto CUR = GROUP->current(); CUR) {
        if (CUR->m_isFloating)
            Desktop::windowState()->raise(CUR);
        if (Desktop::focusState()->window() != CUR)
            Desktop::focusState()->rawWindowFocus(CUR, Desktop::FOCUS_REASON_CLICK);
    }
}

static CHyprColor configColor(Config::INTEGER color) {
    return CHyprColor{static_cast<uint64_t>(color)};
}

CHyprBar::CHyprBar(PHLWINDOW pWindow) : IHyprWindowDecoration(pWindow) {
    m_pWindow = pWindow;

    const auto PMONITOR         = pWindow->m_monitor.lock();
    PMONITOR->m_scheduledRecalc = true;

    // button events
    m_pMouseButtonCallback = Event::bus()->m_events.input.mouse.button.listen([&](IPointer::SButtonEvent e, Event::SCallbackInfo& info) { onMouseButton(info, e); });
    m_pTouchDownCallback   = Event::bus()->m_events.input.touch.down.listen([&](ITouch::SDownEvent e, Event::SCallbackInfo& info) { onTouchDown(info, e); });
    m_pTouchUpCallback     = Event::bus()->m_events.input.touch.up.listen([&](ITouch::SUpEvent e, Event::SCallbackInfo& info) { onTouchUp(info, e); });

    // move events
    m_pTouchMoveCallback = Event::bus()->m_events.input.touch.motion.listen([&](ITouch::SMotionEvent e, Event::SCallbackInfo& info) { onTouchMove(info, e); });
    m_pMouseMoveCallback = Event::bus()->m_events.input.mouse.move.listen([&](Vector2D c, Event::SCallbackInfo& info) { onMouseMove(c); });

    Animation::mgr()->createAnimation(configColor(g_pGlobalState->config.barColor->value()), m_cRealBarColor, Config::animationTree()->getAnimationPropertyConfig("border"),
                                      pWindow, AVARDAMAGE_NONE);
    m_cRealBarColor->setUpdateCallback([&](auto) { damageEntire(); });
}

CHyprBar::~CHyprBar() {
    std::erase(g_pGlobalState->bars, m_self);
}

bool CHyprBar::grouped() {
    const auto PWINDOW = m_pWindow.lock();
    return PWINDOW && PWINDOW->m_group && PWINDOW->m_group->size() > 0;
}

bool CHyprBar::alwaysTabbar() {
    const auto PWINDOW = m_pWindow.lock();
    if (!PWINDOW || !PWINDOW->m_ruleApplicator || !g_pGlobalState)
        return false;
    return PWINDOW->m_ruleApplicator->m_otherProps.props.contains(g_pGlobalState->alwaysTabbarRuleIdx);
}

bool CHyprBar::wantsTabbar() {
    return grouped() || alwaysTabbar();
}

int CHyprBar::tabHeight() {
    return g_pGlobalState->config.tabHeight->value();
}

bool CHyprBar::groupCurrent() {
    const auto PWINDOW = m_pWindow.lock();
    if (!PWINDOW || !PWINDOW->m_group)
        return true;
    return PWINDOW == PWINDOW->m_group->current();
}

SDecorationPositioningInfo CHyprBar::getPositioningInfo() {
    const auto                 HEIGHT     = g_pGlobalState->config.barHeight->value();
    const auto                 ENABLED    = g_pGlobalState->config.enabled->value() && xModeEnabled();
    const auto                 PRECEDENCE = g_pGlobalState->config.barPrecedenceOverBorder->value();
    // Reserve the tabbar for every group member, not only the current one: the
    // positioner caches these extents and its fast path never recomputes them
    // when the group's current tab changes, so gating on groupCurrent() left the
    // newly-current bar with a stale, zero-height box and it vanished until
    // something forced a full recalc (a new tab, a shadow, ...). Only the current
    // member paints (draw() still checks groupCurrent()); the reserved space is
    // shared by the whole group anyway.
    const auto                 TOTAL      = HEIGHT + (wantsTabbar() ? tabHeight() : 0);

    SDecorationPositioningInfo info;
    info.policy         = m_hidden ? DECORATION_POSITION_ABSOLUTE : DECORATION_POSITION_STICKY;
    info.edges          = DECORATION_EDGE_TOP;
    info.priority       = PRECEDENCE ? 10005 : 5000;
    info.reserved       = true;
    info.desiredExtents = {{0, (m_hidden || !ENABLED) ? 0 : TOTAL}, {0, 0}};
    return info;
}

void CHyprBar::onPositioningReply(const SDecorationPositioningReply& reply) {
    if (reply.assignedGeometry.size() != m_bAssignedBox.size())
        m_bWindowSizeChanged = true;

    m_bAssignedBox = reply.assignedGeometry;
}

std::string CHyprBar::getDisplayName() {
    return "Hyprbar";
}

bool CHyprBar::inputIsValid() {
    if (m_hidden || !xModeEnabled())
        return false;

    if (g_pSeatManager->m_seatGrab && !g_pSeatManager->m_seatGrab->accepts(m_pWindow->wlSurface()->resource()))
        return false;

    const auto MOUSE    = g_pInputManager->getMouseCoordsInternal();
    auto       PMONITOR = Desktop::focusState()->monitor();

    if (!PMONITOR)
        return false;

    Desktop::CViewHitTester hitTester{*Desktop::viewState()};

    const auto              WINDOWATCURSOR = hitTester.windowAt(MOUSE, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS | Desktop::View::ALLOW_FLOATING);

    // Only the bar of the window actually under the cursor may handle input.
    // Upstream also accepted the focused window even when the cursor was over a
    // different window, so with overlapping floating windows a click on the top
    // window's tabbar was handled by the focused (behind) window too.
    if (WINDOWATCURSOR != m_pWindow)
        return false;

    PHLLS    foundSurface = nullptr;
    Vector2D surfaceCoords;

    // Check Top Layer
    hitTester.layerSurfaceAt(MOUSE, &PMONITOR->m_layerSurfaceLayers[ZWLR_LAYER_SHELL_V1_LAYER_TOP], &surfaceCoords, &foundSurface);
    if (foundSurface)
        return false;

    // Check Overlay Layer
    hitTester.layerSurfaceAt(MOUSE, &PMONITOR->m_layerSurfaceLayers[ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY], &surfaceCoords, &foundSurface);
    if (foundSurface)
        return false;

    return true;
}

void CHyprBar::onMouseButton(Event::SCallbackInfo& info, IPointer::SButtonEvent e) {
    if (e.state != WL_POINTER_BUTTON_STATE_PRESSED) {
        // A fresh press may be handled again.
        g_lastPressTime   = 0;
        g_lastPressButton = 0;
        // Always finish if we cancelled the down (titlebar click/drag), even
        // when the cursor is now over a layer surface. The drag session itself
        // also ends on any mouse-up, so snap still runs if focus moved away.
        if (m_bDraggingThis || m_bDragPending || m_bCancelledDown)
            handleUpEvent(info);
        else if (inputIsValid())
            handleUpEvent(info);
        return;
    }

    // A single physical press reaches every bar. Only the first bar that can
    // handle it (the window actually under the cursor) may act: otherwise
    // handling it can change focus/stacking, a later bar then becomes valid for
    // the very same click and steals it (e.g. clicking a foot tab focused
    // chromium).
    if (g_lastPressTime == e.timeMs && g_lastPressButton == e.button)
        return;

    if (!inputIsValid())
        return;

    g_lastPressTime   = e.timeMs;
    g_lastPressButton = e.button;
    handleDownEvent(info, std::nullopt, e.button);
}

void CHyprBar::onTouchDown(Event::SCallbackInfo& info, ITouch::SDownEvent e) {
    // Don't do anything if you're already grabbed a window with another finger
    if (!inputIsValid() || e.touchID != 0)
        return;

    handleDownEvent(info, e);
}

void CHyprBar::onTouchUp(Event::SCallbackInfo& info, ITouch::SUpEvent e) {
    if (!m_bDragPending || !m_bTouchEv || e.touchID != m_touchId)
        return;

    handleUpEvent(info);
}

void CHyprBar::onMouseMove(Vector2D coords) {
    // ensure proper redraws of button icons on hover when using hardware cursors
    if (g_pGlobalState->config.iconOnHover->value())
        damageOnButtonHover();

    if (m_bTouchEv || !validMapped(m_pWindow) || m_touchId != 0)
        return;

    if (m_bDragPending) {
        m_bDragPending = false;
        handleMovement();
    }

    if (m_bTabDragPending)
        updateTabDrag(coords);

    // Mouse titlebar drag is driven by CDragSession (global mouse-move listener)
    // so it keeps going if focus or the pointer leaves this bar. Touch still
    // uses the per-bar path below.
    if (m_bDraggingThis && m_bTouchEv)
        moveDragWindow(coords);
}

void CHyprBar::onTouchMove(Event::SCallbackInfo& info, ITouch::SMotionEvent e) {
    if (!m_bDragPending || !m_bTouchEv || !validMapped(m_pWindow) || e.touchID != m_touchId)
        return;

    auto PMONITOR     = m_pWindow->m_monitor.lock();
    PMONITOR          = PMONITOR ? PMONITOR : Desktop::focusState()->monitor();
    const auto COORDS = Vector2D(PMONITOR->m_position.x + e.pos.x * PMONITOR->m_size.x, PMONITOR->m_position.y + e.pos.y * PMONITOR->m_size.y);

    if (!m_bDraggingThis) {
        // Initial setup for dragging a window.
        g_pKeybindManager->m_dispatchers["setfloating"]("activewindow");
        g_pKeybindManager->m_dispatchers["resizewindowpixel"]("exact 50% 50%,activewindow");
        // pin it so you can change workspaces while dragging a window
        g_pKeybindManager->m_dispatchers["pin"]("activewindow");
    }
    g_pKeybindManager->m_dispatchers["movewindowpixel"](std::format("exact {} {},activewindow", (int)(COORDS.x - (assignedBoxGlobal().w / 2)), (int)COORDS.y));
    m_bDraggingThis = true;
}

void CHyprBar::handleDownEvent(Event::SCallbackInfo& info, std::optional<ITouch::SDownEvent> touchEvent, uint32_t button) {
    m_bTouchEv = touchEvent.has_value();
    if (m_bTouchEv)
        m_touchId = touchEvent.value().touchID;

    const auto PWINDOW = m_pWindow.lock();

    auto       COORDS = cursorRelativeToBar();
    if (m_bTouchEv) {
        ITouch::SDownEvent e        = touchEvent.value();
        PHLMONITOR         PMONITOR = nullptr;
        for (auto& m : State::monitorState()->monitors()) {
            if (m->m_name == (!e.device->m_boundOutput.empty() ? e.device->m_boundOutput : "")) {
                PMONITOR = m;
                break;
            }
        }
        PMONITOR = PMONITOR ? PMONITOR : Desktop::focusState()->monitor();
        COORDS   = Vector2D(PMONITOR->m_position.x + e.pos.x * PMONITOR->m_size.x, PMONITOR->m_position.y + e.pos.y * PMONITOR->m_size.y) - assignedBoxGlobal().pos();
    }

    const auto HEIGHT           = g_pGlobalState->config.barHeight->value();
    const auto BARBUTTONPADDING = g_pGlobalState->config.barButtonPadding->value();
    const auto BARPADDING       = g_pGlobalState->config.barPadding->value();
    const auto ALIGNBUTTONS     = g_pGlobalState->config.barButtonsAlignment->value();
    const auto ON_DOUBLE_CLICK  = g_pGlobalState->config.onDoubleClick->value();

    const bool BUTTONSRIGHT = ALIGNBUTTONS != "left";

    if (!VECINRECT(COORDS, 0, 0, assignedBoxGlobal().w, HEIGHT + (wantsTabbar() ? tabHeight() : 0) - 1)) {

        if (m_bDraggingThis) {
            if (m_bTouchEv)
                g_pKeybindManager->m_dispatchers["settiled"]("activewindow");
            g_pKeybindManager->m_dispatchers["mouse"]("0movewindow");
            Log::logger->log(Log::DEBUG, "[hyprbars] Dragging ended on {:x}", (uintptr_t)PWINDOW.get());
        }

        m_bDraggingThis = false;
        m_bDragPending  = false;
        m_bDragActive   = false;
        m_bTouchEv      = false;
        return;
    }

    // Dismiss dropdowns / popups: clicking on the window decoration should close
    // any open menus / xdg_popups immediately.
    g_pSeatManager->setGrab(nullptr);

    // Custom tabbar: handle a tab click before focusing the window, so a tab
    // switch is a single focus change (to the target) instead of focusing the
    // current window first and then the target (which flashes two borders).
    bool      closeHit = false;
    const int TAB      = tabAt(COORDS, closeHit);
    if (TAB == -2 && (m_bTouchEv || button == 272)) {
        info.cancelled   = true;
        m_bCancelledDown = true;
        std::string cls = PWINDOW->m_initialClass.empty() ? PWINDOW->m_class : PWINDOW->m_initialClass;
        if (!cls.empty()) {
            // Same launcher the dock uses: desktop-id == window class for most apps.
            g_pKeybindManager->m_dispatchers["exec"](std::format("gtk-launch {}", cls));
        }
        return;
    }
    if (TAB >= 0 && (m_bTouchEv || button == 272)) {
        info.cancelled   = true;
        m_bCancelledDown = true;
        PHLWINDOW target;
        if (PWINDOW->m_group) {
            const auto MEMBERS = PWINDOW->m_group->windows();
            if (TAB < (int)MEMBERS.size())
                target = MEMBERS[TAB].lock();
        } else if (TAB == 0)
            target = PWINDOW;
        if (target) {
            if (closeHit) {
                // Just close: the window.close listener keeps focus and stacking
                // in the group (keepGroupFocusOnClose).
                g_pXWaylandManager->sendCloseWindow(target);
            } else if (PWINDOW->m_group && PWINDOW->m_group->size() > 1) {
                // Don't switch yet: a small move turns this into a reorder. The
                // switch happens on release if the pointer never left the tab.
                m_bTabDragPending = true;
                m_bTabDragging    = false;
                m_iTabDragFrom    = TAB;
                m_iTabDragOver    = TAB;
                m_tabDragStart    = g_pInputManager->getMouseCoordsInternal();
            }
        }
        return;
    }

    if (Desktop::focusState()->window() != PWINDOW)
        Desktop::focusState()->fullWindowFocus(PWINDOW, Desktop::FOCUS_REASON_CLICK);

    if (PWINDOW->m_isFloating)
        Desktop::windowState()->raise(PWINDOW);

    info.cancelled   = true;
    m_bCancelledDown = true;

    // Right-click (and anything but left / touch) focuses and raises, but must
    // not start a drag: the session only ends on button 272, so RMB would keep
    // the window glued to the cursor until the next LMB.
    if (!m_bTouchEv && button != 272)
        return;

    if (doButtonPress(BARPADDING, BARBUTTONPADDING, HEIGHT, COORDS, BUTTONSRIGHT))
        return;

    if (!ON_DOUBLE_CLICK.empty() &&
        std::chrono::duration_cast<std::chrono::milliseconds>(Time::steadyNow() - m_lastMouseDown).count() < 400 /* Arbitrary delay I found suitable */) {
        Config::Supplementary::executor()->spawn(ON_DOUBLE_CLICK);
        m_bDragPending = false;
    } else {
        m_lastMouseDown = Time::steadyNow();
        if (m_bTouchEv)
            m_bDragPending = true;
        else if (g_pDragSession)
            g_pDragSession->begin(PWINDOW);
    }
}

void CHyprBar::handleUpEvent(Event::SCallbackInfo& info) {
    if (m_bTabDragPending) {
        // Released without ever crossing the drag threshold: it was a click, so
        // switch to the tab that was pressed. A reorder already happened live.
        const auto PWINDOW = m_pWindow.lock();
        if (!m_bTabDragging && PWINDOW && PWINDOW->m_group) {
            const auto MEMBERS = PWINDOW->m_group->windows();
            if (m_iTabDragFrom >= 0 && m_iTabDragFrom < (int)MEMBERS.size()) {
                if (const auto target = MEMBERS[m_iTabDragFrom].lock()) {
                    if (target != PWINDOW->m_group->current())
                        PWINDOW->m_group->setCurrent(target);
                    if (Desktop::focusState()->window() != target)
                        Desktop::focusState()->rawWindowFocus(target, Desktop::FOCUS_REASON_CLICK);
                    if (target->m_isFloating)
                        Desktop::windowState()->raise(target);
                }
            }
        }
        m_bTabDragPending = false;
        m_bTabDragging    = false;
        m_iTabDragFrom    = -1;
        m_iTabDragOver    = -1;
        info.cancelled    = true;
        m_bCancelledDown  = false;
        m_bTouchEv        = false;
        return;
    }

    if (m_pWindow.lock() != Desktop::focusState()->window() && !m_bDraggingThis && !m_bCancelledDown && !m_bDragPending)
        return;

    if (m_bCancelledDown)
        info.cancelled = true;

    m_bCancelledDown = false;

    if (m_bDraggingThis) {
        g_pKeybindManager->changeMouseBindMode(MBIND_INVALID);
        m_bDraggingThis = false;
        m_bDragActive   = false;
        if (m_bTouchEv)
            (void)Config::Actions::floatWindow(Config::Actions::eTogglableAction::TOGGLE_ACTION_DISABLE);

        Log::logger->log(Log::DEBUG, "[hyprbars] Dragging ended on {:x}", (uintptr_t)m_pWindow.lock().get());
    }

    m_bDragPending = false;
    m_bTouchEv     = false;
    m_touchId      = 0;
}

void CHyprBar::handleMovement() {
    // Touch path only. Mouse titlebar drag is CDragSession (global listeners).
    m_bDraggingThis   = true;
    m_bDragActive     = false;
    m_dragStartCursor = g_pInputManager->getMouseCoordsInternal();
    Log::logger->log(Log::DEBUG, "[hyprbars] Dragging initiated on {:x}", (uintptr_t)m_pWindow.lock().get());
    return;
}

void CHyprBar::moveDragWindow(const Vector2D& coords) {
    static auto PDRAGTHRESHOLD = CConfigValue<Config::INTEGER>("binds:drag_threshold");

    const auto PWINDOW = m_pWindow.lock();
    // Group target owns the geometry; move it, not the window target.
    const auto TARGET = PWINDOW->layoutTarget();
    if (!PWINDOW || !TARGET || !TARGET->floating())
        return;

    // ignore the first few pixels of motion (like Hyprland's drag threshold),
    // then re-anchor so the window does not jump.
    if (!m_bDragActive) {
        if (std::abs(coords.x - m_dragStartCursor.x) < *PDRAGTHRESHOLD && std::abs(coords.y - m_dragStartCursor.y) < *PDRAGTHRESHOLD)
            return;
        m_bDragActive   = true;
        m_dragAnchor    = coords;
        m_dragWindowPos = TARGET->position().pos();
        return;
    }

    const auto DELTA  = coords - m_dragAnchor;
    auto       newPos = m_dragWindowPos + DELTA;

    const auto MON = PWINDOW->m_monitor.lock();
    if (MON) {
        const auto TOP    = MON->m_reservedArea.top();
        const auto CHROME = (double)Snap::chromeH(PWINDOW);
        const auto LIMIT  = TOP + (double)Snap::border();
        if (newPos.y - CHROME < LIMIT)
            newPos.y = LIMIT + CHROME;
    }

    Snap::moveDrag(PWINDOW, newPos);
}

bool CHyprBar::doButtonPress(Config::INTEGER barPadding, Config::INTEGER barButtonPadding, Config::INTEGER barHeight, Vector2D COORDS, const bool BUTTONSRIGHT) {
    //check if on a button
    float offset = barPadding;

    for (auto& b : g_pGlobalState->buttons) {
        const auto BARBUF     = Vector2D{(int)assignedBoxGlobal().w, barHeight};
        Vector2D   currentPos = Vector2D{(BUTTONSRIGHT ? BARBUF.x - barButtonPadding - b.size - offset : offset), (BARBUF.y - b.size) / 2.0}.floor();

        if (VECINRECT(COORDS, currentPos.x, currentPos.y, currentPos.x + b.size + barButtonPadding, currentPos.y + b.size)) {
            // hit on close
            g_pKeybindManager->m_dispatchers["exec"](b.cmd);
            return true;
        }

        offset += barButtonPadding + b.size;
    }
    return false;
}

void CHyprBar::renderBarTitle(const Vector2D& bufferSize, const float scale) {
    const auto COLORVAL         = g_pGlobalState->config.textColor->value();
    const auto SIZE             = g_pGlobalState->config.barTextSize->value();
    const auto WEIGHT           = g_pGlobalState->config.barTextWeight->value();
    const auto FONT             = g_pGlobalState->config.barTextFont->value();
    const auto ALIGN            = g_pGlobalState->config.barTextAlign->value();
    const auto BARPADDING       = g_pGlobalState->config.barPadding->value();
    const auto BARBUTTONPADDING = g_pGlobalState->config.barButtonPadding->value();

    float      buttonSizes = BARBUTTONPADDING;
    for (auto& b : g_pGlobalState->buttons) {
        buttonSizes += b.size + BARBUTTONPADDING;
    }

    const int  scaledSize        = std::round(SIZE * scale);
    const auto scaledButtonsSize = buttonSizes * scale;
    const auto scaledBarPadding  = BARPADDING * scale;
    const int  paddingTotal      = scaledBarPadding * 2 + scaledButtonsSize + (ALIGN != "left" ? scaledButtonsSize : 0);
    const int  maxWidth          = std::clamp(static_cast<int>(bufferSize.x - paddingTotal), 0, INT_MAX);

    if (m_szLastTitle.empty() || maxWidth < 1) {
        m_pTextTex = nullptr;
        return;
    }

    const CHyprColor COLOR = m_bForcedTitleColor.value_or(configColor(COLORVAL));
    m_pTextTex             = g_pHyprRenderer->renderText(m_szLastTitle, COLOR, scaledSize, false, FONT, maxWidth, WEIGHT.m_value);
}

size_t CHyprBar::getVisibleButtonCount(Config::INTEGER barButtonPadding, Config::INTEGER barPadding, const Vector2D& bufferSize, const float scale) {
    float  availableSpace = bufferSize.x - barPadding * scale * 2;
    size_t count          = 0;

    for (const auto& button : g_pGlobalState->buttons) {
        const float buttonSpace = (button.size + barButtonPadding) * scale;
        if (availableSpace >= buttonSpace) {
            count++;
            availableSpace -= buttonSpace;
        } else
            break;
    }

    return count;
}

void CHyprBar::renderBarButtons(CBox* barBox, const float scale, const float a) {
    const auto BARBUTTONPADDING = g_pGlobalState->config.barButtonPadding->value();
    const auto BARPADDING       = g_pGlobalState->config.barPadding->value();
    const auto ALIGNBUTTONS     = g_pGlobalState->config.barButtonsAlignment->value();
    const auto INACTIVECOLOR    = g_pGlobalState->config.inactiveButtonColor->value();

    const bool BUTTONSRIGHT    = ALIGNBUTTONS != "left";
    const auto visibleCount    = getVisibleButtonCount(BARBUTTONPADDING, BARPADDING, Vector2D{barBox->w, barBox->h}, scale);
    const bool INVALIDATEICONS = m_bButtonsDirty || m_bWindowSizeChanged;

    int        offset = BARPADDING * scale;
    for (size_t i = 0; i < visibleCount; ++i) {
        auto&      button           = g_pGlobalState->buttons[i];
        const auto scaledButtonSize = button.size * scale;
        const auto scaledButtonsPad = BARBUTTONPADDING * scale;

        auto       color = button.bgcol;

        if (INACTIVECOLOR > 0) {
            color = m_bWindowHasFocus ? color : configColor(INACTIVECOLOR);
            if (INVALIDATEICONS && button.userfg && button.iconTex)
                button.iconTex = nullptr;
        }

        color.a *= a;

        CBox buttonBox = {barBox->x + (BUTTONSRIGHT ? barBox->w - offset - scaledButtonSize : offset), barBox->y + (barBox->h - scaledButtonSize) / 2.0, scaledButtonSize,
                          scaledButtonSize};
        buttonBox.round();

        g_pHyprOpenGL->renderRect(buttonBox, color, {.round = static_cast<int>(std::round(scaledButtonSize / 2.0)), .roundingPower = 2.F});

        offset += scaledButtonsPad + scaledButtonSize;
    }
}

void CHyprBar::renderBarButtonsText(CBox* barBox, const float scale, const float a) {
    const auto HEIGHT           = g_pGlobalState->config.barHeight->value();
    const auto BARBUTTONPADDING = g_pGlobalState->config.barButtonPadding->value();
    const auto BARPADDING       = g_pGlobalState->config.barPadding->value();
    const auto ALIGNBUTTONS     = g_pGlobalState->config.barButtonsAlignment->value();
    const auto ICONONHOVER      = g_pGlobalState->config.iconOnHover->value();

    const bool BUTTONSRIGHT = ALIGNBUTTONS != "left";
    const auto visibleCount = getVisibleButtonCount(BARBUTTONPADDING, BARPADDING, Vector2D{barBox->w, barBox->h}, scale);
    const auto COORDS       = cursorRelativeToBar();

    int        offset        = BARPADDING * scale;
    float      noScaleOffset = BARPADDING;

    for (size_t i = 0; i < visibleCount; ++i) {
        auto&      button           = g_pGlobalState->buttons[i];
        const auto scaledButtonSize = button.size * scale;
        const auto scaledButtonsPad = BARBUTTONPADDING * scale;

        // check if hovering here
        const auto BARBUF     = Vector2D{(int)assignedBoxGlobal().w, HEIGHT};
        Vector2D   currentPos = Vector2D{(BUTTONSRIGHT ? BARBUF.x - BARBUTTONPADDING - button.size - noScaleOffset : noScaleOffset), (BARBUF.y - button.size) / 2.0}.floor();
        bool       hovering   = VECINRECT(COORDS, currentPos.x, currentPos.y, currentPos.x + button.size + BARBUTTONPADDING, currentPos.y + button.size);
        noScaleOffset += BARBUTTONPADDING + button.size;

        if ((!button.iconTex || button.iconTex->m_texID == 0) && !button.icon.empty()) {
            // render icon
            auto fgcol = button.userfg ? button.fgcol : (button.bgcol.r + button.bgcol.g + button.bgcol.b < 1) ? CHyprColor(0xFFFFFFFF) : CHyprColor(0xFF000000);

            button.iconTex = g_pHyprRenderer->renderText(button.icon, fgcol, std::round(button.size * 0.62 * scale), false, "sans", scaledButtonSize);
        }

        if (!button.iconTex || button.iconTex->m_texID == 0)
            continue;

        const auto iconX = barBox->x + (BUTTONSRIGHT ? barBox->width - offset - scaledButtonSize / 2.0 : offset + scaledButtonSize / 2.0) - button.iconTex->m_size.x / 2.0;
        const auto iconY = barBox->y + barBox->height / 2.0 - button.iconTex->m_size.y / 2.0;
        CBox       pos   = {iconX, iconY, button.iconTex->m_size.x, button.iconTex->m_size.y};

        if (!ICONONHOVER || (ICONONHOVER && m_iButtonHoverState > 0))
            g_pHyprOpenGL->renderTexture(button.iconTex, pos, {.a = a});
        offset += scaledButtonsPad + scaledButtonSize;

        bool currentBit = (m_iButtonHoverState & (1 << i)) != 0;
        if (hovering != currentBit) {
            m_iButtonHoverState ^= (1 << i);
            // damage to get rid of some artifacts when icons are "hidden"
            damageEntire();
        }
    }
}

static constexpr double TAB_PLUS_W      = 34.0;
// Positive shifts the + right inside its slot. Tweak this, not the draw math.
static constexpr double TAB_PLUS_NUDGE  = 0.0;

int CHyprBar::tabAt(const Vector2D& coords, bool& closeHit) {
    closeHit = false;
    const auto PWINDOW = m_pWindow.lock();
    if (!PWINDOW || !wantsTabbar())
        return -1;

    const auto HEIGHT = g_pGlobalState->config.barHeight->value();
    if (coords.y < HEIGHT || coords.y >= HEIGHT + tabHeight())
        return -1;

    const double W = assignedBoxGlobal().w;
    if (W < 1)
        return -1;

    if (coords.x >= W - TAB_PLUS_W)
        return -2; // + button: open another window of this app

    const int N = PWINDOW->m_group ? (int)PWINDOW->m_group->windows().size() : 1;
    if (N <= 0)
        return -1;

    const double TABW = (W - TAB_PLUS_W) / N;
    int          idx  = coords.x / TABW;
    if (idx < 0)
        idx = 0;
    if (idx >= N)
        idx = N - 1;

    if (coords.x >= idx * TABW + TABW - 24) {
        // With tab_close_active_only the ✕ only acts on the current tab of a
        // focused group; anywhere else the click focuses/switches instead, so it
        // cannot close a tab the user was not looking at.
        if (!g_pGlobalState->config.tabCloseActiveOnly->value()) {
            closeHit = true;
        } else if (PWINDOW == Desktop::focusState()->window()) {
            PHLWINDOW  target;
            if (PWINDOW->m_group) {
                const auto MEMBERS = PWINDOW->m_group->windows();
                if (idx < (int)MEMBERS.size())
                    target = MEMBERS[idx].lock();
            } else if (idx == 0) {
                target = PWINDOW;
            }
            const auto CURRENT = PWINDOW->m_group ? PWINDOW->m_group->current() : PWINDOW;
            if (target && target == CURRENT)
                closeHit = true;
        }
    }
    return idx;
}

void CHyprBar::updateTabDrag(const Vector2D& coords) {
    const auto PWINDOW = m_pWindow.lock();
    if (!PWINDOW || !PWINDOW->m_group) {
        m_bTabDragPending = false;
        return;
    }
    auto& group = PWINDOW->m_group;

    static auto PDRAGTHRESHOLD = CConfigValue<Config::INTEGER>("binds:drag_threshold");
    if (!m_bTabDragging) {
        const auto delta = g_pInputManager->getMouseCoordsInternal() - m_tabDragStart;
        if (std::abs(delta.x) <= *PDRAGTHRESHOLD)
            return;
        // swapWithNext / swapWithLast only move the current tab, so the dragged
        // one has to be current before it can walk anywhere.
        if (group->getCurrentIdx() != (size_t)m_iTabDragFrom)
            group->setCurrent((size_t)m_iTabDragFrom);
        m_bTabDragging = true;
        // The lifted tab is drawn wherever the pointer is, so it needs a
        // repaint on every move, not only when it changes slot.
        damageEntire();
    }

    bool      closeHit = false;
    const int over     = tabAt(cursorRelativeToBar(), closeHit);
    if (over < 0 || over == m_iTabDragOver)
        return;

    const int dir = over > m_iTabDragOver ? 1 : -1;
    while (m_iTabDragOver != over) {
        if (dir > 0)
            group->swapWithNext();
        else
            group->swapWithLast();
        m_iTabDragOver += dir;
    }
    damageEntire();
}

void CHyprBar::renderTabs(CBox* barBox, const float scale, const float a) {
    const auto PWINDOW = m_pWindow.lock();
    if (!PWINDOW || !wantsTabbar())
        return;

    std::vector<PHLWINDOWREF> solo;
    if (!PWINDOW->m_group)
        solo.push_back(PWINDOW);
    const auto& members = PWINDOW->m_group ? PWINDOW->m_group->windows() : solo;
    const int N = (int)members.size();

    const auto HEIGHT = g_pGlobalState->config.barHeight->value();
    // Highlight the group's current tab, not the globally focused window: the
    // tabbar is drawn by the group's current window, so it must stay highlighted
    // even when another app has focus.
    const auto CURRENT = PWINDOW->m_group ? PWINDOW->m_group->current() : PWINDOW;
    const auto FONT    = g_pGlobalState->config.barTextFont->value();

    // Tabs follow the titlebar palette (the Lua config sets bar_color/col.text
    // from the Omarchy theme), so switching theme recolors the whole chrome.
    const CHyprColor BASE  = configColor(g_pGlobalState->config.barColor->value());
    const CHyprColor TEXT  = configColor(g_pGlobalState->config.textColor->value());
    const CHyprColor ROW   = CHyprColor(BASE.r * 0.60, BASE.g * 0.60, BASE.b * 0.60, BASE.a);
    const CHyprColor TABIN = CHyprColor(BASE.r * 0.78, BASE.g * 0.78, BASE.b * 0.78, BASE.a);
    // Contrast between the current tab and the rest comes from the text color,
    // not the weight: lift the current tab toward white, pull the others toward
    // the tab background so they read dimmer.
    const CHyprColor TXTACT = CHyprColor(TEXT.r + (1.F - TEXT.r) * 0.35F, TEXT.g + (1.F - TEXT.g) * 0.35F, TEXT.b + (1.F - TEXT.b) * 0.35F, 1.F);
    const CHyprColor TXTIN  = CHyprColor(TEXT.r + (BASE.r - TEXT.r) * 0.45F, TEXT.g + (BASE.g - TEXT.g) * 0.45F, TEXT.b + (BASE.b - TEXT.b) * 0.45F, 1.F);
    const CHyprColor CLOSE  = CHyprColor(TXTACT.r, TXTACT.g, TXTACT.b, 0.9F);
    // tab_close_active_only: draw the ✕ only on the current tab, and only while
    // the group has focus. Without it every tab keeps its ✕ as before.
    const bool CLOSEACTIVEONLY = g_pGlobalState->config.tabCloseActiveOnly->value();
    const bool WINDOWFOCUSED   = PWINDOW == Desktop::focusState()->window();

    const double W = assignedBoxGlobal().w;
    if (W < 1)
        return;
    const double TABW = N > 0 ? (W - TAB_PLUS_W) / N : 0;
    // The title texture is cached per bar (only the current member draws the
    // tabbar), so the key must include the geometry that decides the ellipsis:
    // each window's bar would otherwise keep the truncation of an older N/width
    // and switching tabs changed how short every tab's text looked.
    const int TAB_FONT = (int)std::round(11 * scale);
    const int TAB_MAXW = (int)(TABW * scale) - (int)(28 * scale);
    // Tabs follow the titlebar weight; the same weight for every tab.
    const int TAB_WEIGHT = g_pGlobalState->config.barTextWeight->value().m_value;

    CBox rowBox = {barBox->x, barBox->y + (int)(HEIGHT * scale), (int)(W * scale), (int)(tabHeight() * scale)};
    g_pHyprOpenGL->renderRect(rowBox, CHyprColor(ROW.r, ROW.g, ROW.b, ROW.a * a), {});

    // The dragged tab leaves its slot, so the row shows a gap there and the tab
    // itself is painted on top, shifted toward the pointer.
    const bool dragging = m_bTabDragging && m_iTabDragOver >= 0 && m_iTabDragOver < N;

    for (int i = 0; i < N; i++) {
        auto m = members[i].lock();
        if (!m)
            continue;

        const bool ISACTIVE = (N <= 1) || (m == CURRENT);
        CBox       tabBox   = {barBox->x + (int)(i * TABW * scale), barBox->y + (int)(HEIGHT * scale), (int)(TABW * scale) - 1, (int)(tabHeight() * scale)};
        if (dragging && i == m_iTabDragOver)
            continue;
        g_pHyprOpenGL->renderRect(tabBox, ISACTIVE ? CHyprColor(BASE.r, BASE.g, BASE.b, BASE.a * a) : CHyprColor(TABIN.r, TABIN.g, TABIN.b, TABIN.a * a), {});

        const std::string title = m->m_title;
        const std::string key   = std::to_string(TAB_MAXW) + ":" + std::to_string(TAB_FONT) + ":" + (ISACTIVE ? "1:" : "0:") + title;
        auto              it    = m_tabTexs.find(key);
        if (it == m_tabTexs.end()) {
            auto tex = g_pHyprRenderer->renderText(title, ISACTIVE ? TXTACT : TXTIN, TAB_FONT, false, FONT, TAB_MAXW, TAB_WEIGHT);
            it       = m_tabTexs.emplace(key, tex).first;
        }
        if (it->second && it->second->m_texID != 0) {
            // Integer device-pixel position: a half-pixel offset makes the
            // GL_LINEAR texture sample between texels and the text looks blurred.
            CBox titleBox = {tabBox.x + (int)(8 * scale), tabBox.y + (int)std::round((tabBox.h - it->second->m_size.y) / 2.0), it->second->m_size.x, it->second->m_size.y};
            g_pHyprOpenGL->renderTexture(it->second, titleBox, {.a = a});
        }

        if (!CLOSEACTIVEONLY || (WINDOWFOCUSED && ISACTIVE)) {
            const std::string xkey = "x:" + std::to_string(TAB_FONT) + ":" + std::to_string((int)(16 * scale));
            auto              xit  = m_tabTexs.find(xkey);
            if (xit == m_tabTexs.end()) {
                auto tex = g_pHyprRenderer->renderText("✕", CLOSE, TAB_FONT, false, FONT, (int)(16 * scale));
                xit      = m_tabTexs.emplace(xkey, tex).first;
            }
            if (xit->second && xit->second->m_texID != 0) {
                CBox xBox = {tabBox.x + tabBox.w - (int)(18 * scale), tabBox.y + (int)std::round((tabBox.h - xit->second->m_size.y) / 2.0), xit->second->m_size.x, xit->second->m_size.y};
                g_pHyprOpenGL->renderTexture(xit->second, xBox, {.a = a});
            }
        }
    }

    // The lifted tab. Its slot was skipped above, so it has to be drawn here,
    // shifted by how far the pointer has moved but kept inside the row.
    if (dragging) {
        auto dragged = members[m_iTabDragOver].lock();
        if (dragged) {
            const double home  = m_iTabDragOver * TABW;
            const double delta = cursorRelativeToBar().x - (m_tabDragStart.x - assignedBoxGlobal().pos().x);
            double       x     = home + delta;
            x                  = std::clamp(x, 0.0, std::max(0.0, W - TAB_PLUS_W - TABW));

            CBox tabBox = {barBox->x + (int)std::round(x * scale), barBox->y + (int)(HEIGHT * scale), (int)(TABW * scale) - 1, (int)(tabHeight() * scale)};
            g_pHyprOpenGL->renderRect(tabBox, CHyprColor(BASE.r, BASE.g, BASE.b, BASE.a * a), {});

            const std::string title = dragged->m_title;
            const std::string key   = std::to_string(TAB_MAXW) + ":" + std::to_string(TAB_FONT) + ":1:" + title;
            auto              it    = m_tabTexs.find(key);
            if (it == m_tabTexs.end()) {
                auto tex = g_pHyprRenderer->renderText(title, TXTACT, TAB_FONT, false, FONT, TAB_MAXW, TAB_WEIGHT);
                it       = m_tabTexs.emplace(key, tex).first;
            }
            if (it->second && it->second->m_texID != 0) {
                CBox titleBox = {tabBox.x + (int)(8 * scale), tabBox.y + (int)std::round((tabBox.h - it->second->m_size.y) / 2.0), it->second->m_size.x, it->second->m_size.y};
                g_pHyprOpenGL->renderTexture(it->second, titleBox, {.a = a});
            }
        }
    }

    CBox plusBox = {barBox->x + (int)((W - TAB_PLUS_W) * scale), barBox->y + (int)(HEIGHT * scale), (int)(TAB_PLUS_W * scale), (int)(tabHeight() * scale)};
    g_pHyprOpenGL->renderRect(plusBox, CHyprColor(TABIN.r, TABIN.g, TABIN.b, TABIN.a * a), {});
    const double arm    = std::round(8.0 * scale);
    const double thick  = std::max(1.0, std::round(1.5 * scale));
    const double cx     = plusBox.x + plusBox.w / 2.0 + TAB_PLUS_NUDGE * scale;
    const double cy     = plusBox.y + plusBox.h / 2.0;
    const CHyprColor plusCol{TEXT.r, TEXT.g, TEXT.b, TEXT.a * a};
    // Snap the bars to whole pixels so the thin strokes stay crisp.
    g_pHyprOpenGL->renderRect(CBox{std::round(cx - arm / 2.0), std::round(cy - thick / 2.0), arm, thick}, plusCol, {});
    g_pHyprOpenGL->renderRect(CBox{std::round(cx - thick / 2.0), std::round(cy - arm / 2.0), thick, arm}, plusCol, {});
}

void CHyprBar::applyEnabled() {
    m_bLastEnabledState = g_pGlobalState->config.enabled->value() && xModeEnabled();
    g_pDecorationPositioner->repositionDeco(this);
    damageEntire();
}

void CHyprBar::draw(PHLMONITOR pMonitor, const float& a) {
    const auto ENABLED = g_pGlobalState->config.enabled->value() && xModeEnabled();
    if (m_bLastEnabledState != ENABLED)
        applyEnabled();

    // The tabbar now reserves the same extents for every group member
    // (getPositioningInfo() no longer depends on the current tab), so a tab
    // switch needs no reposition. It does change what we paint (title, which tab
    // is highlighted), and setCurrent() only damages the window box, not the bar
    // above it — so damage the bar when the current member changes.
    const auto PWINDOW   = m_pWindow.lock();
    const auto PCURRENT  = PWINDOW && PWINDOW->m_group ? PWINDOW->m_group->current() : PWINDOW;
    if (m_pLastGroupCurrent.lock() != PCURRENT) {
        m_pLastGroupCurrent = PCURRENT;
        damageEntire();
    }

    if (m_hidden || !validMapped(m_pWindow) || !ENABLED || !groupCurrent())
        return;

    if (!PWINDOW->m_ruleApplicator->decorate().valueOrDefault())
        return;

    auto data = CBarPassElement::SBarData{this, a};
    g_pHyprRenderer->m_renderPass.add(makeUnique<CBarPassElement>(data));
}

void CHyprBar::renderPass(PHLMONITOR pMonitor, const float& a) {
    const auto  PWINDOW = m_pWindow.lock();

    static auto PENABLEBLURGLOBAL = CConfigValue<Config::BOOL>("decoration:blur:enabled");
    const auto  BARCOLOR          = g_pGlobalState->config.barColor->value();
    const auto  HEIGHT            = g_pGlobalState->config.barHeight->value();
    const auto  PRECEDENCE        = g_pGlobalState->config.barPrecedenceOverBorder->value();
    const auto  ALIGNBUTTONS      = g_pGlobalState->config.barButtonsAlignment->value();
    const auto  ENABLETITLE       = g_pGlobalState->config.barTitleEnabled->value();
    const auto  ENABLEBLUR        = g_pGlobalState->config.barBlur->value();
    const auto  INACTIVECOLOR     = g_pGlobalState->config.inactiveButtonColor->value();

    const auto TABCLOSEACTIVEONLY = g_pGlobalState->config.tabCloseActiveOnly->value();

    if (INACTIVECOLOR > 0 || TABCLOSEACTIVEONLY) {
        bool currentWindowFocus = PWINDOW == Desktop::focusState()->window();
        if (currentWindowFocus != m_bWindowHasFocus) {
            m_bWindowHasFocus = currentWindowFocus;
            m_bButtonsDirty   = true;
            if (TABCLOSEACTIVEONLY)
                damageEntire();
        }
    }

    const CHyprColor DEST_COLOR = m_bForcedBarColor.value_or(configColor(BARCOLOR));
    if (DEST_COLOR != m_cRealBarColor->goal())
        *m_cRealBarColor = DEST_COLOR;

    CHyprColor color = m_cRealBarColor->value();

    color.a *= a;
    const bool BUTTONSRIGHT = ALIGNBUTTONS != "left";
    const bool SHOULDBLUR   = ENABLEBLUR && *PENABLEBLURGLOBAL && color.a < 1.F;

    if (HEIGHT < 1) {
        m_iLastHeight = HEIGHT;
        return;
    }

    const auto PWORKSPACE      = PWINDOW->m_workspace;
    const auto WORKSPACEOFFSET = PWORKSPACE && !PWINDOW->m_pinned ? PWORKSPACE->m_renderOffset->value() : Vector2D();

    const auto ROUNDING = PWINDOW->rounding() + (PRECEDENCE ? 0 : PWINDOW->getRealBorderSize());

    const auto scaledRounding = ROUNDING > 0 ? ROUNDING * pMonitor->m_scale - 2 /* idk why but otherwise it looks bad due to the gaps */ : 0;

    m_seExtents = {{0, HEIGHT}, {}};

    const auto DECOBOX = assignedBoxGlobal();

    const auto BARBUF = DECOBOX.size() * pMonitor->m_scale;

    CBox       titleBarBox = {DECOBOX.x - pMonitor->m_position.x, DECOBOX.y - pMonitor->m_position.y, DECOBOX.w,
                              HEIGHT + ROUNDING * 3 /* to fill the bottom cuz we can't disable rounding there */};

    titleBarBox.translate(PWINDOW->m_floatingOffset).scale(pMonitor->m_scale).round();

    if (titleBarBox.w < 1 || titleBarBox.h < 1)
        return;

    // (tim) Fill the window box with the bar color, so an app that paints late
    // (Chromium, LibreOffice) shows the theme background instead of the
    // wallpaper / white while it comes up. This pass element is on the UNDER
    // layer, so it sits behind the window content; drawn before the bar's
    // scissor so it can cover the content area below the bar.
    {
        CBox winBox = {PWINDOW->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT).x + PWINDOW->m_floatingOffset.x - pMonitor->m_position.x,
                       PWINDOW->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT).y + PWINDOW->m_floatingOffset.y - pMonitor->m_position.y,
                       PWINDOW->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT).x, PWINDOW->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT).y};
        winBox.scale(pMonitor->m_scale).round();
        if (winBox.w >= 1 && winBox.h >= 1)
            g_pHyprOpenGL->renderRect(winBox, color, {.round = scaledRounding, .roundingPower = PWINDOW->roundingPower()});
    }

    g_pHyprOpenGL->scissor(titleBarBox);

    if (ROUNDING) {
        // the +1 is a shit garbage temp fix until renderRect supports an alpha matte
        CBox windowBox = {PWINDOW->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT).x + PWINDOW->m_floatingOffset.x - pMonitor->m_position.x + 1,
                          PWINDOW->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT).y + PWINDOW->m_floatingOffset.y - pMonitor->m_position.y + 1,
                          PWINDOW->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT).x - 2, PWINDOW->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT).y - 2};

        if (windowBox.w < 1 || windowBox.h < 1)
            return;

        glClearStencil(0);
        glClear(GL_STENCIL_BUFFER_BIT);

        g_pHyprOpenGL->setCapStatus(GL_STENCIL_TEST, true);

        glStencilFunc(GL_ALWAYS, 1, -1);
        glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);

        glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);

        windowBox.translate(WORKSPACEOFFSET).scale(pMonitor->m_scale).round();
        g_pHyprOpenGL->renderRect(windowBox, CHyprColor(0, 0, 0, 0), {.round = scaledRounding, .roundingPower = m_pWindow->roundingPower()});
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);

        glStencilFunc(GL_NOTEQUAL, 1, -1);
        glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);
    }

    if (SHOULDBLUR)
        g_pHyprOpenGL->renderRect(titleBarBox, color, {.round = scaledRounding, .roundingPower = m_pWindow->roundingPower(), .blur = true, .blurA = a});
    else
        g_pHyprOpenGL->renderRect(titleBarBox, color, {.round = scaledRounding, .roundingPower = m_pWindow->roundingPower()});

    // render title
    if (ENABLETITLE && (m_szLastTitle != PWINDOW->m_title || m_bWindowSizeChanged || !m_pTextTex || m_pTextTex->m_texID == 0 || m_bTitleColorChanged)) {
        m_szLastTitle = PWINDOW->m_title;
        renderBarTitle(BARBUF, pMonitor->m_scale);
    }

    if (ROUNDING) {
        // cleanup stencil
        glClearStencil(0);
        glClear(GL_STENCIL_BUFFER_BIT);
        g_pHyprOpenGL->setCapStatus(GL_STENCIL_TEST, false);
        glStencilMask(-1);
        glStencilFunc(GL_ALWAYS, 1, 0xFF);
    }

    CBox textBox = {titleBarBox.x, titleBarBox.y, (int)BARBUF.x, (int)(HEIGHT * pMonitor->m_scale)};
    if (ENABLETITLE && m_pTextTex) {
        const auto BARPADDING       = g_pGlobalState->config.barPadding->value();
        const auto BARBUTTONPADDING = g_pGlobalState->config.barButtonPadding->value();
        const auto ALIGN            = g_pGlobalState->config.barTextAlign->value();

        float      buttonSizes = BARBUTTONPADDING;
        for (auto& b : g_pGlobalState->buttons) {
            buttonSizes += b.size + BARBUTTONPADDING;
        }

        const auto scaledBorderSize  = PWINDOW->getRealBorderSize() * pMonitor->m_scale;
        const auto scaledButtonsSize = buttonSizes * pMonitor->m_scale;
        const auto scaledBarPadding  = BARPADDING * pMonitor->m_scale;
        const auto xOffset           = ALIGN == "left" ? std::round(scaledBarPadding + (BUTTONSRIGHT ? 0 : scaledButtonsSize)) :
                                                         std::round(((BARBUF.x - scaledBorderSize) / 2.0 - m_pTextTex->m_size.x / 2.0));
        const auto yOffset           = std::round((HEIGHT * pMonitor->m_scale - m_pTextTex->m_size.y) / 2.0);
        CBox       titleBox          = {textBox.x + xOffset, textBox.y + yOffset, m_pTextTex->m_size.x, m_pTextTex->m_size.y};

        g_pHyprOpenGL->renderTexture(m_pTextTex, titleBox, {.a = a});
    }

    renderBarButtons(&textBox, pMonitor->m_scale, a);
    m_bButtonsDirty = false;

    g_pHyprOpenGL->scissor(nullptr);

    renderTabs(&textBox, pMonitor->m_scale, a);

    renderBarButtonsText(&textBox, pMonitor->m_scale, a);

    m_bWindowSizeChanged = false;
    m_bTitleColorChanged = false;

    // dynamic updates change the extents
    if (m_iLastHeight != HEIGHT) {
        PWINDOW->layoutTarget()->recalc();
        m_iLastHeight = HEIGHT;
    }
}

eDecorationType CHyprBar::getDecorationType() {
    return DECORATION_CUSTOM;
}

void CHyprBar::updateWindow(PHLWINDOW pWindow) {
    damageEntire();
}

void CHyprBar::onConfigReloaded() {
    m_bButtonsDirty      = true;
    m_bTitleColorChanged = true;
    m_pTextTex           = nullptr;
    m_tabTexs.clear();

    g_pDecorationPositioner->repositionDeco(this);
    damageEntire();
}

void CHyprBar::damageEntire() {
    g_pHyprRenderer->damageBox(assignedBoxGlobal());
}

Vector2D CHyprBar::cursorRelativeToBar() {
    return g_pInputManager->getMouseCoordsInternal() - assignedBoxGlobal().pos();
}

eDecorationLayer CHyprBar::getDecorationLayer() {
    return DECORATION_LAYER_UNDER;
}

uint64_t CHyprBar::getDecorationFlags() {
    return DECORATION_ALLOWS_MOUSE_INPUT | (g_pGlobalState->config.barPartOfWindow->value() ? DECORATION_PART_OF_MAIN_WINDOW : 0);
}

CBox CHyprBar::assignedBoxGlobal() {
    if (!validMapped(m_pWindow))
        return {};

    CBox box = m_bAssignedBox;
    box.translate(g_pDecorationPositioner->getEdgeDefinedPoint(DECORATION_EDGE_TOP, m_pWindow.lock()));

    const auto PWORKSPACE      = m_pWindow->m_workspace;
    const auto WORKSPACEOFFSET = PWORKSPACE && !m_pWindow->m_pinned ? PWORKSPACE->m_renderOffset->value() : Vector2D();

    return box.translate(WORKSPACEOFFSET);
}

PHLWINDOW CHyprBar::getOwner() {
    return m_pWindow.lock();
}

void CHyprBar::updateRules() {
    const auto PWINDOW              = m_pWindow.lock();
    auto       prevHidden           = m_hidden;
    auto       prevForcedTitleColor = m_bForcedTitleColor;

    m_bForcedBarColor   = std::nullopt;
    m_bForcedTitleColor = std::nullopt;
    m_hidden            = false;

    if (PWINDOW->m_ruleApplicator->m_otherProps.props.contains(g_pGlobalState->nobarRuleIdx))
        m_hidden = truthy(PWINDOW->m_ruleApplicator->m_otherProps.props.at(g_pGlobalState->nobarRuleIdx)->effect);
    if (PWINDOW->m_ruleApplicator->m_otherProps.props.contains(g_pGlobalState->barColorRuleIdx))
        m_bForcedBarColor = CHyprColor(Config::ParserUtils::parseColor(PWINDOW->m_ruleApplicator->m_otherProps.props.at(g_pGlobalState->barColorRuleIdx)->effect).value_or(0));
    if (PWINDOW->m_ruleApplicator->m_otherProps.props.contains(g_pGlobalState->titleColorRuleIdx))
        m_bForcedTitleColor = CHyprColor(Config::ParserUtils::parseColor(PWINDOW->m_ruleApplicator->m_otherProps.props.at(g_pGlobalState->titleColorRuleIdx)->effect).value_or(0));

    g_pDecorationPositioner->repositionDeco(this);
    if (prevForcedTitleColor != m_bForcedTitleColor)
        m_bTitleColorChanged = true;
}

void CHyprBar::damageOnButtonHover() {
    const auto BARPADDING       = g_pGlobalState->config.barPadding->value();
    const auto BARBUTTONPADDING = g_pGlobalState->config.barButtonPadding->value();
    const auto HEIGHT           = g_pGlobalState->config.barHeight->value();
    const auto ALIGNBUTTONS     = g_pGlobalState->config.barButtonsAlignment->value();
    const bool BUTTONSRIGHT     = ALIGNBUTTONS != "left";

    float      offset = BARPADDING;

    const auto COORDS = cursorRelativeToBar();

    for (auto& b : g_pGlobalState->buttons) {
        const auto BARBUF     = Vector2D{(int)assignedBoxGlobal().w, HEIGHT};
        Vector2D   currentPos = Vector2D{(BUTTONSRIGHT ? BARBUF.x - BARBUTTONPADDING - b.size - offset : offset), (BARBUF.y - b.size) / 2.0}.floor();

        bool       hover = VECINRECT(COORDS, currentPos.x, currentPos.y, currentPos.x + b.size + BARBUTTONPADDING, currentPos.y + b.size);

        if (hover != m_bButtonHovered) {
            m_bButtonHovered = hover;
            damageEntire();
        }

        offset += BARBUTTONPADDING + b.size;
    }
}
