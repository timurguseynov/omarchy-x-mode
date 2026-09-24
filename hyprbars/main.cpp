#define WLR_USE_UNSTABLE

#include <unistd.h>

#include <any>
#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/config/ConfigManager.hpp>
#include <hyprland/src/config/shared/parserUtils/ParserUtils.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/desktop/rule/windowRule/WindowRuleEffectContainer.hpp>
#include <hyprland/src/config/lua/bindings/LuaBindingsInternal.hpp>
#include <hyprland/src/config/lua/types/LuaConfigColor.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include <hyprutils/string/VarList.hpp>

#include <algorithm>
#include <format>
#include <cstdio>
#include <cstdlib>

#include "barDeco.hpp"
#include "dragSession.hpp"
#include "globals.hpp"
#include "snap.hpp"

#include <hyprland/src/config/lua/objects/LuaWindow.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/managers/XWaylandManager.hpp>
#include <hyprland/src/managers/EventManager.hpp>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

// Do NOT change this function.
APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

static void onNewWindow(PHLWINDOW window) {
    if (!window->m_X11DoesntWantBorders) {
        if (std::ranges::any_of(window->m_windowDecorations, [](const auto& d) { return d->getDisplayName() == "Hyprbar"; }))
            return;

        auto bar = makeUnique<CHyprBar>(window);
        g_pGlobalState->bars.emplace_back(bar);
        bar->m_self = bar;
        HyprlandAPI::addWindowDecoration(PHANDLE, window, std::move(bar));
    }
}

static void onPreConfigReload() {
    g_pGlobalState->buttons.clear();
}

static void onConfigReloaded() {
    for (auto& b : g_pGlobalState->bars) {
        if (!b)
            continue;

        b->onConfigReloaded();
    }
}

// (tim) Hyprland recreates its Lua event handler on every config reload, which
// drops the listener it had installed for our custom events. Without that
// listener the events no longer reach Lua's hl.on("hyprbars.drag") after the
// reload the plugin itself triggers at load -- the subscription silently
// registers but never fires. Re-register the events on each reload so the new
// handler subscribes again: removePluginEvent/addPluginEvent make the bus emit
// pluginEventRemoved / pluginEventAdded, which is what (re)binds the listener.
static void reRegisterEvents() {
    if (!g_pGlobalState || !g_pGlobalState->dragEvent || !g_pGlobalState->xModeEvent)
        return;

    HyprlandAPI::removeEvent(PHANDLE, "hyprbars.drag");
    HyprlandAPI::removeEvent(PHANDLE, "hyprbars.x_mode");
    HyprlandAPI::addEvent(PHANDLE, g_pGlobalState->dragEvent);
    HyprlandAPI::addEvent(PHANDLE, g_pGlobalState->xModeEvent);
}

static void onUpdateWindowRules(PHLWINDOW window) {
    const auto BARIT = std::find_if(g_pGlobalState->bars.begin(), g_pGlobalState->bars.end(), [window](const auto& bar) { return bar->getOwner() == window; });

    if (BARIT == g_pGlobalState->bars.end())
        return;

    (*BARIT)->updateRules();
    window->updateWindowDecos();
}

Hyprlang::CParseResult onNewButton(const char* K, const char* V) {
    std::string                 v = V;
    Hyprutils::String::CVarList vars(v);

    Hyprlang::CParseResult      result;

    // hyprbars-button = bgcolor, size, icon, action, fgcolor

    if (vars[0].empty() || vars[1].empty()) {
        result.setError("bgcolor and size cannot be empty");
        return result;
    }

    float size = 10;
    try {
        size = std::stof(vars[1]);
    } catch (std::exception& e) {
        result.setError("failed to parse size");
        return result;
    }

    bool userfg  = false;
    auto fgcolor = Config::ParserUtils::parseColor("rgb(ffffff)");
    auto bgcolor = Config::ParserUtils::parseColor(vars[0]);

    if (!bgcolor) {
        result.setError("invalid bgcolor");
        return result;
    }

    if (vars.size() == 5) {
        userfg  = true;
        fgcolor = Config::ParserUtils::parseColor(vars[4]);
    }

    if (!fgcolor) {
        result.setError("invalid fgcolor");
        return result;
    }

    g_pGlobalState->buttons.push_back(SHyprButton{vars[3], userfg, *fgcolor, *bgcolor, size, vars[2]});

    for (auto& b : g_pGlobalState->bars) {
        b->m_bButtonsDirty = true;
    }

    return result;
}

