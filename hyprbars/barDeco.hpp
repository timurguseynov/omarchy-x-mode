#pragma once

#define WLR_USE_UNSTABLE

#include <hyprland/src/render/decorations/IHyprWindowDecoration.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/gl/GLTexture.hpp>
#include <hyprland/src/devices/IPointer.hpp>
#include <hyprland/src/devices/ITouch.hpp>
#include <hyprland/src/desktop/rule/windowRule/WindowRule.hpp>
#include <hyprland/src/helpers/AnimatedVariable.hpp>
#include <hyprland/src/helpers/time/Time.hpp>
#include <hyprland/src/helpers/signal/Signal.hpp>
#include "globals.hpp"

#include <unordered_map>
#include <string>

#define private public
#include <hyprland/src/managers/input/InputManager.hpp>
#undef private

namespace Event {
    struct SCallbackInfo;
}

// Keep focus (and stacking) inside the group when its current tab goes away:
// switch to the previous tab and raise/focus it. Closing the current tab
// otherwise makes Hyprland focus a group sibling but not raise the group (see
// the m_target note in CFocusState::rawWindowFocus), so the previously active
// app stays on top and it looks like focus jumped to it.
//
// Called from the window.close listener in main.cpp. That event fires for every
// close path -- Cmd+W, the tabbar close button, an app closing its own window --
// so this is the single place that knows how a group survives a tab close.
// Defined in barDeco.cpp.
void keepGroupFocusOnClose(PHLWINDOW w);

// The covering fullscreen window owns the workspace. Returns true when w was
// held under it (no raise). A group tab of that window is not held.
bool holdUnderFullscreen(PHLWINDOW w);

// Raise a floating window, unless holdUnderFullscreen claims it. Returns false
// when the window was held under a fullscreen one (nothing raised, and the
// caller must not focus it); true otherwise, including a non-floating window,
// which the caller may still focus.
bool raiseFloating(PHLWINDOW w);

class CHyprBar : public IHyprWindowDecoration {
  public:
    CHyprBar(PHLWINDOW);
    virtual ~CHyprBar();

    virtual SDecorationPositioningInfo getPositioningInfo();

    virtual void                       onPositioningReply(const SDecorationPositioningReply& reply);

    virtual void                       draw(PHLMONITOR, float const& a);

    virtual eDecorationType            getDecorationType();

    virtual void                       updateWindow(PHLWINDOW);

    virtual void                       damageEntire();

    virtual eDecorationLayer           getDecorationLayer();

    virtual uint64_t                   getDecorationFlags();

    bool                               m_bButtonsDirty = true;

    virtual std::string                getDisplayName();

    PHLWINDOW                          getOwner();

    void                               updateRules();
    void                               onConfigReloaded();
    void                               applyEnabled();

    WP<CHyprBar>                       m_self;

  private:
    SBoxExtents                m_seExtents;

    PHLWINDOWREF               m_pWindow;

    // (tim) group member whose bar was drawn last, to notice a tab switch.
    PHLWINDOWREF               m_pLastGroupCurrent;

    CBox                       m_bAssignedBox;

    SP<Render::ITexture>       m_pTextTex;

    bool                       m_bWindowSizeChanged = false;
    bool                       m_hidden             = false;
    bool                       m_bTitleColorChanged = false;
    bool                       m_bButtonHovered     = false;
    bool                       m_bLastEnabledState  = false;
    bool                       m_bWindowHasFocus    = false;
    std::optional<CHyprColor>  m_bForcedBarColor;
    std::optional<CHyprColor>  m_bForcedTitleColor;

    Time::steady_tp            m_lastMouseDown = Time::steadyNow();

    PHLANIMVAR<CHyprColor>     m_cRealBarColor;

    Vector2D                   cursorRelativeToBar();

    // (tim) custom tabbar for grouped windows: tabs + per-tab close buttons
    // Height comes from plugin:hyprbars:tab_height (see globals.hpp).
    int                        tabHeight();
    bool                       grouped();
    bool                       alwaysTabbar();
    bool                       wantsTabbar();
    bool                       groupCurrent();
    int                        tabAt(const Vector2D& coords, bool& closeHit);
    // Drag a tab sideways to reorder it. CGroup only exposes swapWithNext /
    // swapWithLast and both move the *current* tab, so the dragged window is
    // made current first and then walked to the slot under the pointer.
    void                       updateTabDrag(const Vector2D& coords);
    void                       renderTabs(CBox* barBox, const float scale, const float a);

    bool      m_bTabDragPending = false;
    bool      m_bTabDragging    = false;
    int       m_iTabDragFrom    = -1;
    int       m_iTabDragOver    = -1;
    Vector2D  m_tabDragStart;
    std::unordered_map<std::string, SP<Render::ITexture>> m_tabTexs;

    void                       renderPass(PHLMONITOR, float const& a);
    void                       renderBarTitle(const Vector2D& bufferSize, const float scale);
    void renderBarButtons(CBox* barBox, const float scale, const float a);
    void renderBarButtonsText(CBox* barBox, const float scale, const float a);
    void damageOnButtonHover();

    bool inputIsValid();
    void onMouseButton(Event::SCallbackInfo& info, IPointer::SButtonEvent e);
    void onTouchDown(Event::SCallbackInfo& info, ITouch::SDownEvent e);
    void onTouchUp(Event::SCallbackInfo& info, ITouch::SUpEvent e);
    void onMouseMove(Vector2D coords);
    void onTouchMove(Event::SCallbackInfo& info, ITouch::SMotionEvent e);

    void                       handleDownEvent(Event::SCallbackInfo& info, std::optional<ITouch::SDownEvent> touchEvent, uint32_t button = 272);
    void                       handleUpEvent(Event::SCallbackInfo& info);
    void                       handleMovement();
    void                       moveDragWindow(const Vector2D& coords);
    bool doButtonPress(Config::INTEGER barPadding, Config::INTEGER barButtonPadding, Config::INTEGER barHeight, Vector2D COORDS, bool BUTTONSRIGHT);

    CBox assignedBoxGlobal();

    CHyprSignalListener m_pMouseButtonCallback;
    CHyprSignalListener m_pTouchDownCallback;
    CHyprSignalListener m_pTouchUpCallback;

    CHyprSignalListener m_pTouchMoveCallback;
    CHyprSignalListener m_pMouseMoveCallback;

    std::string         m_szLastTitle;

    bool                m_bDraggingThis  = false;
    bool                m_bTouchEv       = false;
    bool                m_bDragPending   = false;
    bool                m_bCancelledDown = false;
    int                 m_touchId        = 0;

    // Touch drag (mouse titlebar drag lives in CDragSession).
    bool                m_bDragActive     = false;
    Vector2D            m_dragStartCursor;
    Vector2D            m_dragAnchor;
    Vector2D            m_dragWindowPos;

    // store hover state for buttons as a bitfield
    unsigned int m_iButtonHoverState = 0;

    // for dynamic updates
    int    m_iLastHeight = 0;

    size_t getVisibleButtonCount(Config::INTEGER barButtonPadding, Config::INTEGER barPadding, const Vector2D& bufferSize, const float scale);

    friend class CBarPassElement;
};
