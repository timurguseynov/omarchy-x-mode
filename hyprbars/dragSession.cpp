#include "dragSession.hpp"
#include "globals.hpp"

UP<CDragSession> g_pDragSession;

#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/view/Group.hpp>
#include <hyprland/src/devices/IPointer.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/layout/target/Target.hpp>
#include <hyprland/src/managers/EventManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <format>

CDragSession::CDragSession() {
    m_mouseMove = Event::bus()->m_events.input.mouse.move.listen([this](Vector2D c, Event::SCallbackInfo&) { onMove(c); });
    m_mouseButton = Event::bus()->m_events.input.mouse.button.listen([this](IPointer::SButtonEvent e, Event::SCallbackInfo&) {
        if (e.button == 272 && e.state != WL_POINTER_BUTTON_STATE_PRESSED && inProgress())
            end();
    });
    m_windowClose = Event::bus()->m_events.window.close.listen([this](PHLWINDOW w) {
        if (owns(w))
            cancel();
    });
}

void CDragSession::stealCompositorMove() {
    if (!xModeEnabled() || inProgress() || !g_layoutManager)
        return;
    const auto& ctrl = g_layoutManager->dragController();
    if (!ctrl || ctrl->mode() != MBIND_MOVE)
        return;
    const auto target = ctrl->target();
    if (!target)
        return;
    const auto w = target->window();
    if (!w || !w->m_isFloating)
        return;
    // Chromium (and others) start a compositor move from their own tab strip.
    // Abort that drag and run ours so edge-snap still works.
    g_layoutManager->endDragTarget();
    begin(w);
}

bool CDragSession::owns(PHLWINDOW w) const {
    const auto ours = m_window.lock();
    if (!w || !ours)
        return false;
    if (w == ours)
        return true;
    if (w->m_group && ours->m_group && w->m_group == ours->m_group)
        return true;
    return false;
}

void CDragSession::emitDrag(bool active, PHLWINDOW w) {
    if (!g_pGlobalState || !g_pGlobalState->dragEvent)
        return;
    (void)g_pGlobalState->dragEvent->emit({active, PHLWINDOWREF{w}});
}

void CDragSession::begin(PHLWINDOW w) {
    cancel();
    if (!w || !xModeEnabled())
        return;
    m_window      = w;
    m_pending     = true;
    m_active      = false;
    m_zone        = Snap::eKind::None;
    m_startCursor = g_pInputManager->getMouseCoordsInternal();
    emitDrag(true, w);
}

void CDragSession::onMove(const Vector2D& coords) {
    if (!m_pending && !m_active)
        stealCompositorMove();
    if (!m_pending && !m_active)
        return;
    moveWindow(coords);
    if (m_active)
        updatePreview();
}

void CDragSession::end() {
    if (!inProgress())
        return;
    const auto w    = m_window.lock();
    const auto zone = m_zone;
    const bool snap = m_active && zone != Snap::eKind::None && w;
    // Snap first so grouping that runs on drag-end sees the snapped geometry.
    if (snap)
        Snap::applyKind(w, zone);
    else if (m_active && w)
        w->sendWindowSize(true);
    cancel();
}

void CDragSession::cancel() {
    const auto w   = m_window.lock();
    const bool was = m_pending || m_active;
    m_pending      = false;
    m_active       = false;
    m_window.reset();
    m_zone = Snap::eKind::None;
    setPreview("hide");
    if (was)
        emitDrag(false, w);
}

void CDragSession::moveWindow(const Vector2D& coords) {
    static auto PDRAGTHRESHOLD = CConfigValue<Config::INTEGER>("binds:drag_threshold");

    const auto PWINDOW = m_window.lock();
    if (!PWINDOW)
        return;
    const auto TARGET = PWINDOW->layoutTarget();
    if (!TARGET || !TARGET->floating())
        return;

    if (!m_active) {
        if (std::abs(coords.x - m_startCursor.x) < *PDRAGTHRESHOLD && std::abs(coords.y - m_startCursor.y) < *PDRAGTHRESHOLD)
            return;
        m_pending   = false;
        m_active    = true;
        m_anchor    = coords;
        m_windowPos = TARGET->position().pos();
        return;
    }

    const auto DELTA  = coords - m_anchor;
    auto       newPos = m_windowPos + DELTA;

    const auto MON = PWINDOW->m_monitor.lock();
    if (MON) {
        // Mac-like: the titlebar (and tabbar) cannot go above the reserved
        // top. With no top bar this is y=0, the screen edge.
        // Visual chrome top is at.y - chrome; the border is drawn outside the
        // box, so leave border_size below the reserved top or it overlaps the bar.
        const auto TOP    = MON->m_reservedArea.top();
        const auto CHROME = sc<double>(Snap::chromeH(PWINDOW));
        const auto LIMIT  = TOP + sc<double>(Snap::border());
        if (newPos.y - CHROME < LIMIT)
            newPos.y = LIMIT + CHROME;
    }

    Snap::moveDrag(PWINDOW, newPos);
}

void CDragSession::updatePreview() {
    const auto w = m_window.lock();
    if (!w) {
        setPreview("hide");
        return;
    }
    const auto cursor = g_pInputManager->getMouseCoordsInternal();
    m_zone            = Snap::zoneAtCursor(cursor, w, true);
    if (m_zone == Snap::eKind::None) {
        setPreview("hide");
        return;
    }
    const auto mon = State::monitorState()->query().vec(cursor).run();
    const auto box = Snap::zoneBox(m_zone, mon);
    if (!box) {
        setPreview("hide");
        return;
    }
    setPreview(std::format("show {} {} {} {}", sc<int>(std::floor(box->x + 0.5)), sc<int>(std::floor(box->y + 0.5)), sc<int>(std::floor(box->w + 0.5)),
                           sc<int>(std::floor(box->h + 0.5))));
}

void CDragSession::setPreview(const std::string& line) {
    if (line == m_lastPreview)
        return;
    m_lastPreview = line;

    const char* runtime = std::getenv("XDG_RUNTIME_DIR");
    const auto  path    = std::format("{}/omarchy-snap-preview.cmd", runtime && *runtime ? runtime : "/tmp");
    FILE*       file    = std::fopen(path.c_str(), "w");
    if (!file)
        return;
    std::fprintf(file, "%s\n", line.c_str());
    std::fclose(file);

    if (g_pEventManager)
        g_pEventManager->postEvent(SHyprIPCEvent{.event = "xmodesnap", .data = line});
}