int newLuaButton(lua_State* L) {
    if (!lua_istable(L, 1))
        return Config::Lua::Bindings::Internal::configError(L, "add_button: expected a table { bg_color, fg_color, size, icon, action }");

    SHyprButton button;

    {
        Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

        lua_getfield(L, 1, "bg_color");

        Config::Lua::CLuaConfigColor parser(0);
        auto                         err = parser.parse(L);
        if (err.errorCode != Config::Lua::PARSE_ERROR_OK)
            return Config::Lua::Bindings::Internal::configError(L, "add_button: failed to parse bg_color");

        button.bgcol = parser.parsed();
    }

    {
        Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

        lua_getfield(L, 1, "fg_color");

        Config::Lua::CLuaConfigColor parser(0);
        auto                         err = parser.parse(L);
        if (err.errorCode != Config::Lua::PARSE_ERROR_OK)
            return Config::Lua::Bindings::Internal::configError(L, "add_button: failed to parse fg_color");

        button.userfg = true;
        button.fgcol = parser.parsed();
    }

    {
        Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

        lua_getfield(L, 1, "size");

        if (!lua_isnumber(L, -1))
            return Config::Lua::Bindings::Internal::configError(L, "add_button: size must be an integer");

        button.size = lua_tointeger(L, -1);
    }

    {
        Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

        lua_getfield(L, 1, "icon");

        if (!lua_isstring(L, -1))
            return Config::Lua::Bindings::Internal::configError(L, "add_button: icon must be a string");

        button.icon = lua_tostring(L, -1);
    }

    {
        Hyprutils::Utils::CScopeGuard x([L] { lua_pop(L, 1); });

        lua_getfield(L, 1, "action");

        if (!lua_isstring(L, -1))
            return Config::Lua::Bindings::Internal::configError(L, "add_button: action must be a string");

        button.cmd = lua_tostring(L, -1);
    }

    g_pGlobalState->buttons.push_back(std::move(button));

    for (auto& b : g_pGlobalState->bars) {
        b->m_bButtonsDirty = true;
    }

    return 0;
}

static int luaSnap(lua_State* L) {
    if (!lua_istable(L, 1))
        return Config::Lua::Bindings::Internal::configError(L, "snap: expected a table { kind, window? }");

    lua_getfield(L, 1, "kind");
    if (!lua_isstring(L, -1)) {
        lua_pop(L, 1);
        return Config::Lua::Bindings::Internal::configError(L, "snap: kind must be a string");
    }
    const auto kind = Snap::kindFromString(lua_tostring(L, -1));
    lua_pop(L, 1);
    if (kind == Snap::eKind::None)
        return Config::Lua::Bindings::Internal::configError(L, "snap: unknown kind");

    lua_getfield(L, 1, "window");
    PHLWINDOW window = nullptr;
    if (!lua_isnil(L, -1))
        window = Config::Lua::Bindings::Internal::windowFromLuaSelectorOrObject(L, -1, "hyprbars.snap");
    lua_pop(L, 1);
    if (!window)
        window = Desktop::focusState()->window();
    if (!window)
        return 0;

    Snap::applyKind(window, kind);
    return 0;
}

