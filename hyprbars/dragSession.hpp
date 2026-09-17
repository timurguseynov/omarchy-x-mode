#pragma once

#include <hyprland/src/desktop/DesktopTypes.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/helpers/math/Math.hpp>
#include <hyprland/src/helpers/signal/Signal.hpp>
#include "snap.hpp"

#include <string>

// One in-flight titlebar drag for the whole plugin. The window is pinned at
// press; focus changes (a new app opening) cannot steal the snap. Listens to
// mouse move/release globally so the snap still runs if the pointer is over a
// layer surface or another window when the button comes up.
class CDragSession {
  public:
    CDragSession();
    ~CDragSession() { cancel(); }

    bool      owns(PHLWINDOW w) const;
    bool      inProgress() const { return m_pending || m_active; }
    PHLWINDOW window() const { return m_window.lock(); }

    void begin(PHLWINDOW w);
    void end();
    void cancel();

  private:
    void stealCompositorMove();
    void onMove(const Vector2D& coords);
    void moveWindow(const Vector2D& coords);
    void updatePreview();
    void setPreview(const std::string& line);
    void emitDrag(bool active, PHLWINDOW w);

    bool         m_pending = false;
    bool         m_active  = false;
    PHLWINDOWREF m_window;
    Vector2D     m_startCursor;
    Vector2D     m_anchor;
    Vector2D     m_windowPos;
    Snap::eKind  m_zone = Snap::eKind::None;
    std::string  m_lastPreview;

    CHyprSignalListener m_mouseMove;
    CHyprSignalListener m_mouseButton;
    CHyprSignalListener m_windowClose;
};
