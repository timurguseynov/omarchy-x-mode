#pragma once

#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/render/Texture.hpp>
#include <hyprland/src/config/values/types/BoolValue.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>
#include <hyprland/src/config/values/types/StringValue.hpp>
#include <hyprland/src/config/values/types/ColorValue.hpp>
#include <hyprland/src/config/values/types/FontWeightValue.hpp>

inline HANDLE PHANDLE = nullptr;

struct SHyprButton {
    std::string          cmd     = "";
    bool                 userfg  = false;
    CHyprColor           fgcol   = CHyprColor(0, 0, 0, 0);
    CHyprColor           bgcol   = CHyprColor(0, 0, 0, 0);
    float                size    = 10;
    std::string          icon    = "";
    SP<Render::ITexture> iconTex;
};

class CHyprBar;
class CDragSession;

extern UP<CDragSession> g_pDragSession;

struct SGlobalState {
    std::vector<SHyprButton>  buttons;
    std::vector<WP<CHyprBar>> bars;
    uint32_t                  nobarRuleIdx       = 0;
    uint32_t                  alwaysTabbarRuleIdx = 0;
    uint32_t                  barColorRuleIdx    = 0;
    uint32_t                  titleColorRuleIdx  = 0;

    struct {
        SP<Config::Values::CColorValue>      barColor, textColor, inactiveButtonColor;
        SP<Config::Values::CIntValue>        barHeight;
        SP<Config::Values::CIntValue>        barTextSize;
        SP<Config::Values::CFontWeightValue> barTextWeight;
        SP<Config::Values::CIntValue>        barPadding;
        SP<Config::Values::CIntValue>        barButtonPadding;
        SP<Config::Values::CBoolValue>       barBlur, barTitleEnabled, barPartOfWindow, barPrecedenceOverBorder, enabled, iconOnHover;
        SP<Config::Values::CStringValue>     barTextFont, barTextAlign, barButtonsAlignment, onDoubleClick;
        // (tim) x-mode: tabbar height and snap/grouping tunables. Real Hyprland
        // config keys (plugin:hyprbars:*) so they are edited in the config, not
        // in code; the C++ snap engine and Lua grouping read the same value.
        SP<Config::Values::CIntValue>        tabHeight;
        SP<Config::Values::CBoolValue>       tabCloseActiveOnly;
        SP<Config::Values::CIntValue>        xModeDockInset;
        SP<Config::Values::CIntValue>        xModeSnapMargin;
        SP<Config::Values::CIntValue>        xModeSnapCorner;
        SP<Config::Values::CIntValue>        xModeSnapShortEdge;
        SP<Config::Values::CIntValue>        xModeSnapTopSlop;
        SP<Config::Values::CBoolValue>       xModeSnapTopHalf;
        SP<Config::Values::CBoolValue>       xModeSnapBottomHalf;
        SP<Config::Values::CIntValue>        xModeAlmostMaximizePercent;
        SP<Config::Values::CIntValue>        xModeGroupMinWidth;
        SP<Config::Values::CIntValue>        xModeGroupMinHeight;
    } config;

    SP<Event::CEventBus::CCustomEvent> dragEvent;
    SP<Event::CEventBus::CCustomEvent> xModeEvent;
    bool                               xModeOn = true;
};

inline UP<SGlobalState> g_pGlobalState;

inline bool xModeEnabled() {
    return g_pGlobalState && g_pGlobalState->xModeOn;
}