// The snap zone a window currently fills, or nil. An optional { gap, border }
// tests the position against the zones those gaps would produce, so a window
// snapped with no gaps is still recognised after the gaps come back.
static int luaZone(lua_State* L) {
    PHLWINDOW w = nullptr;
    if (lua_gettop(L) >= 1 && !lua_isnil(L, 1))
        w = Config::Lua::Bindings::Internal::windowFromLuaSelectorOrObject(L, 1, "hyprbars.zone");
    if (!w)
        w = Desktop::focusState()->window();

    int gap = -1, border = -1;
    if (lua_istable(L, 2)) {
        lua_getfield(L, 2, "gap");
        if (lua_isnumber(L, -1))
            gap = sc<int>(lua_tonumber(L, -1));
        lua_pop(L, 1);
        lua_getfield(L, 2, "border");
        if (lua_isnumber(L, -1))
            border = sc<int>(lua_tonumber(L, -1));
        lua_pop(L, 1);
    }

    Snap::assumeGaps(gap, border);
    const auto kind = Snap::kindOf(w);
    Snap::assumeGaps(-1, -1);

    if (kind == Snap::eKind::None) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushstring(L, Snap::kindToString(kind));
    return 1;
}

// The top the bar currently reserves, with the shell-restart fallback applied
// (see Snap::barTop). Lua clamps windows itself in a few places and has to lift
// a group's tabbar out from under the bar with the same number the snap used.
static int luaBarTop(lua_State* L) {
    const char* name = lua_isstring(L, 1) ? lua_tostring(L, 1) : nullptr;
    for (const auto& m : State::monitorState()->monitors()) {
        if (!m || (name && m->m_name != name))
            continue;
        lua_pushnumber(L, Snap::barTop(m));
        return 1;
    }
    lua_pushnil(L);
    return 1;
}

static int luaDragging(lua_State* L) {
    lua_pushboolean(L, g_pDragSession && g_pDragSession->inProgress());
    return 1;
}

static int luaDragWindow(lua_State* L) {
    const auto w = g_pDragSession ? g_pDragSession->window() : PHLWINDOW{};
    if (!w) {
        lua_pushnil(L);
        return 1;
    }
    Config::Lua::Objects::CLuaWindow::push(L, w);
    return 1;
}

static int luaDragOwns(lua_State* L) {
    PHLWINDOW w = nullptr;
    if (lua_gettop(L) >= 1 && !lua_isnil(L, 1))
        w = Config::Lua::Bindings::Internal::windowFromLuaSelectorOrObject(L, 1, "hyprbars.drag_owns");
    lua_pushboolean(L, g_pDragSession && g_pDragSession->owns(w));
    return 1;
}

// Same classification Hyprland uses for auto-group / float: override-redirect,
// modal, X11 menu/combo/tooltip types, transients, and xdg children. Size is
// not a signal — a small document is still a document.
static int luaGroupable(lua_State* L) {
    PHLWINDOW w = nullptr;
    if (lua_gettop(L) >= 1 && !lua_isnil(L, 1))
        w = Config::Lua::Bindings::Internal::windowFromLuaSelectorOrObject(L, 1, "hyprbars.groupable");
    if (!w) {
        lua_pushboolean(L, false);
        return 1;
    }
    if (w->isX11OverrideRedirect() || w->isModal() || g_pXWaylandManager->shouldBeFloated(w)) {
        lua_pushboolean(L, false);
        return 1;
    }
    lua_pushboolean(L, true);
    return 1;
}

static void writeXModeFiles(bool on) {
    const auto  line    = on ? "on\n" : "off\n";
    const char* runtime = std::getenv("XDG_RUNTIME_DIR");
    const auto  rt      = std::format("{}/omarchy-x-mode.state", runtime && *runtime ? runtime : "/tmp");
    if (FILE* f = std::fopen(rt.c_str(), "w")) {
        std::fputs(line, f);
        std::fclose(f);
    }
    const char* home = std::getenv("HOME");
    if (home && *home) {
        const auto path = std::format("{}/.local/state/omarchy-x-mode/enabled", home);
        if (FILE* f = std::fopen(path.c_str(), "w")) {
            std::fputs(line, f);
            std::fclose(f);
        }
    }
}

static bool readPersistedXMode() {
    const char* home = std::getenv("HOME");
    if (!home || !*home)
        return true;
    const auto path = std::format("{}/.local/state/omarchy-x-mode/enabled", home);
    FILE*      f    = std::fopen(path.c_str(), "r");
    if (!f)
        return true;
    char buf[8]{};
    std::fgets(buf, sizeof(buf), f);
    std::fclose(f);
    return !(buf[0] == 'o' && buf[1] == 'f');
}

static void applyXMode(bool on) {
    if (!g_pGlobalState)
        return;
    if (g_pGlobalState->xModeOn == on) {
        writeXModeFiles(on);
        return;
    }
    g_pGlobalState->xModeOn = on;
    if (!on && g_pDragSession)
        g_pDragSession->cancel();
    for (auto& b : g_pGlobalState->bars) {
        if (b)
            b->applyEnabled();
    }
    writeXModeFiles(on);
    if (g_pGlobalState->xModeEvent)
        (void)g_pGlobalState->xModeEvent->emit({on});
    if (g_pEventManager)
        g_pEventManager->postEvent(SHyprIPCEvent{.event = "xmode", .data = on ? "on" : "off"});
}

static int luaXMode(lua_State* L) {
    if (lua_gettop(L) >= 1 && !lua_isnil(L, 1)) {
        bool on = true;
        if (lua_isboolean(L, 1))
            on = lua_toboolean(L, 1);
        else if (lua_isstring(L, 1)) {
            const char* s = lua_tostring(L, 1);
            on = !(s && (s[0] == 'o' || s[0] == 'O') && (s[1] == 'f' || s[1] == 'F'));
            if (s && (s[0] == '0' || ((s[0] == 'f' || s[0] == 'F') && s[1] == 'a')))
                on = false;
            if (s && (s[0] == 't' || s[0] == 'T' || s[0] == '1'))
                on = true;
        }
        applyXMode(on);
    }
    lua_pushboolean(L, xModeEnabled());
    return 1;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    const std::string HASH        = __hyprland_api_get_hash();
    const std::string CLIENT_HASH = __hyprland_api_get_client_hash();

    if (HASH != CLIENT_HASH) {
        HyprlandAPI::addNotification(PHANDLE, "[hyprbars] Failure in initialization: Version mismatch (headers ver is not equal to running hyprland ver)",
                                     CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[hb] Version mismatch");
    }

    g_pGlobalState                    = makeUnique<SGlobalState>();
    g_pGlobalState->nobarRuleIdx        = Desktop::Rule::windowEffects()->registerEffect("hyprbars:no_bar");
    g_pGlobalState->alwaysTabbarRuleIdx = Desktop::Rule::windowEffects()->registerEffect("hyprbars:always_tabbar");
    g_pGlobalState->barColorRuleIdx   = Desktop::Rule::windowEffects()->registerEffect("hyprbars:bar_color");
    g_pGlobalState->titleColorRuleIdx = Desktop::Rule::windowEffects()->registerEffect("hyprbars:title_color");

    static auto P  = Event::bus()->m_events.window.open.listen([&](PHLWINDOW w) { onNewWindow(w); });
    static auto P3 = Event::bus()->m_events.window.updateRules.listen([&](PHLWINDOW w) { onUpdateWindowRules(w); });
    // Single close path for the whole pack: Hyprland's unmap refocus picks a
    // group sibling but never raises the group, so the previously active app
    // stays on top. Cmd+W, the tabbar close button and an app closing its own
    // window all end up here. Keep the group focused on its previous tab.
    // Only for the focused window: a background app closing a background
    // window must not steal focus. The window.close event is emitted before
    // Hyprland resets focus, so the closing window is still the focused one.
    static auto PClose = Event::bus()->m_events.window.close.listen([&](PHLWINDOW w) {
        if (!xModeEnabled() || !w || w != Desktop::focusState()->window())
            return;
        keepGroupFocusOnClose(w);
    });
    // plugin:hyprbars:tab_close_active_only gates the tabbar ✕ on focus, but
    // renderPass is only reached when the deco is redrawn, so a focus change
    // must damage the bars itself or the ✕ would linger.
    static auto PFocus = Event::bus()->m_events.window.active.listen([&](PHLWINDOW w, Desktop::eFocusReason r) {
        if (!xModeEnabled() || !g_pGlobalState->config.tabCloseActiveOnly || !g_pGlobalState->config.tabCloseActiveOnly->value())
            return;
        // The bars are owned by unique_ptrs (see onNewWindow), so the weak
        // pointers must not be lock()ed -- that asserts. Use operator-> like the
        // other loops do.
        for (auto& bar : g_pGlobalState->bars) {
            if (bar)
                bar->damageEntire();
        }
    });

    g_pGlobalState->config.barColor            = makeShared<Config::Values::CColorValue>("plugin:hyprbars:bar_color", "Change the bar color", 0x88333333);
    g_pGlobalState->config.textColor           = makeShared<Config::Values::CColorValue>("plugin:hyprbars:col.text", "Change the text color", 0xffffffff);
    g_pGlobalState->config.inactiveButtonColor = makeShared<Config::Values::CColorValue>(
        "plugin:hyprbars:inactive_button_color", "Change the inactive button's color. 0x00000000 means unset", 0x00000000);
    g_pGlobalState->config.barHeight       = makeShared<Config::Values::CIntValue>("plugin:hyprbars:bar_height", "Change the bar's height", 15);
    g_pGlobalState->config.barTextSize     = makeShared<Config::Values::CIntValue>("plugin:hyprbars:bar_text_size", "Change the bar's text size", 10);
    g_pGlobalState->config.barTextWeight   = makeShared<Config::Values::CFontWeightValue>("plugin:hyprbars:bar_text_weight", "Bar's title text weight (e.g. \"bold\" or an integer 100-1000)", 400);
    g_pGlobalState->config.barTitleEnabled = makeShared<Config::Values::CBoolValue>("plugin:hyprbars:bar_title_enabled", "Whether to enable titles in the bar", true);
    g_pGlobalState->config.barBlur         = makeShared<Config::Values::CBoolValue>("plugin:hyprbars:bar_blur", "Whether to enable blur of the bar", false);
    g_pGlobalState->config.barTextFont     = makeShared<Config::Values::CStringValue>("plugin:hyprbars:bar_text_font", "Bar's text font", "Sans");
    g_pGlobalState->config.barTextAlign    = makeShared<Config::Values::CStringValue>("plugin:hyprbars:bar_text_align", "Bar's text alignment", "center");
    g_pGlobalState->config.barPartOfWindow =
        makeShared<Config::Values::CBoolValue>("plugin:hyprbars:bar_part_of_window", "Whether the bar is a part of the window (reserves space)", true);
    g_pGlobalState->config.barPrecedenceOverBorder =
        makeShared<Config::Values::CBoolValue>("plugin:hyprbars:bar_precedence_over_border", "Whether the bar is before, or after the border", false);
    g_pGlobalState->config.barButtonsAlignment = makeShared<Config::Values::CStringValue>("plugin:hyprbars:bar_buttons_alignment", "Alignment of the bar buttons", "right");
    g_pGlobalState->config.barPadding          = makeShared<Config::Values::CIntValue>("plugin:hyprbars:bar_padding", "Padding of the bar", 7);
    g_pGlobalState->config.barButtonPadding    = makeShared<Config::Values::CIntValue>("plugin:hyprbars:bar_button_padding", "Padding of the bar buttons", 5);
    g_pGlobalState->config.enabled             = makeShared<Config::Values::CBoolValue>("plugin:hyprbars:enabled", "Whether bars are enabled", true);
    g_pGlobalState->config.iconOnHover         = makeShared<Config::Values::CBoolValue>("plugin:hyprbars:icon_on_hover", "Whether to use an icon on hover of the buttons", false);
    g_pGlobalState->config.onDoubleClick       = makeShared<Config::Values::CStringValue>("plugin:hyprbars:on_double_click", "Action to execute on double click of the bar", "");

    // (tim) x-mode: the tabbar height and the tunables of the Lua snap/grouping
    // engine, as real Hyprland config keys so they are edited in the config.
    g_pGlobalState->config.tabHeight = makeShared<Config::Values::CIntValue>("plugin:hyprbars:tab_height", "Height of the group tabbar", 24);
    g_pGlobalState->config.tabCloseActiveOnly =
        makeShared<Config::Values::CBoolValue>("plugin:hyprbars:tab_close_active_only", "Only show and act on the close button of the current tab, and only while the group has focus", false);
    g_pGlobalState->config.xModeDockInset =
        makeShared<Config::Values::CIntValue>("plugin:hyprbars:x_mode_dock_inset", "Right snap inset: dock card plus half of gaps_out (set by x-mode.lua)", 45);
    g_pGlobalState->config.xModeSnapMargin =
        makeShared<Config::Values::CIntValue>("plugin:hyprbars:x_mode_snap_margin", "Thickness (px) of the screen-edge strip that starts a snap", 12);
    g_pGlobalState->config.xModeSnapCorner =
        makeShared<Config::Values::CIntValue>("plugin:hyprbars:x_mode_snap_corner", "Corner square (px) that picks a quarter snap", 20);
    g_pGlobalState->config.xModeSnapShortEdge =
        makeShared<Config::Values::CIntValue>("plugin:hyprbars:x_mode_snap_short_edge", "Along a side edge, px from top/bottom that pick a top/bottom half", 145);
    g_pGlobalState->config.xModeSnapTopSlop =
        makeShared<Config::Values::CIntValue>("plugin:hyprbars:x_mode_snap_top_slop", "Extra px below the reserved top (top bar) that still maximize", 8);
    g_pGlobalState->config.xModeSnapTopHalf =
        makeShared<Config::Values::CBoolValue>("plugin:hyprbars:x_mode_snap_top_half", "Side-edge short strip at the top picks a top half", false);
    g_pGlobalState->config.xModeSnapBottomHalf =
        makeShared<Config::Values::CBoolValue>("plugin:hyprbars:x_mode_snap_bottom_half", "Side-edge short strip at the bottom picks a bottom half", false);
    g_pGlobalState->config.xModeAlmostMaximizePercent =
        makeShared<Config::Values::CIntValue>("plugin:hyprbars:x_mode_almost_maximize_percent", "Size of the almost-maximize window, in percent", 90);
    g_pGlobalState->config.xModeGroupMinWidth =
        makeShared<Config::Values::CIntValue>("plugin:hyprbars:x_mode_group_min_width", "Windows narrower than this (px) are not auto-grouped", 400);
    g_pGlobalState->config.xModeGroupMinHeight =
        makeShared<Config::Values::CIntValue>("plugin:hyprbars:x_mode_group_min_height", "Windows shorter than this (px) are not auto-grouped", 300);

    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barColor);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.textColor);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.inactiveButtonColor);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barHeight);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barTextSize);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barTextWeight);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barTitleEnabled);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barBlur);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barTextFont);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barTextAlign);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barPartOfWindow);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barPrecedenceOverBorder);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barButtonsAlignment);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barPadding);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.barButtonPadding);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.enabled);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.iconOnHover);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.onDoubleClick);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.tabHeight);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.tabCloseActiveOnly);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.xModeDockInset);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.xModeSnapMargin);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.xModeSnapCorner);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.xModeSnapShortEdge);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.xModeSnapTopSlop);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.xModeSnapTopHalf);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.xModeSnapBottomHalf);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.xModeAlmostMaximizePercent);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.xModeGroupMinWidth);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_pGlobalState->config.xModeGroupMinHeight);

    if (Config::mgr()->type() == Config::CONFIG_LEGACY)
        HyprlandAPI::addConfigKeyword(PHANDLE, "plugin:hyprbars:hyprbars-button", onNewButton, Hyprlang::SHandlerOptions{});
    else {
        HyprlandAPI::addLuaFunction(PHANDLE, "hyprbars", "add_button", ::newLuaButton);
        HyprlandAPI::addLuaFunction(PHANDLE, "hyprbars", "snap", ::luaSnap);
        HyprlandAPI::addLuaFunction(PHANDLE, "hyprbars", "zone", ::luaZone);
        HyprlandAPI::addLuaFunction(PHANDLE, "hyprbars", "bar_top", ::luaBarTop);
        HyprlandAPI::addLuaFunction(PHANDLE, "hyprbars", "dragging", ::luaDragging);
        HyprlandAPI::addLuaFunction(PHANDLE, "hyprbars", "drag_window", ::luaDragWindow);
        HyprlandAPI::addLuaFunction(PHANDLE, "hyprbars", "drag_owns", ::luaDragOwns);
        HyprlandAPI::addLuaFunction(PHANDLE, "hyprbars", "groupable", ::luaGroupable);
        HyprlandAPI::addLuaFunction(PHANDLE, "hyprbars", "x_mode", ::luaXMode);
    }

    g_pGlobalState->dragEvent = makeShared<Event::CEventBus::CCustomEvent>(
        "hyprbars.drag", std::vector<Event::CEventBus::CCustomEvent::eType>{
                             Event::CEventBus::CCustomEvent::TYPE_BOOL,
                             Event::CEventBus::CCustomEvent::TYPE_WINDOW,
                         });
    HyprlandAPI::addEvent(PHANDLE, g_pGlobalState->dragEvent);
    g_pGlobalState->xModeEvent = makeShared<Event::CEventBus::CCustomEvent>(
        "hyprbars.x_mode", std::vector<Event::CEventBus::CCustomEvent::eType>{
                               Event::CEventBus::CCustomEvent::TYPE_BOOL,
                           });
    HyprlandAPI::addEvent(PHANDLE, g_pGlobalState->xModeEvent);
    g_pDragSession = makeUnique<CDragSession>();
    static auto P4 = Event::bus()->m_events.config.preReload.listen([&] { onPreConfigReload(); });
    static auto P5 = Event::bus()->m_events.config.reloaded.listen([&] {
        reRegisterEvents();
        onConfigReloaded();
    });

    // add deco to existing windows
    for (auto& w : Desktop::windowState()->windows()) {
        if (w->isHidden() || !w->m_isMapped)
            continue;

        onNewWindow(w);
    }

    HyprlandAPI::reloadConfig();

    if (!readPersistedXMode())
        applyXMode(false);

    return {"hyprbars", "A plugin to add title bars to windows.", "Vaxry", "1.0"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_pDragSession.reset();
    if (g_pGlobalState && g_pGlobalState->dragEvent)
        HyprlandAPI::removeEvent(PHANDLE, "hyprbars.drag");
    if (g_pGlobalState && g_pGlobalState->xModeEvent)
        HyprlandAPI::removeEvent(PHANDLE, "hyprbars.x_mode");

    // (tim) Unloading a plugin does not destroy its window decorations, so
    // remove our bars from every window first; otherwise the titlebars stay on
    // screen after the plugin is unloaded.
    {
        auto bars = g_pGlobalState->bars;
        for (auto& b : bars) {
            if (b)
                HyprlandAPI::removeWindowDecoration(PHANDLE, b.get());
        }
    }

    for (auto& m : State::monitorState()->monitors())
        m->m_scheduledRecalc = true;

    g_pHyprRenderer->m_renderPass.removeAllOfType("CBarPassElement");

    Desktop::Rule::windowEffects()->unregisterEffect(g_pGlobalState->barColorRuleIdx);
    Desktop::Rule::windowEffects()->unregisterEffect(g_pGlobalState->titleColorRuleIdx);
    Desktop::Rule::windowEffects()->unregisterEffect(g_pGlobalState->nobarRuleIdx);
    Desktop::Rule::windowEffects()->unregisterEffect(g_pGlobalState->alwaysTabbarRuleIdx);
}
