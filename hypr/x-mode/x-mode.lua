-- omarchy-x-mode: the macOS-like desktop layer.
--
-- Loaded from a sentinel block at the end of ~/.config/hypr/hyprland.lua:
--   -- >>> omarchy-x-mode >>>
--   dofile((os.getenv("HOME") or "") .. "/.config/hypr/x-mode/x-mode.lua")
--   -- <<< omarchy-x-mode <<<
--
-- This file holds the pack: the floating desktop, the Mac titlebar/tabbar
-- (patched hyprbars), and the Rectangle-style snap + same-app grouping engine.
-- Geometry is not here: the plugin owns it (hyprbars/snap.cpp -- zones, the snap
-- cycle, the work frame, the chrome), and this config asks it. Pure parsing
-- lives next to it in the same directory so it can be tested on its own
-- (tests/unit). Personal look'n'feel (input, monitors, decoration, native snap,
-- ...) lives in a separate file the pack does not own -- see
-- omarchy-x-vm/taste.lua -- so uninstalling the pack never removes it.

-- Resolve this file's directory so the sibling modules are found both installed
-- (~/.config/hypr/x-mode/) and straight from the repo (the tests load this file
-- out of hypr/x-mode/).
local X_MODE_DIR = (debug.getinfo(1, "S").source or ""):match("^@(.*/)") or "./"
local settings = dofile(X_MODE_DIR .. "settings.lua")
local theme = dofile(X_MODE_DIR .. "theme.lua")
local mru = dofile(X_MODE_DIR .. "mru.lua")
local group = dofile(X_MODE_DIR .. "group.lua")
local supermap = dofile(X_MODE_DIR .. "supermap.lua")
local textkeys = dofile(X_MODE_DIR .. "textkeys.lua")

-- A list out of a query result. Omarchy's keybindings scan
-- (`omarchy-menu-keybindings`) dofiles hyprland.lua with a stub `hl` whose every
-- field is a callable proxy that answers any index, so a query returns that
-- proxy instead of a list and `ipairs` walks it forever -- that is what left
-- three `lua` processes pinned at 100%. The proxy has no __len, so `#` reads 0
-- and the list comes back empty; in Hyprland the result is a plain array.
local function as_list(v)
  if type(v) ~= "table" or #v == 0 then
    return {}
  end
  return v
end


-- ---------------------------------------------------------------------------
-- Runtime on/off. The bar widget writes ~/.local/state/omarchy-x-mode/enabled
-- then runs `hyprctl reload`. Off skips the rest of this file so Omarchy's
-- binds, tiling and animations come back; the plugin stays loaded.
-- $X_MODE_STATE overrides the state directory, so a nested test session keeps
-- its own state instead of touching the real one.
-- ---------------------------------------------------------------------------

local X_MODE_STATE = os.getenv("X_MODE_STATE") or ((os.getenv("HOME") or "") .. "/.local/state/omarchy-x-mode")

local function x_mode_wanted()
  local file = io.open(X_MODE_STATE .. "/enabled", "r")
  if file == nil then
    return true
  end
  local line = (file:read("*l") or ""):lower()
  file:close()
  return not (line:match("^off") or line == "0" or line == "false")
end

local function restore_desktop()
  -- Same idea as install.sh uninstall: ungroup everything, restore windows
  -- that were floating before the pack, tile the rest.
  for _, w in ipairs(as_list(hl.get_windows())) do
    if w.group ~= nil then
      pcall(function()
        hl.dispatch(hl.dsp.window.move({ out_of_group = true, window = w }))
      end)
    end
  end
  hl.timer(function()
    local prior = {}
    local file = io.open(X_MODE_STATE .. "/prior-windows.json", "r")
    if file then
      local raw = file:read("*a") or ""
      file:close()
      for obj in raw:gmatch("%b{}") do
        local addr = obj:match('"address"%s*:%s*"([^"]+)"')
        if addr then
          local atx, aty = obj:match('"at"%s*:%s*%[%s*([-%d.]+)%s*,%s*([-%d.]+)')
          local sx, sy = obj:match('"size"%s*:%s*%[%s*([-%d.]+)%s*,%s*([-%d.]+)')
          prior[addr] = {
            floating = obj:match('"floating"%s*:%s*true') ~= nil,
            x = tonumber(atx), y = tonumber(aty),
            w = tonumber(sx), h = tonumber(sy),
          }
        end
      end
    end
    for _, w in ipairs(as_list(hl.get_windows())) do
      local snap = prior[tostring(w.address or "")]
      local want_float = snap and snap.floating or false
      if want_float then
        if not w.floating then
          hl.dispatch(hl.dsp.window.float({ action = "enable", window = w }))
        end
        if snap.x and snap.y and snap.w and snap.h then
          hl.dispatch(hl.dsp.window.resize({ x = snap.w, y = snap.h, relative = false, window = w }))
          hl.dispatch(hl.dsp.window.move({ x = snap.x, y = snap.y, relative = false, window = w }))
        end
      elseif w.floating then
        hl.dispatch(hl.dsp.window.float({ action = "disable", window = w }))
      end
    end
  end, { timeout = 150, type = "oneshot" })
end

if not x_mode_wanted() then
  -- Remember that the desktop was switched off, so the next time it comes on
  -- (the bar panel writes "on" and reloads) the windows get spread across the
  -- halves again, the same as a fresh install. Only the off path writes it:
  -- the on path consumes it, so a reload while already on does nothing.
  pcall(function()
    local marker = io.open(X_MODE_STATE .. "/arrange", "w")
    if marker then
      marker:write("on")
      marker:close()
    end
  end)
  -- Keep the plugin around so the bar toggle still works after a reload.
  o.exec_on_start("hyprpm reload -n")
  o.exec_on_start("sh -c 'hyprctl plugin unload \"$HOME/.local/share/hyprbars/hyprbars.so\" >/dev/null 2>&1; hyprctl plugin list 2>/dev/null | grep -q hyprbars || hyprctl plugin load \"$HOME/.local/share/hyprbars/x-mode-hyprbars.so\"'")
  pcall(function()
    hl.config({ plugin = { hyprbars = { enabled = false } } })
    if hl.plugin and hl.plugin.hyprbars and hl.plugin.hyprbars.x_mode then
      hl.plugin.hyprbars.x_mode(false)
    end
  end)
  hl.timer(restore_desktop, { timeout = 200, type = "oneshot" })
  return
end

-- ---------------------------------------------------------------------------
-- Required Hyprland config
-- ---------------------------------------------------------------------------

-- Fallbacks for the config keys read back below. Everything the pack uses is a
-- real Hyprland config key — a standard key, or plugin:hyprbars:* registered by
-- the patched plugin — so it is tuned in the config, never in code. These
-- fallbacks only apply if a key isn't readable.
local GAP_FALLBACK      = 8
local TITLEBAR_FALLBACK = 28

hl.config({
  general = {
    -- Otherwise Hyprland makes the parent of a modal window non-interactive, so
    -- with a dialog open (gitfourchette's push, a save prompt, ...) clicks on the
    -- parent fall through to whatever is behind it -- a different app when the
    -- parent fills the screen. The modal is just another floating window here,
    -- and a click on the parent should focus the parent.
    modal_parent_blocking = false,
  },
  cursor = {
    -- Do not move the pointer when a window is focused (e.g. from the dock).
    no_warps = true,
  },
  input = {
    -- Click to focus: keyboard focus never follows the pointer over a window
    -- (that would be 1). 2 is Hyprland's "detached": pointer events still go to
    -- the window under the cursor, so scrolling and the like work over a window
    -- without focusing it, while focus itself still changes on click.
    -- Omarchy sets follow_mouse = 1 earlier in the config; this file is loaded
    -- last and puts it back.
    follow_mouse = 2,
    -- The default (1) still focuses the window under the cursor when one of the
    -- two is tiled and the other is floating. A client-maximized window is that
    -- tiled side, so moving the pointer onto it focuses it even though
    -- follow_mouse is 2. Everything here is floating; hover must not focus.
    float_switch_override_focus = 0,
  },
  binds = {
    -- Matches the drag threshold in the patched hyprbars titlebar drag.
    drag_threshold = 10,
  },
  group = {
    auto_group = false,
    -- Never mix apps in one group: disable dragging windows/groupbars into
    -- other groups. Same-app auto-grouping (join_same_app below) is
    -- programmatic and unaffected.
    drag_into_group = 0,
    merge_groups_on_groupbar = false,
    merge_floated_into_tiled_on_groupbar = false,
    groupbar = {
      -- Tabs are drawn by the patched hyprbars (with per-tab close buttons);
      -- the native groupbar is disabled to avoid a double tabbar.
      enabled = false,
    },
  },
})

-- Instant window appearance and movement: a new same-app window must jump to
-- the existing window's position in the same frame, and switching a group tab
-- must not animate borders (it looked like a flicker).
hl.animation({ leaf = "windowsIn", enabled = false })
hl.animation({ leaf = "windowsOut", enabled = false })
hl.animation({ leaf = "windowsMove", enabled = false })
hl.animation({ leaf = "fadeIn", enabled = false })
hl.animation({ leaf = "fadeOut", enabled = false })
hl.animation({ leaf = "border", enabled = false })

-- Desktop-style window rules: everything opens floating (the pack is a
-- macOS-like desktop, not a tiler); Super+T (toggle floating/tiling) is unbound
-- below.
-- suppress_event = maximize: a client request to maximize (Zed does this on
-- startup) would enter Hyprland's FSMODE_MAXIMIZED. That mode is not a
-- floating window, and a later move is ignored, so the titlebar drag does
-- nothing until something (Super+Alt+F) takes it back out. Real fullscreen
-- is a different request and is not suppressed.
o.window(".*", { float = true, opacity = "1.0 override 1.0 override", suppress_event = "maximize" })
-- Omarchy's browser defaults force Chromium-based apps to tile. That tag rule
-- wins over the catch-all above, so override it here.
o.window({ tag = "chromium-based-browser" }, { tile = false, float = true })

-- Mac-style titlebar via the patched hyprbars (native decoration, moves in
-- lockstep with the window). One close button on the left; the tabbar sits
-- right below it. The chrome follows the current Omarchy theme: read the
-- palette the shell also uses (~/.local/state/omarchy/current/theme/colors.toml)
-- and hand the background/foreground to hyprbars; the patched tabbar derives
-- its shades from these two, so a theme switch (plus a Hyprland reload)
-- recolors everything.
local function omarchy_theme_colors()
  local home = os.getenv("HOME") or ""
  local file = io.open(home .. "/.local/state/omarchy/current/theme/colors.toml", "r")
  if file == nil then
    return {}
  end
  local raw = file:read("*a") or ""
  file:close()
  return theme.parse_toml(raw)
end

local palette = omarchy_theme_colors()
local bar_bg, bar_fg = theme.bar_colors(palette)

pcall(function()
  hl.config({
    plugin = {
      hyprbars = {
        enabled = true,
        bar_height = TITLEBAR_FALLBACK,
        bar_color = bar_bg,
        ["col.text"] = bar_fg,
        bar_title_enabled = true,
        bar_text_size = 11,
        bar_text_font = "sans-serif",
        bar_text_align = "center",
        bar_buttons_alignment = "left",
        bar_part_of_window = true,
        bar_precedence_over_border = true,
        bar_padding = 10,
        bar_button_padding = 6,
        icon_on_hover = false,
        -- The ✕ shows and closes only on the current tab, and only while the
        -- group has focus; anywhere else clicking a tab focuses/switches instead.
        tab_close_active_only = true,
        -- Card width plus half of gaps_out. Set again after GAP_OUT is known.
        x_mode_dock_inset = 45,
      },
    },
  })
  if hl.plugin and hl.plugin.hyprbars and hl.plugin.hyprbars.add_button then
    hl.plugin.hyprbars.add_button({
      -- Match the tabbar close (✕): the theme's text color, not macOS red.
      bg_color = bar_fg,
      fg_color = bar_fg,
      size = 12,
      icon = "",
      -- Close the whole group (all tabs) when grouped, otherwise just the
      -- window. The button action is run as a shell command, so it evals Lua via
      -- hyprctl.
      action = [[hyprctl eval 'local w=hl.get_active_window(); if w then if w.group then for _,m in ipairs(w.group.members) do hl.dispatch(hl.dsp.window.close({window=m})) end else hl.dispatch(hl.dsp.window.close({window=w})) end end']],
    })
  end
end)

-- ---------------------------------------------------------------------------
-- Tunables, read from the Hyprland config
-- ---------------------------------------------------------------------------
-- Everything here is a real config key, so it is set in hyprland.lua or the
-- theme like any other option. Standard Hyprland keys are used where they
-- exist; x-mode's own knobs live under plugin:hyprbars:* (registered by the
-- patched plugin), so the C++ and Lua read the same value.
local function cfg_int(key, fallback)
  local ok, value = pcall(hl.get_config, key)
  if not ok or value == nil then
    return fallback
  end
  if type(value) == "number" then
    return math.floor(value)
  end
  if type(value) == "table" then
    return math.floor(value.top or value[1] or fallback)
  end
  if type(value) == "string" then
    local n = value:match("(%d+)")
    if n ~= nil then
      return tonumber(n)
    end
  end
  return fallback
end

local TITLEBAR          = cfg_int("plugin:hyprbars:bar_height", TITLEBAR_FALLBACK)
-- Read live: the panel's "No gaps" option rewrites general:gaps_out and
-- general:border_size at runtime, and snap geometry has to follow.
local function GAP_OUT()
  return cfg_int("general:gaps_out", GAP_FALLBACK)
end
local function BORDER()
  return cfg_int("general:border_size", 2)
end
-- The dock overlays windows (it reserves no screen space). Snap zones keep the
-- full work area and only the right edge is pulled in by the dock card plus half
-- the outer gap, which is the dock's own screen margin (Style.gapsOut). The card
-- width is the dock's own (Dock.qml: iconSize + pad*2); it is read off the
-- x-mode-dock layer below, so a change to the card moves the zones with it.
-- Until that layer exists (the shell starts after this config) the last width
-- it had is used, and this one only before it has ever been seen.
local DOCK_CARD_FALLBACK = 40
local dock_card = DOCK_CARD_FALLBACK
local function DOCK_PULL()
  return dock_card + math.floor(GAP_OUT() / 2)
end
local GROUP_MIN_W       = cfg_int("plugin:hyprbars:x_mode_group_min_width", 400)
local GROUP_MIN_H       = cfg_int("plugin:hyprbars:x_mode_group_min_height", 300)

-- Open floating windows with the outer gap under the top bar. Hyprland measures
-- float_gaps from the work area (which already starts below the top bar) and
-- hyprbars draws its titlebar *above* the window box, so the titlebar lands at
-- float_gaps.top - TITLEBAR below the bar. Add the effective outer gap and the
-- border so the titlebar sits exactly at topbar + gap + border, and give the
-- other sides the same gap + border so a window never opens flush to an edge.
-- float_gaps and the dock inset both derive from the live gap and border, so
-- the panel's "No gaps" option recomputes them instead of leaving the values
-- captured at load.
local function apply_gap_geometry()
  local edge = GAP_OUT() + BORDER()
  hl.config({
    general = {
      float_gaps = {
        top = TITLEBAR + edge,
        left = edge,
        right = edge,
        bottom = edge,
      },
    },
    plugin = {
      hyprbars = {
        x_mode_dock_inset = DOCK_PULL(),
      },
    },
  })
end

apply_gap_geometry()

-- The dock's card width, taken from its own layer surface (namespace
-- x-mode-dock). The shell starts after this config, and the layer is gone for
-- a moment while it restarts, so a missing layer keeps the last width: zones
-- must not jump to the fallback and back every time the shell blinks. A layer
-- that maps before its first arrange reports no width; that one is skipped.
local function dock_card_now()
  local ok, layers = pcall(hl.get_layers, { namespace = "x-mode-dock" })
  if not ok then
    return nil
  end
  for _, layer in ipairs(as_list(layers)) do
    local w = tonumber(layer.w)
    if w ~= nil and w > 0 then
      return math.floor(w)
    end
  end
  return nil
end

local function refresh_dock_card()
  local w = dock_card_now()
  if w == nil or w == dock_card then
    return
  end
  dock_card = w
  apply_gap_geometry()
end

-- Load hyprpm-managed plugins, then the patched x-mode hyprbars on login
-- (install.sh loads it immediately too). Disable a stock hyprbars first so only
-- one is active.
o.exec_on_start("hyprpm reload -n")
o.exec_on_start("sh -c 'hyprctl plugin unload \"$HOME/.local/share/hyprbars/hyprbars.so\" >/dev/null 2>&1; hyprctl plugin list 2>/dev/null | grep -q hyprbars || hyprctl plugin load \"$HOME/.local/share/hyprbars/x-mode-hyprbars.so\"'")

-- ---------------------------------------------------------------------------
-- Snap + same-app grouping engine
-- ---------------------------------------------------------------------------

-- Rectangle-style snap for floating windows.
-- Titlebar drag-to-edge lives in the patched hyprbars (CDragSession): it moves
-- the window, draws the preview, and applies the snap. Lua keeps restore +
-- Super+Alt hotkeys, and defers same-app grouping while a drag is in progress.

local saved = {}
-- Same-app windows that arrived during a drag; joined after the drag ends.
local pending_join = {}
local flush_pending_joins = function() end

local function bars()
  return hl.plugin and hl.plugin.hyprbars
end

local function dragging()
  local p = bars()
  return p and p.dragging and p.dragging() or false
end

local function drag_owns(w)
  local p = bars()
  return p and p.drag_owns and p.drag_owns(w) or false
end

local function vec(value)
  if type(value) ~= "table" then
    return 0, 0
  end
  if value.x ~= nil then
    return value.x, value.y or 0
  end
  if value.w ~= nil then
    return value.w, value.h or 0
  end
  return value[1] or 0, value[2] or 0
end

-- The top the bar reserves. It is a layer-shell surface and is gone for a
local function usable(monitor)
  -- The plugin's frame: the monitor minus its reserved area and the dock inset,
  -- with the same bar-height memory across a shell restart a snap uses. It is
  -- the frame a left and a right half split, so a clamp or a restore default
  -- taken from it can never disagree with the zones.
  local p = bars()
  if p == nil or p.usable == nil or monitor == nil then
    return nil
  end
  local ok, box = pcall(p.usable, monitor.name)
  if not ok or type(box) ~= "table" then
    return nil
  end
  return box.x, box.y, box.w, box.h
end

local function window_class(w)
  if w == nil then
    return ""
  end
  return string.lower(tostring(w.initial_class or w.class or ""))
end

local function chrome_h(window)
  -- The plugin's number, including its no_bar check (Snap::chromeH): a window
  -- with its titlebar off has no chrome to keep free above its content.
  local p = bars()
  if p == nil or p.chrome_height == nil then
    return 0
  end
  local ok, h = pcall(p.chrome_height, window)
  if not ok or type(h) ~= "number" then
    return 0
  end
  return h
end

local function ensure_tab_group(window)
  if window == nil or window.group ~= nil then
    return
  end
  pcall(function()
    hl.dispatch(hl.dsp.group.toggle({ window = window }))
  end)
end

-- Defined later (need window_class/ws_id/... helpers); forward-declared so
-- snap() can join an existing same-app group before creating a new one.
local find_peer
local join_same_app
local apps_off = {}
-- Classes whose Super+W goes to the app as Ctrl+W (the panel's per-app switch).
local ctrl_w_apps = {}
-- Classes with the panel's "Super works as Ctrl" flag: unbound Super+key
-- combinations reach them as Ctrl+key.
local ctrl_as_super = {}
-- Occupied Super keys stolen per class (supermap ids: Q, TAB, SHIFT+TAB, B).
-- Unbind is global; the wrap checks this set for the focused window, like Super+W.
local steal_keys = {}
-- Classes with the panel's "Ctrl+C as Ctrl+Shift+C" flag: an app that hosts a
-- terminal needs Ctrl+C left to the shell, so the pack hands it Ctrl+Shift+C
-- instead and lets the app's own binding decide what that means.
local ctrl_c_shift_apps = {}
-- Classes with the panel's "⌘+click as Ctrl+click" flag: Super+mouse button
-- is sent as Ctrl+click. Unflagged apps still get Super+click (pass_event).
local ctrl_click_apps = {}
local ctrl_c_binds = {}
-- Defined with the other option appliers (it reads the bind table out of band),
-- forward-declared so the app refresh can call it.
local apply_super_ctrl

-- Send a chord to a window. The key goes as a keycode, not as a name:
-- `send_shortcut` resolves a name by looking the keysym up in the *active*
-- layout, so on a Cyrillic layout Ctrl+T would not resolve at all. A keycode is
-- what "Cmd+T means the physical T key" wants anyway.
local function send_chord(mods, key, w)
  local code = supermap.key_code(key)
  if code == nil then
    return false
  end
  hl.dispatch(hl.dsp.send_shortcut({
    mods = mods,
    key = "code:" .. tostring(code),
    window = w,
  }))
  return true
end

local function send_ctrl(key, shift, w)
  return send_chord(shift and "CTRL SHIFT" or "CTRL", key, w)
end

local function key_stolen(cls, key, shift)
  local ids = steal_keys[cls]
  return ids ~= nil and ids[supermap.key_id(key, shift)] == true
end

local function window_by_addr(addr)
  if addr == nil then
    return nil
  end
  local a = tostring(addr)
  if a:sub(1, 8) ~= "address:" then
    a = "address:" .. a
  end
  return hl.get_window(a)
end

local function save(window)
  if window == nil then
    return
  end
  local x, y = vec(window.at)
  local w, h = vec(window.size)
  saved[window.address] = { x = x, y = y, w = w, h = h }
end

local function place(x, y, w, h, window)
  window = window or hl.get_active_window()
  if window == nil then
    return
  end

  if window.fullscreen and window.fullscreen ~= 0 then
    hl.dispatch(hl.dsp.window.fullscreen({ action = "unset", window = window }))
  end
  if not window.floating then
    hl.dispatch(hl.dsp.window.float({ action = "enable", window = window }))
  end

  hl.dispatch(hl.dsp.window.resize({ x = w, y = h, relative = false, window = window }))
  hl.dispatch(hl.dsp.window.move({ x = x, y = y, relative = false, window = window }))
end

local function snap(kind, window)
  window = window or hl.get_active_window()
  if window == nil then
    return
  end

  if kind ~= "restore" then
    save(window)
  end

  if kind == "restore" then
    local monitor = window.monitor or hl.get_monitor_at_cursor() or hl.get_active_monitor()
    if monitor == nil then
      return
    end
    local x, y, w, h = usable(monitor)
    if x == nil then
      return
    end
    local prev = saved[window.address]
    if prev then
      place(prev.x, prev.y, prev.w, prev.h, window)
    else
      place(x + math.floor(w * 0.15), y + math.floor(h * 0.12), math.floor(w * 0.7), math.floor(h * 0.76), window)
    end
    return
  end

  -- Join an existing same-app group first; only create a fresh group if there
  -- is no group to join (otherwise snapping would spawn a second group). Join
  -- directly (no keep_pos) so the snapped position is not undone afterwards.
  if window.group == nil and find_peer ~= nil then
    local peer = find_peer(window)
    if peer ~= nil and peer.group ~= nil then
      pcall(function()
        peer.group:add(window)
      end)
    end
  end
  -- The zone geometry (and the client minimum a zone grows to) is the plugin's
  -- (Snap::applyKind / contentBox). Without the plugin there is no snap: the
  -- pack is its plugin, and a second implementation in here is exactly the
  -- drift the old fallback caused.
  local p = bars()
  if p ~= nil and p.snap ~= nil then
    pcall(function()
      p.snap({ kind = kind, window = window })
    end)
  end
end

-- Super+Alt+Left/Right step the window through the cycle sizes on that side
-- (half, two thirds, a third) and snap it to the side's zone when it is not on
-- one of them yet. Both the sizes and the matching live in the plugin
-- (Snap::cycle): they are the same frame, chrome, client minimum and insets a
-- zone is built from, so there is no second copy to keep in step.
local function snap_or_expand(side)
  local window = hl.get_active_window()
  local monitor = hl.get_monitor_at_cursor() or hl.get_active_monitor()
  if window == nil or monitor == nil then
    return
  end

  local p = bars()
  if p ~= nil and p.cycle ~= nil then
    local ok, stepped = pcall(p.cycle, window, side)
    if ok and stepped then
      return
    end
  end
  snap(side, window)
end

-- Super+LMB was window drag, Super+RMB was resize. Titlebar drag-to-edge
-- lives in hyprbars (CDragSession); Super+click is Ctrl+click for apps with
-- the panel flag, and otherwise reaches the app as Super+click.
hl.unbind("SUPER + mouse:272")
hl.unbind("SUPER + mouse:273")
local function window_at_cursor()
  local pos = hl.get_cursor_pos()
  if pos == nil then
    return nil
  end
  local x, y = vec(pos)
  local hit = nil
  for _, w in ipairs(as_list(hl.get_windows())) do
    if w.mapped and not w.hidden then
      local ax, ay = vec(w.at)
      local ww, hh = vec(w.size)
      if x >= ax and y >= ay and x < ax + ww and y < ay + hh then
        hit = w
      end
    end
  end
  return hit
end
local function super_ctrl_click(button)
  return function()
    -- Titlebar / empty space: let the click through (hyprbars, focus).
    -- The window under the cursor, not the focused one: Cmd+click a link in
    -- a background window should still be Ctrl+click there.
    local w = window_at_cursor()
    if w == nil or not ctrl_click_apps[window_class(w)] then
      return { pass_event = true }
    end
    hl.dispatch(hl.dsp.send_shortcut({
      mods = "CTRL",
      key = "mouse:" .. tostring(button),
      window = w,
    }))
  end
end
o.bind("SUPER + mouse:272", "Ctrl+click", super_ctrl_click(272), { mouse = true })
o.bind("SUPER + mouse:273", "Ctrl+click", super_ctrl_click(273), { mouse = true })
o.bind("SUPER + mouse:274", "Ctrl+click", super_ctrl_click(274), { mouse = true })

-- Hyprland tracks two fullscreen flags: the compositor's own (internal) and the
-- client's xdg request. Either one means the window is not a normal floating
-- window, and the pack must not move, resize or re-fit it. Checking only
-- `fullscreen` left a client-fullscreen window (a video player, a game, or an
-- app that stayed fullscreen after the compositor's flag was cleared) to be
-- pushed below the top bar and off the bottom of the screen by the next clamp.
local function is_fullscreen(w)
  if w == nil then
    return false
  end
  return (w.fullscreen ~= nil and w.fullscreen ~= 0) or (w.fullscreen_client ~= nil and w.fullscreen_client ~= 0)
end

-- Keeping a window below the bar is the plugin's job: CHyprBar::updateWindow
-- runs on every move and resize (updateWindowDecos calls it) and
-- Snap::clampToWorkArea fits the box with the same gap, border and chromeH the
-- snap uses. Lua no longer watches geometry.

-- GTK layer-shell helpers are not started from config: connecting back
-- during Hyprland reload can freeze the compositor.
hl.layer_rule({
  match = { namespace = "omarchy-snap-preview" },
  no_anim = true,
  ignore_alpha = 1,
})
hl.layer_rule({
  match = { namespace = "omarchy-switcher" },
  no_anim = true,
  ignore_alpha = 1,
})
hl.layer_rule({
  name = "titlebar-no-anim",
  match = { namespace = "omarchy-titlebar" },
  no_anim = true,
})

-- ---------------------------------------------------------------------------
-- Cmd+Tab app switcher
-- ---------------------------------------------------------------------------
-- The preview overlay (Quickshell, Switcher.qml) is driven by a command file,
-- like the snap preview: "show <active-class> <class>..." while cycling, "hide"
-- when Super is released.
local SWITCHER_PATH = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/omarchy-switcher.cmd"
local last_switcher = ""
local switcher_active = false

local function switcher_write(line)
  if line == last_switcher then
    return
  end
  last_switcher = line
  local file = io.open(SWITCHER_PATH, "w")
  if file == nil then
    return
  end
  file:write(line .. "\n")
  file:close()
end

local switcher_order = {}
local switcher_tokens = {}
local switcher_index = 0

-- macOS-like MRU order, tracked per class and most recent first. Hyprland's
-- focus_history_id is per window and is rewritten every time the switcher
-- focuses an app while cycling, so tabbing across the row would scramble the
-- order (apps passed over became "most recent", pushing the apps the user
-- actually used apart). Instead record only real focus changes, and while the
-- switcher is held record nothing: the one app left focused on release is the
-- only one that moves to the front.
local switcher_mru = {}

local function switcher_touch(cls)
  mru.touch(switcher_mru, cls)
end

-- Raise + focus the most recently focused window of a class (any workspace;
-- focusing it also switches to its workspace).
-- Super+Tab focuses the chosen app on the key itself. A fullscreen window
-- would take that focus straight back, so leave fullscreen on every other
-- app first. The same app stays fullscreen: the key did not select anything
-- else.
local function leave_fullscreen_for(cls)
  for _, w in ipairs(as_list(hl.get_windows())) do
    if w.fullscreen and w.fullscreen ~= 0 and tostring(w.class or "") ~= cls then
      hl.dispatch(hl.dsp.window.fullscreen({ action = "unset", window = w }))
    end
  end
end

local function switcher_focus(cls)
  leave_fullscreen_for(cls)
  local best = nil
  local best_focus = nil
  for _, w in ipairs(as_list(hl.get_windows())) do
    if tostring(w.class or "") == cls then
      local f = tonumber(w.focus_history_id) or 999999
      if best == nil or f < best_focus then
        best = w
        best_focus = f
      end
    end
  end
  if best ~= nil then
    -- No raise here: focusing routes through window.active, which raises.
    hl.dispatch(hl.dsp.focus({ window = best }))
  end
end

-- Cycle the app switcher by step (+1 / -1). The list is built once when the
-- switcher opens and kept while Super is held, so the row and the cycle stay in
-- sync (cyclenext's reverse does not wrap the same way).
local function switcher_step(step)
  local active = hl.get_active_window()
  local active_class = active and tostring(active.class or "") or ""
  if not switcher_active or #switcher_order == 0 then
    -- One entry per class (any workspace), using the class's most recent window
    -- (smallest focus_history_id): a class can have several windows, and taking
    -- the first one in hl.get_windows() order would sort it by the wrong window.
    local by_class = {}
    for _, w in ipairs(as_list(hl.get_windows())) do
      local cls = tostring(w.class or "")
      if cls ~= "" then
        local f = tonumber(w.focus_history_id) or 999999
        if by_class[cls] == nil or f < by_class[cls].focus then
          by_class[cls] = { focus = f, addr = tostring(w.address or "") }
        end
      end
    end
    local entries = {}
    for cls, e in pairs(by_class) do
      table.insert(entries, { cls = cls, focus = e.focus, addr = e.addr })
    end
    -- Most recently used first (like macOS Cmd+Tab); see mru.sort.
    mru.sort(entries, switcher_mru)
    local classes = {}
    local tokens = {}
    for _, e in ipairs(entries) do
      table.insert(classes, e.cls)
      table.insert(tokens, e.cls .. "|" .. e.addr)
    end
    switcher_order = classes
    switcher_tokens = tokens
    switcher_index = 1
    for i, cls in ipairs(classes) do
      if cls == active_class then
        switcher_index = i
        break
      end
    end
    switcher_active = true
  end
  local n = #switcher_order
  if n == 0 then
    return
  end
  switcher_index = mru.step(switcher_index, n, step)
  local cls = switcher_order[switcher_index]
  switcher_focus(cls)
  switcher_write("show " .. cls .. " " .. table.concat(switcher_tokens, " "))
end

local function switcher_hide()
  if not switcher_active then
    return
  end
  -- The app left focused (keyboard cycle or a click in the overlay) is the one
  -- that moves to the front of the MRU order. Read it from the live focus
  -- rather than switcher_index so a mouse pick is recorded correctly too.
  local active = hl.get_active_window()
  if active ~= nil then
    switcher_touch(active.class)
  end
  switcher_active = false
  switcher_order = {}
  switcher_index = 0
  switcher_write("hide")
end

-- A real focus change updates the MRU order. While the switcher is held the
-- focus moves through every app tabbed over, so those are ignored here.
--
-- Focusing a window does not raise it: rawWindowFocus only brings a grouped
-- window's target to the top, and a focus dispatch never raises at all, so a
-- focused window can sit behind another app. hyprbars.raise does the raise
-- through CWindowState::raise, which does not run the simulateMouseMovement
-- alter_zorder ends with — that re-entered the tab drag and froze the
-- compositor — and it holds the window under a covering fullscreen one instead
-- of drawing it on top.
-- raising guards the re-entry: hyprbars.raise focuses the window, and a focus
-- emits window.active again. The second pass would raise once more for nothing.
local raising = false

hl.on("window.active", function(w, reason)
  if w == nil or raising then
    return
  end
  local p = bars()
  if p ~= nil and p.raise ~= nil and w.floating then
    raising = true
    pcall(p.raise, w)
    raising = false
  end
  if switcher_active then
    return
  end
  switcher_touch(w.class)
end)

-- Super (keycode 133/134 + 8) released: hide the switcher.
hl.on("input.keyboard.key", function(keycode, _, state)
  if switcher_active and state == 0 and (keycode == 133 or keycode == 134) then
    switcher_hide()
  end
end)

-- Cmd+arrows focus the neighbour in Omarchy's defaults. This desktop does not
-- tile, and the keys should reach the app, so drop them. Snap stays on
-- Cmd+Alt+arrows.
hl.unbind("SUPER + LEFT")
hl.unbind("SUPER + RIGHT")
hl.unbind("SUPER + UP")
hl.unbind("SUPER + DOWN")

-- Cmd +/- (and Cmd+Shift+/-) resize the active window in Omarchy's defaults
-- (resizeactive on code:20 = '-' and code:21 = '='). The desktop resizes by
-- dragging the edge, so drop them.
hl.unbind("SUPER + code:20")
hl.unbind("SUPER + code:21")
hl.unbind("SUPER + SHIFT + code:20")
hl.unbind("SUPER + SHIFT + code:21")

-- Tiling leftovers from Omarchy's defaults. This desktop is always floating
-- (snap/resize by drag or Super+Alt+arrows), so drop the tiler keys.
-- Same-app grouping (tabs) stays; those binds are not tiling.
hl.unbind("SUPER + T") -- toggle floating/tiling
hl.unbind("SUPER + L") -- workspace layout picker (dwindle/scrolling)
hl.unbind("SUPER + O") -- pop out: float + pin
hl.unbind("SUPER + J") -- togglesplit
hl.unbind("SUPER + P") -- pseudo (dwindle stretch)
hl.unbind("SUPER + CTRL + F") -- tiled fullscreen
hl.unbind("SUPER + Home") -- restore saved tiled width
hl.unbind("SUPER + ALT + Home") -- save tiled width
-- Remaining keyboard-resize steps (plain Cmd+/- already dropped above).
hl.unbind("SUPER + ALT + code:20")
hl.unbind("SUPER + ALT + code:21")
hl.unbind("SUPER + SHIFT + ALT + code:20")
hl.unbind("SUPER + SHIFT + ALT + code:21")
hl.unbind("SUPER + CTRL + code:20")
hl.unbind("SUPER + CTRL + code:21")
hl.unbind("SUPER + CTRL + SHIFT + code:20")
hl.unbind("SUPER + CTRL + SHIFT + code:21")

-- Cmd+W closes the active window (Omarchy's killactive). Just close it: the
-- patched hyprbars keeps the group focused on the previous tab and raises it
-- from its single window.close listener, which Cmd+W, the tabbar close button
-- and apps closing their own window all share.
--
-- Apps the panel flagged send Ctrl+W instead, so Cmd+W closes the tab rather
-- than the whole window (a browser, a terminal). The key goes to the focused
-- window as a real Ctrl+W; the close path above stays out of the way.
hl.unbind("SUPER + W")
o.bind("SUPER + W", "Close window", function()
  local w = hl.get_active_window()
  if w == nil then
    return
  end
  if ctrl_w_apps[window_class(w)] then
    send_ctrl("W", false, w)
    return
  end
  hl.dispatch(hl.dsp.window.close({ window = w }))
end)

-- Cmd+Q closes the whole app: all tabs of the group (like the titlebar close
-- button), or just the window when it is not grouped.
hl.unbind("SUPER + Q")
o.bind("SUPER + Q", "Close app", function()
  local w = hl.get_active_window()
  if w == nil then
    return
  end
  if key_stolen(window_class(w), "Q", false) then
    send_ctrl("Q", false, w)
    return
  end
  if w.group ~= nil then
    for _, m in ipairs(w.group.members) do
      hl.dispatch(hl.dsp.window.close({ window = m }))
    end
  else
    hl.dispatch(hl.dsp.window.close({ window = w }))
  end
end)

-- Cmd+F is Omarchy fullscreen: a Lua dispatcher, so hyprctl cannot replay it
-- after unbind. Wrap it here like Super+Q. A stolen F is Ctrl+F (Find);
-- otherwise the compositor fullscreen stays.
--
-- Ctrl+Cmd+F is fullscreen on macOS, and it is what is left when the app has
-- taken Cmd+F for Find -- so it never looks at the steal. Omarchy's own
-- Ctrl+Cmd+F (tiled fullscreen) is dropped with the other tiling keys above.
hl.unbind("SUPER + F")
local function toggle_fullscreen()
  local w = hl.get_active_window()
  if w == nil then
    return
  end
  hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen" }))
end
o.bind("SUPER + F", "Full screen", function()
  local w = hl.get_active_window()
  if w == nil then
    return
  end
  if key_stolen(window_class(w), "F", false) then
    send_ctrl("F", false, w)
    return
  end
  toggle_fullscreen()
end)
hl.unbind("SUPER + CTRL + F")
o.bind("SUPER + CTRL + F", "Full screen", toggle_fullscreen)

-- Cmd+Tab cycles through windows (like an app switcher) instead of Omarchy's
-- next/previous workspace; Cmd+Shift+Tab goes the other way. The generated
-- Super-as-Ctrl map never takes it, so a flagged app still gets the switcher
-- unless the panel steals Tab for that app (then it is Ctrl+Tab, like Super+W).
hl.unbind("SUPER + TAB")
hl.unbind("SUPER + SHIFT + TAB")
o.bind("SUPER + TAB", "Focus on next window", function()
  local w = hl.get_active_window()
  if w ~= nil and key_stolen(window_class(w), "TAB", false) then
    send_ctrl("TAB", false, w)
    return
  end
  switcher_step(1)
end)
o.bind("SUPER + SHIFT + TAB", "Focus on previous window", function()
  local w = hl.get_active_window()
  if w ~= nil and key_stolen(window_class(w), "TAB", true) then
    send_ctrl("TAB", true, w)
    return
  end
  switcher_step(-1)
end)

-- Alt+Tab switches between the tabs of the focused group (Omarchy binds it to
-- cyclenext, which we do not want). Set the group's active index directly:
-- group.next() briefly focuses something else, and a follow-up focus would
-- unfocus and refocus the window within one switch.
local function switch_group_tab(next)
  local w = hl.get_active_window()
  if w == nil or w.group == nil then
    return
  end
  local members = w.group.members
  local n = #members
  if n < 2 then
    return
  end
  local cur = w.group.current
  local idx = 1
  for i = 1, n do
    if members[i].address == cur.address then
      idx = i
      break
    end
  end
  idx = next and (idx % n) + 1 or ((idx + n - 2) % n) + 1
  -- group.active focuses the new tab (CGroup::setCurrent calls rawWindowFocus
  -- when the group held focus) and focusing routes through window.active, which
  -- raises. No second dsp.focus: that is a fullWindowFocus plus warpCursor, so
  -- the window is unfocused and refocused within one switch, and Zed paints its
  -- title bar from is_window_active, so that gap dims the bar for a frame.
  hl.dispatch(hl.dsp.group.active({ index = idx, window = w }))
end

hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
o.bind("ALT + TAB", "Next tab", function()
  switch_group_tab(true)
end)
o.bind("ALT + SHIFT + TAB", "Previous tab", function()
  switch_group_tab(false)
end)

-- Cmd+Shift+arrows swap the window with its neighbour in Omarchy's defaults;
-- the desktop does not tile, so drop them.
hl.unbind("SUPER + SHIFT + LEFT")
hl.unbind("SUPER + SHIFT + RIGHT")
hl.unbind("SUPER + SHIFT + UP")
hl.unbind("SUPER + SHIFT + DOWN")

-- Super+Alt+Left/Right were "move window to group on left/right".
hl.unbind("SUPER + ALT + LEFT")
hl.unbind("SUPER + ALT + RIGHT")
o.bind("SUPER + ALT + LEFT", "Snap or expand window left", function()
  snap_or_expand("left")
end)
o.bind("SUPER + ALT + RIGHT", "Snap or expand window right", function()
  snap_or_expand("right")
end)

-- Super+Alt+Up/Down were "move window to group on top/bottom". We never want
-- the arrow keys to create a group, so drop those binds entirely.
hl.unbind("SUPER + ALT + UP")
hl.unbind("SUPER + ALT + DOWN")

-- Cmd+G toggles a Hyprland group, Cmd+Alt+G pulls the window out of one.
-- Same-app tabs are made by the pack, so these keys should reach the app.
hl.unbind("SUPER + G")
hl.unbind("SUPER + ALT + G")

-- Cmd+S toggles the scratchpad, Cmd+Alt+S moves the focused window into it.
-- This desktop does not use a scratchpad, so the keys should reach the app.
hl.unbind("SUPER + S")
hl.unbind("SUPER + ALT + S")

-- Super+Alt+F was Hyprland "full width" (maximized). Match drag-to-top-center instead.
hl.unbind("SUPER + ALT + F")
o.bind("SUPER + ALT + F", "Maximize window", function()
  snap("maximize")
end)
hl.unbind("SUPER + ALT + A")
o.bind("SUPER + ALT + A", "Almost maximize window", function()
  snap("almost-maximize")
end)
o.bind("CTRL + ALT + UP", "Maximize window", function()
  snap("maximize")
end)
o.bind("CTRL + ALT + DOWN", "Restore window size", function()
  snap("restore")
end)
o.bind("CTRL + ALT + U", "Snap window top-left", function()
  snap("top-left")
end)
o.bind("CTRL + ALT + I", "Snap window top-right", function()
  snap("top-right")
end)
o.bind("CTRL + ALT + J", "Snap window bottom-left", function()
  snap("bottom-left")
end)
o.bind("CTRL + ALT + K", "Snap window bottom-right", function()
  snap("bottom-right")
end)

-- --- macOS text chords ------------------------------------------------------
-- On a Mac the text system is the OS's, so Cmd+Left is the start of the line
-- and Option+Backspace deletes a word in *every* app. On Linux no such layer
-- exists: each toolkit invented its own chords, and the terminal invented
-- readline's. textkeys.lua holds what to send where (a terminal and a GUI need
-- different chords for the same function), and this binds it. The context
-- comes from Omarchy's "terminal" tag, so a terminal answers for itself.
--
-- These keys are the desktop's from here on, which is why Super+Left/Right no
-- longer reach the app as Ctrl+Left/Right (the Super-as-Ctrl plan reads the
-- live bind table, sees them taken and leaves them alone) and why Omarchy's
-- window transparency has to move off Cmd+Backspace.
local function send_chords(list, w)
  -- One chord as its own down/up pair rather than `send_shortcut`, which sends
  -- the press and the release in one call: a *second* chord sent that way right
  -- after the first arrives twice (Shift+End then two Deletes), the same
  -- stuck/repeating synthetic key Omarchy's clipboard sends key state by hand
  -- to avoid (hyprland discussion 14099). Sending it by hand also keeps a
  -- synthetic Shift from being left held for the next keystroke.
  local function send(c)
    local code = supermap.key_code(c.key)
    if code == nil then
      return
    end
    local key = "code:" .. tostring(code)
    hl.dispatch(hl.dsp.send_key_state({ mods = c.mods, key = key, state = "down", window = w }))
    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = c.mods, key = key, state = "up", window = w }))
    end, { timeout = 50, type = "oneshot" })
  end

  local function step(i)
    local c = list[i]
    if c == nil then
      return
    end
    send(c)
    if list[i + 1] ~= nil then
      -- The next chord waits for this one's release: in the GUI pair the
      -- selection has to exist before the delete lands.
      hl.timer(function()
        step(i + 1)
      end, { timeout = 80, type = "oneshot" })
    end
  end
  step(1)
end

local function text_chord(id)
  return function()
    local w = hl.get_active_window()
    if w == nil then
      return { pass_event = true }
    end
    local chords = textkeys.chords(id, textkeys.is_terminal(w.tags))
    if chords == nil or #chords == 0 then
      -- Nothing to send in this context (readline has no selection to
      -- extend), so the key stays the app's rather than being swallowed.
      return { pass_event = true }
    end
    send_chords(chords, w)
    return { pass_event = false }
  end
end

for _, e in ipairs(textkeys.plan()) do
  -- Drop whatever held the key: Omarchy's default (Cmd+Backspace, Cmd+Home) or
  -- a Super-as-Ctrl bind left over from the previous config evaluation.
  hl.unbind(e.keys)
  pcall(o.bind, e.keys, e.label, text_chord(e.id))
end

-- Cmd+Backspace is "delete to the start of the line" on macOS, so Omarchy's
-- window transparency keeps a key on the one Backspace chord the pack does not
-- take (Cmd+Shift+Backspace is window gaps, Cmd+Ctrl+Backspace square aspect).
hl.unbind("SUPER + ALT + BACKSPACE")
o.bind("SUPER + ALT + BACKSPACE", "Toggle window transparency", "omarchy-hyprland-window-transparency-toggle")

-- --- macOS capture keys -----------------------------------------------------
-- Cmd+Shift+3/4 and Ctrl+Shift+Cmd+3/4 are the screenshot keys on a Mac, and
-- Omarchy's capture command has the modes to match: `fullscreen` is the whole
-- monitor and `region` is the drag, while the second argument picks what happens
-- to the shot -- unset is their default (the file, the clipboard and the
-- notification with its "edit with Tensaku" action), `copy` is the clipboard on
-- its own. The plain keys take the default and the Control ones only copy, which
-- is the macOS split: on a Mac Cmd+Shift+3 does not overwrite the clipboard
-- either, and only the plain keys announce themselves.
--
-- Cmd+Shift+4 is a plain region and not Omarchy's `smart`, which also offers the
-- window under the cursor: `smart` feeds slurp a candidate list built from
-- `hyprctl clients -j` with no z-order in it, and slurp highlights the smallest
-- rectangle containing the pointer -- so hovering highlights a window that is
-- actually covered, and a click or a tiny drag snaps to the first rectangle in
-- the list, which is the monitor. A drag of your own has none of that.
--
-- Cmd+Shift+5 is the recording key and Cmd+Shift+6 the Touch Bar shot on a Mac
-- -- which does not exist here, so that slot carries the OCR region read.
--
-- Cmd+Shift+3..6 are also Omarchy's "move window to workspace 3..6", written by
-- keycode (code:12 is the 3 key). Both spellings are dropped: a bind matches on
-- its own spelling, so the keycode one left behind would move the window as
-- well. With workspaces on F1..F10 the moves live on Shift+F1..F10, so nothing
-- is lost; on Omarchy's own digits, Cmd+Shift+3..6 are the pack's now.
local CAPTURE = {
  {
    keys = "SUPER + SHIFT + 3", code = "SUPER + SHIFT + code:12",
    label = "Screenshot the screen", cmd = "omarchy-capture-screenshot fullscreen",
  },
  {
    keys = "SUPER + CTRL + SHIFT + 3", code = "SUPER + CTRL + SHIFT + code:12",
    label = "Screenshot the screen to clipboard", cmd = "omarchy-capture-screenshot fullscreen copy",
  },
  {
    keys = "SUPER + SHIFT + 4", code = "SUPER + SHIFT + code:13",
    label = "Screenshot a region", cmd = "omarchy-capture-screenshot region",
  },
  {
    keys = "SUPER + CTRL + SHIFT + 4", code = "SUPER + CTRL + SHIFT + code:13",
    label = "Screenshot a region to clipboard", cmd = "omarchy-capture-screenshot region copy",
  },
  {
    keys = "SUPER + SHIFT + 5", code = "SUPER + SHIFT + code:14",
    -- Omarchy's own recording key: stop a running recording, otherwise offer
    -- the options -- which is what Cmd+Shift+5 opens on a Mac too.
    label = "Screen recording",
    cmd = "omarchy-capture-screenrecording --stop-recording || omarchy-menu toggle trigger.capture.screenrecord",
  },
  {
    keys = "SUPER + SHIFT + 6", code = "SUPER + SHIFT + code:15",
    label = "Capture text from a region", cmd = "omarchy-capture-text",
  },
}

for _, e in ipairs(CAPTURE) do
  hl.unbind(e.keys)
  if e.code ~= nil then
    hl.unbind(e.code)
  end
  pcall(o.bind, e.keys, e.label, e.cmd)
end

local function ws_id(w)
  local ws = w and w.workspace
  if ws == nil then
    return nil
  end
  local ok, id = pcall(function()
    return ws.id or ws.name
  end)
  if ok and id ~= nil then
    return id
  end
  if type(ws) == "number" or type(ws) == "string" then
    return ws
  end
  return nil
end

-- The panel's settings, options and per-app chrome in one file:
-- ~/.config/hypr/x-mode.json -- user config, next to the pack's own directory,
-- so it survives an uninstall and comes back on the next install. Kept out of
-- ~/.config/hypr/x-mode/ (the pack owns that directory and uninstall removes
-- it) and out of the state dir (also removed).
-- { "options": { "nativeScroll": ..., ... },
--   "apps": { "class": { "chrome": true, "alwaysTabbar": false,
--                      "ctrlW": false, "ctrlAsSuper": false, "ctrlCShift": false,
--                      "ctrlClick": false, "ctrlAsSuperKeys": [] } } }
-- chrome=false → no titlebar/tabbar/grouping. alwaysTabbar → tab strip even
-- when the window is not grouped. ctrlW → Super+W closes the app's tab (Ctrl+W);
-- ctrlAsSuper → unbound Super+key reaches the app as Ctrl+key; ctrlAsSuperKeys →
-- occupied Super keys stolen for this app (same wrap as Super+W); ctrlClick →
-- Super+click is Ctrl+click; ctrlCShift →
-- Ctrl+C reaches it as Ctrl+Shift+C, so the app's own binding can make it the
-- interrupt while Super+C stays the copy. Missing entries mean chrome on, flags
-- off.
--
-- The bar panel is the only writer. The runtime on/off flag stays a separate
-- plain file (`enabled`): the plugin reads that one with stdio, before any Lua
-- runs, and a broken settings file must not decide whether x-mode loads.
local SETTINGS_PATH = (os.getenv("HOME") or "") .. "/.config/hypr/x-mode.json"
-- Older installs kept the settings in the state dir; read one those once and
-- write the new file. options.json/apps.json predate even that.
local LEGACY_SETTINGS_PATH = X_MODE_STATE .. "/settings.json"
local LEGACY_OPTIONS_PATH = X_MODE_STATE .. "/options.json"
local LEGACY_APPS_PATH = X_MODE_STATE .. "/apps.json"

local function slurp(path)
  local file = io.open(path, "r")
  if file == nil then
    return nil
  end
  local raw = file:read("*a") or ""
  file:close()
  if raw:match("^%s*$") then
    return nil
  end
  return raw
end

-- The whole settings file. Older installs kept it in the state dir, and before
-- that as options.json/apps.json: fold whichever of those exists into the new
-- file once. A present-but-empty file is returned as it is, not rebuilt: the
-- panel writes by truncating first, so rebuilding here would turn a write that
-- is still in flight into lost settings.
local function read_settings()
  local file = io.open(SETTINGS_PATH, "r")
  if file ~= nil then
    local raw = file:read("*a") or ""
    file:close()
    return raw
  end
  local raw = slurp(LEGACY_SETTINGS_PATH) or settings.merge(slurp(LEGACY_OPTIONS_PATH), slurp(LEGACY_APPS_PATH))
  local out = io.open(SETTINGS_PATH, "w")
  if out then
    out:write(raw, "\n")
    out:close()
  end
  return raw
end

-- The apps object on its own, out of the settings file.
local function apps_raw()
  return settings.apps_section(read_settings())
end

local function load_apps()
  return settings.parse_apps(apps_raw())
end

local function chrome_on(cls)
  local e = apps_cfg[cls]
  if e == nil then
    return true
  end
  return e.chrome ~= false
end

apps_cfg = load_apps()
apps_off = {} -- skip_group / clamp still use a set of chrome-off classes
local function sync_apps_off()
  apps_off = {}
  for cls, e in pairs(apps_cfg) do
    if e.chrome == false then
      apps_off[cls] = true
    end
  end
end
sync_apps_off()

local function sync_app_flags()
  ctrl_w_apps = settings.ctrl_w_set(apps_cfg)
  ctrl_as_super = settings.flag_set(apps_cfg, "ctrl_as_super")
  ctrl_c_shift_apps = settings.flag_set(apps_cfg, "ctrl_c_shift")
  ctrl_click_apps = settings.flag_set(apps_cfg, "ctrl_click")
  steal_keys = {}
  for cls, e in pairs(apps_cfg) do
    if e.ctrl_as_super_keys and next(e.ctrl_as_super_keys) then
      steal_keys[cls] = e.ctrl_as_super_keys
    end
  end
end
sync_app_flags()

-- Ctrl+C for an app that hosts a terminal. Ctrl+C is the shell's interrupt and
-- the app cannot tell it apart from the copy chord a desktop sends (Super+C
-- arrives through Omarchy's universal clipboard as Ctrl+C). For an app with this
-- flag the physical Ctrl+C goes in shifted instead, so the app's own
-- Ctrl+Shift+C binding decides what it means -- in Zed that is the interrupt --
-- while Super+C keeps arriving as Ctrl+C and copies.
--
-- Only the physical key is caught: a chord the desktop sends goes straight to
-- the client and never through the bind table, so this cannot loop.
local function apply_ctrl_c_shift()
  if #ctrl_c_binds > 0 or next(ctrl_c_shift_apps) == nil then
    return
  end
  local ok, kb = pcall(hl.bind, "CTRL + C", function()
    local w = hl.get_active_window()
    if w == nil or not ctrl_c_shift_apps[window_class(w)] then
      return { pass_event = true }
    end
    send_chord("CTRL SHIFT", "C", w)
  end, { description = "Shift Ctrl+C for the app" })
  if ok and kb then
    ctrl_c_binds[#ctrl_c_binds + 1] = kb
  end
end

local nobar_applied = {}
local always_applied = {}

local function set_rule(name, cls, effect, on)
  -- The stored key is lowercased, but Hyprland matches a rule's class as a
  -- case-sensitive RE2 full match, so the pattern carries the case-insensitive
  -- flag (and escapes the class's regex metacharacters). Without it an app with
  -- an uppercase letter in its class -- Thunderbird's org.mozilla.Thunderbird --
  -- kept its titlebar no matter what the panel said.
  pcall(function()
    hl.window_rule({
      name = name .. cls,
      enabled = on and true or false,
      match = { class = settings.rule_pattern(cls) },
      [effect] = true,
    })
  end)
end

local function apply_apps()
  apps_cfg = load_apps()
  sync_apps_off()
  sync_app_flags()
  apply_ctrl_c_shift()
  local wanted_nobar, wanted_always = settings.desired_rules(apps_cfg)
  local add_nobar, drop_nobar = settings.rule_diff(wanted_nobar, nobar_applied)
  local add_always, drop_always = settings.rule_diff(wanted_always, always_applied)
  for _, cls in ipairs(add_nobar) do
    set_rule("x-mode-nobar-", cls, "hyprbars:no_bar", true)
  end
  for _, cls in ipairs(drop_nobar) do
    set_rule("x-mode-nobar-", cls, "hyprbars:no_bar", false)
  end
  for _, cls in ipairs(add_always) do
    set_rule("x-mode-always-tabbar-", cls, "hyprbars:always_tabbar", true)
  end
  for _, cls in ipairs(drop_always) do
    set_rule("x-mode-always-tabbar-", cls, "hyprbars:always_tabbar", false)
  end
  nobar_applied = wanted_nobar
  always_applied = wanted_always
end

local function ungroup_where(pred)
  for _, w in ipairs(as_list(hl.get_windows())) do
    if pred(window_class(w)) and w.group ~= nil then
      pcall(function()
        hl.dispatch(hl.dsp.window.move({ out_of_group = true, window = w }))
      end)
    end
  end
end

local function ungroup_chrome_off()
  ungroup_where(function(cls)
    return apps_off[cls]
  end)
end

-- A nest that was already tabbed when this file loaded (the usual case on
-- install) does not get a window.open, so skip_group never sees it. Pull it
-- out here, same moment as a chrome-off window.
local function ungroup_never()
  ungroup_where(function(cls)
    return group.never_group(cls)
  end)
end

local function regroup_chrome_on()
  for _, w in ipairs(as_list(hl.get_windows())) do
    if chrome_on(window_class(w)) then
      join_same_app(w)
    end
  end
end

apply_apps()
hl.timer(function()
  ungroup_chrome_off()
  ungroup_never()
end, { timeout = 250, type = "oneshot" })

x_mode = x_mode or {}
function x_mode.refresh_apps_off()
  apply_apps()
  apply_super_ctrl()
  ungroup_chrome_off()
  ungroup_never()
  regroup_chrome_on()
end

-- Desktop options (native scroll, Ctrl+1..9 tab switching, no gaps, workspaces
-- on F1..F10), read from settings.json. Ctrl+1..9 switches group tabs when the
-- focused app has chrome/titlebar on; otherwise the key is passed through to the
-- app. Off by default, so those shortcuts reach the app. No gaps zeroes the
-- outer and inner gaps and keeps a hairline border. Workspaces on F1..F10 is
-- what frees Super+1..0 (see apply_workspace_keys); off is Omarchy's layout,
-- Cmd+1..0 on the workspaces.
local native_scroll = false
local ctrl_tab_switch = false
local ctrl_tab_binds = {}
local no_gaps = false
-- Workspace switching on Super+F1..F10 instead of Super+1..0.
local workspaces_fkeys = false
local workspace_key_binds = {}

local function load_options()
  local o = settings.parse_options(read_settings())
  native_scroll = o.native_scroll
  ctrl_tab_switch = o.ctrl_tab_switch
  no_gaps = o.no_gaps
  workspaces_fkeys = o.workspaces_fkeys
end

-- gaps_* only schedule a layout refresh, and `hyprctl eval` returns before
-- that deferred refresh runs, so the windows would keep their old boxes and
-- the border change would not repaint. Run the scheduled refresh now: it
-- recalculates every monitor's active workspace from the new gaps.
local function flush_layout()
  pcall(function()
    hl.exec_scheduled_prop_refresh_immediately()
  end)
end

-- A window can be sitting in one of two layouts: the one the live gaps make,
-- or the one "No gaps" leaves behind. Only the second is known from the option:
-- a reload starts Lua over, and the config above this file has already put the
-- normal gaps back while the windows are still where the previous option left
-- them. So each window is matched twice, once against the live gaps and, for
-- whatever is left, against the no-gap layout. Only a window in the *other*
-- layout is returned; one already in the target layout is left alone, as is a
-- window that fills no zone at all (moved by hand).
--
-- The dock inset follows gaps_out, so the no-gap pass has to push the inset
-- that layout used as well; the plugin's own gap override only covers the gap
-- and border, and without this a right-edge window misses by half a gap.
local function zoned_hits(target)
  local hits = {}
  local p = bars()
  if p == nil or p.snap == nil or p.zone == nil then
    return hits
  end

  local rest = {}
  for _, w in ipairs(as_list(hl.get_windows())) do
    if w.floating and not w.pinned and not w.hidden then
      local ok, kind = pcall(p.zone, w)
      if ok and type(kind) == "string" and kind ~= "" then
        if target ~= "live" then
          hits[#hits + 1] = { window = w, kind = kind }
        end
      else
        rest[#rest + 1] = w
      end
    end
  end

  if #rest > 0 then
    -- No gaps means gaps_out is 0, so the inset is the dock card alone.
    hl.config({ plugin = { hyprbars = { x_mode_dock_inset = dock_card } } })
    for _, w in ipairs(rest) do
      local ok, kind = pcall(p.zone, w, { gap = 0, border = 1 })
      if ok and type(kind) == "string" and kind ~= "" and target ~= "no-gap" then
        hits[#hits + 1] = { window = w, kind = kind }
      end
    end
  end

  return hits
end

local function apply_no_gaps()
  -- Name the zones while the windows are still in the layout they were snapped
  -- in: change the gaps first and there is nothing left to compare against.
  local hits = zoned_hits(no_gaps and "no-gap" or "live")

  if no_gaps then
    pcall(function()
      hl.config({
        general = {
          -- No gaps between windows; keep a hairline border so windows stay
          -- separable.
          gaps_in = 0,
          gaps_out = 0,
          border_size = 1,
        },
      })
    end)
  end
  -- Snap, float_gaps and the dock inset all read the gap live. This also puts
  -- the dock inset back after the no-gap pass above moved it.
  apply_gap_geometry()
  flush_layout()

  local p = bars()
  if p == nil or p.snap == nil then
    return
  end
  for _, hit in ipairs(hits) do
    pcall(function()
      p.snap({ kind = hit.kind, window = hit.window })
    end)
  end
end

-- Put the windows that are still shaped like a zone back on that zone, with the
-- live gaps. A window snapped and then nudged a little (or left a titlebar lower
-- while its client settled) is still that zone -- the plugin's zone match reads a
-- full-height zone by x and size, not by an exact y -- so a load re-applies the
-- zone box instead of leaving it out of line with the gaps around it.
--
-- This is a *load-time* pass on purpose. The same re-apply used to fall out of
-- Snap::clampToWorkArea, which runs from the bar's updateRules, and Hyprland
-- re-evaluates every window's rules whenever *any* window opens: a snapped
-- window dragged a little down flew back into its snap when another window
-- opened, with nothing in sight to explain it. A window moved out of the zone's
-- shape (another x or width) is free and is left alone, as is one being dragged
-- right now.
local function resnap_zoned()
  local p = bars()
  if p == nil or p.snap == nil or p.zone == nil then
    return
  end
  if p.dragging ~= nil then
    local ok, dragging = pcall(p.dragging)
    if ok and dragging then
      return
    end
  end
  for _, w in ipairs(as_list(hl.get_windows())) do
    if w.floating and not w.pinned and not w.hidden then
      local ok, kind = pcall(p.zone, w)
      if ok and type(kind) == "string" and kind ~= "" then
        pcall(function()
          p.snap({ kind = kind, window = w })
        end)
      end
    end
  end
end

local function apply_native_scroll()
  -- Set both the mouse and touchpad keys: some pads are classified as mice.
  pcall(function()
    hl.config({
      input = {
        natural_scroll = native_scroll,
        touchpad = { natural_scroll = native_scroll },
      },
    })
  end)
end

local function focus_group_tab(index)
  local w = hl.get_active_window()
  if w == nil or w.group == nil or not chrome_on(window_class(w)) then
    return { pass_event = true }
  end
  local members = w.group.members
  if index < 1 or index > #members then
    return { pass_event = true }
  end
  -- group.active focuses the tab; the raise is the focus handler's.
  hl.dispatch(hl.dsp.group.active({ index = index, window = w }))
  return { pass_event = false }
end

-- Bind or release Ctrl+1..9. The handles are kept so turning the option off
-- removes exactly these binds (hl.unbind would also drop any the user set on
-- the same keys). A removed bind lets the key fall through to the app.
local function apply_ctrl_tab_switch()
  if ctrl_tab_switch then
    if #ctrl_tab_binds > 0 then
      return
    end
    for i = 1, 9 do
      local ok, kb = pcall(o.bind, "CTRL + code:" .. tostring(i + 9), "Switch to tab " .. i, function()
        return focus_group_tab(i)
      end)
      if ok and kb then
        ctrl_tab_binds[#ctrl_tab_binds + 1] = kb
      end
    end
  else
    for _, kb in ipairs(ctrl_tab_binds) do
      pcall(function()
        kb:unbind()
      end)
    end
    ctrl_tab_binds = {}
  end
end

-- "Super works as Ctrl": for an app with the flag, every Super+key the
-- desktop does not already bind is re-sent to the app as Ctrl+key. Hyprland
-- dispatches every matching bind, so the bind table has to be read rather than
-- guessed, and it is not in the Lua API: hyprctl writes it out and a timer picks
-- it up. Reading it inline would block the parse on the compositor's own IPC.
-- The text form is read, not -j: a keycode bind (Omarchy's workspaces) has no
-- name there for the JSON to print.
local super_ctrl_binds = {}
-- Bumped on every replan so a read that lands late cannot bind a stale table
-- over a newer one.
local super_ctrl_gen = 0

local function drop_super_ctrl()
  for _, kb in ipairs(super_ctrl_binds) do
    pcall(function()
      kb:unbind()
    end)
  end
  super_ctrl_binds = {}
end

-- Hand the key to the app as Ctrl+key and consume it; any other app gets the
-- key exactly as before.
local function super_ctrl_key(key, shift)
  local w = hl.get_active_window()
  if w == nil or not ctrl_as_super[window_class(w)] then
    return { pass_event = true }
  end
  send_ctrl(key, shift, w)
end

-- Pack-owned Super binds wrapped at the source (like Super+W). Everything
-- else that is stealable is an Omarchy command we unbind and replay: hyprctl
-- prints those as __lua, so the command is recovered from Omarchy's bind files.
local STEAL_OWN = { Q = true, TAB = true, F = true }
-- [id] = { keys, originals, handle } for wraps we installed on Omarchy keys.
local steal_wraps = {}
local omarchy_exec = nil

local function ensure_omarchy_exec()
  if omarchy_exec ~= nil then
    return
  end
  omarchy_exec = {}
  local p = io.popen("ls /usr/share/omarchy/default/hypr/bindings/*.lua 2>/dev/null")
  if p == nil then
    return
  end
  local listing = p:read("*a") or ""
  p:close()
  for path in listing:gmatch("[^\n]+") do
    local text = slurp(path)
    if text ~= nil then
      for id, cmd in pairs(supermap.parse_omarchy_binds(text)) do
        omarchy_exec[id] = cmd
      end
    end
  end
end

local function steal_bind_string(key, shift)
  if shift then
    return "SUPER + SHIFT + " .. key
  end
  return "SUPER + " .. key
end

local function replay_orig(orig)
  local d = orig.dispatcher or ""
  if d == "exec" or d == "exec_cmd" then
    hl.exec_cmd(orig.arg or "")
    return
  end
  if d ~= "" and d ~= "__lua" then
    hl.exec_cmd("hyprctl dispatch " .. d .. " " .. (orig.arg or ""))
  end
end

local function restore_orig(keys, orig)
  local d = orig.dispatcher or ""
  if d == "exec" or d == "exec_cmd" then
    pcall(o.bind, keys, orig.description, orig.arg)
    return
  end
  if d ~= "" and d ~= "__lua" then
    pcall(function()
      hl.bind(keys, function()
        replay_orig(orig)
      end, { description = orig.description })
    end)
  end
end

local function drop_steal_wrap(id)
  local wrap = steal_wraps[id]
  if wrap == nil then
    return
  end
  pcall(function()
    wrap.handle:unbind()
  end)
  for _, orig in ipairs(wrap.originals) do
    restore_orig(wrap.keys, orig)
  end
  steal_wraps[id] = nil
end

-- Ids that need an Omarchy-key wrap: stolen somewhere, and not a pack bind
-- already wrapped at the source (Q, Tab, W, F).
local function needed_steals()
  local set = {}
  for _, ids in pairs(steal_keys) do
    for id in pairs(ids) do
      if id ~= "Q" and id ~= "TAB" and id ~= "SHIFT+TAB" and id ~= "W" and id ~= "F" then
        set[id] = true
      end
    end
  end
  return set
end

local function apply_steal_wraps(raw)
  local needed = needed_steals()
  for id in pairs(steal_wraps) do
    if not needed[id] then
      drop_steal_wrap(id)
    end
  end
  if next(needed) == nil then
    return
  end
  local by_id = {}
  for _, e in ipairs(supermap.stealable(raw, STEAL_OWN, omarchy_exec)) do
    by_id[e.id] = e
  end
  for id in pairs(needed) do
    if steal_wraps[id] == nil then
      local e = by_id[id]
      if e ~= nil and not e.wrapped then
        local keys = steal_bind_string(e.key, e.shift)
        local originals = e.binds
        if omarchy_exec[id] then
          originals = { { dispatcher = "exec", arg = omarchy_exec[id], description = e.description } }
        end
        hl.unbind(keys)
        local code = supermap.key_code(e.key)
        if code ~= nil then
          local ck = e.shift and ("SUPER + SHIFT + code:" .. tostring(code)) or ("SUPER + code:" .. tostring(code))
          hl.unbind(ck)
        end
        local key, shift = e.key, e.shift
        local ok, kb = pcall(hl.bind, keys, function()
          local w = hl.get_active_window()
          if w ~= nil and key_stolen(window_class(w), key, shift) then
            send_ctrl(key, shift, w)
            return
          end
          for _, orig in ipairs(originals) do
            replay_orig(orig)
          end
        end, { description = supermap.steal_desc(id, e.description) })
        if ok and kb then
          steal_wraps[id] = { keys = keys, originals = originals, handle = kb }
        end
      end
    end
  end
end

local function write_occupied(raw)
  local file = io.open(X_MODE_STATE .. "/occupied.json", "w")
  if file == nil then
    return
  end
  file:write(supermap.occupied_json(supermap.stealable(raw, STEAL_OWN, omarchy_exec)), "\n")
  file:close()
end

local function bind_super_ctrl(raw, gen)
  if gen ~= super_ctrl_gen then
    return
  end
  ensure_omarchy_exec()
  write_occupied(raw)
  apply_steal_wraps(raw)
  if next(ctrl_as_super) == nil then
    return
  end
  for _, b in ipairs(supermap.plan(raw)) do
    local keys = b.shift and ("SUPER + SHIFT + " .. b.key) or ("SUPER + " .. b.key)
    local ok, kb = pcall(hl.bind, keys, function()
      return super_ctrl_key(b.key, b.shift)
    end, { description = supermap.PREFIX .. (b.shift and " SHIFT" or "") .. " " .. b.key })
    if ok and kb then
      super_ctrl_binds[#super_ctrl_binds + 1] = kb
    end
  end
end

-- Poll for the file: the exec that writes it has not landed when the timer is
-- set, and a missing file must not read as "nothing is bound".
local function super_ctrl_read(path, tries, gen)
  hl.timer(function()
    if gen ~= super_ctrl_gen then
      return
    end
    local raw = slurp(path)
    if raw ~= nil then
      bind_super_ctrl(raw, gen)
      return
    end
    if tries > 0 then
      super_ctrl_read(path, tries - 1, gen)
    end
  end, { timeout = 200, type = "oneshot" })
end

apply_super_ctrl = function()
  drop_super_ctrl()
  super_ctrl_gen = super_ctrl_gen + 1
  -- Always re-read: the occupied list feeds the panel even when no app has
  -- Super-as-Ctrl on, and steal wraps can exist without that flag.
  local path = X_MODE_STATE .. "/binds.txt"
  os.remove(path)
  hl.exec_cmd("sh -c 'hyprctl binds > \"" .. path .. "\" 2>/dev/null'")
  super_ctrl_read(path, 10, super_ctrl_gen)
end

apply_super_ctrl()

-- Workspace switching on F1..F10 instead of Super+1..0. Off is Omarchy's layout:
-- the pack does nothing. On, the digit binds (Omarchy writes them as
-- `SUPER + code:10..19`) are released so "Super works as Ctrl" can take the
-- digits -- Ctrl+1..0 switches the app's tabs -- and the F keys switch the
-- desktop's workspaces. Turning it back off goes through a reload, which
-- re-creates the Omarchy binds, so only the pack's own binds have to go.
local function drop_workspace_keys()
  for _, kb in ipairs(workspace_key_binds) do
    pcall(function()
      kb:unbind()
    end)
  end
  workspace_key_binds = {}
end

local function add_workspace_key(keys, description, dispatcher)
  local ok, kb = pcall(hl.bind, keys, dispatcher, { description = description })
  if ok and kb then
    workspace_key_binds[#workspace_key_binds + 1] = kb
  end
end

local function apply_workspace_keys()
  drop_workspace_keys()
  if not workspaces_fkeys then
    return
  end
  for i = 1, 10 do
    local code = tostring(i + 9)
    hl.unbind("SUPER + code:" .. code)
    hl.unbind("SUPER + SHIFT + code:" .. code)
    hl.unbind("SUPER + SHIFT + ALT + code:" .. code)
    local fkey = "F" .. tostring(i)
    local ws = tostring(i)
    add_workspace_key("SUPER + " .. fkey, "Switch to workspace " .. ws, function()
      hl.dispatch(hl.dsp.focus({ workspace = ws }))
    end)
    add_workspace_key("SUPER + SHIFT + " .. fkey, "Move window to workspace " .. ws, function()
      hl.dispatch(hl.dsp.window.move({ workspace = ws }))
    end)
    add_workspace_key("SUPER + SHIFT + ALT + " .. fkey, "Move window silently to workspace " .. ws, function()
      hl.dispatch(hl.dsp.window.move({ workspace = ws, follow = false }))
    end)
  end
end

function x_mode.refresh_options()
  load_options()
  apply_native_scroll()
  apply_ctrl_tab_switch()
  apply_no_gaps()
  apply_workspace_keys()
end

load_options()
apply_native_scroll()
apply_ctrl_tab_switch()
apply_no_gaps()
apply_workspace_keys()

local function skip_group(w)
  if w == nil or w.pinned or w.hidden then
    return true
  end
  local class = window_class(w)
  if apps_off[class] then
    return true
  end
  -- Nested compositor toplevels share one class, so same-app grouping would
  -- put every nest in one tab. The titlebar stays. hyprbars.groupable refuses
  -- the same classes; this also covers the size fallback below, which runs
  -- when the plugin is not loaded yet.
  if group.never_group(class) then
    return true
  end
  if class == "" or class:find("portal", 1, true) or class:find("polkit", 1, true) or class:find("titlebar", 1, true) then
    return true
  end
  -- Hyprland's own popup classification (override-redirect, modal, X11
  -- MENU/DROPDOWN/COMBO/TOOLTIP, transients, xdg children). Size is not a
  -- signal: a small document is still a document.
  local p = bars()
  if p and p.groupable then
    if not p.groupable(w) then
      return true
    end
  else
    -- Plugin not loaded yet: keep the old size floor as a last resort.
    local ww, wh = vec(w.size)
    if ww > 0 and wh > 0 and (ww < GROUP_MIN_W or wh < GROUP_MIN_H) then
      return true
    end
  end
  return false
end

local function addr_sel(w)
  local a = tostring(w.address)
  if a:sub(1, 8) == "address:" then
    return a
  end
  return "address:" .. a
end

local function refresh_window(w)
  if w == nil or w.address == nil then
    return w
  end
  return hl.get_window(addr_sel(w)) or w
end

local function hide_key(w)
  if w == nil or w.address == nil then
    return nil
  end
  return tostring(w.address)
end

-- After a tab is added the chrome grows upward (hyprbars draws above the
-- window box). Keep the visual top put by placing content at
-- old_y + chrome growth, and shrink the height so the bottom edge stays put.
-- Targets are absolute from the pre-join geometry so repeated calls are
-- idempotent (a plain delta nudge + keep_pos left maximized windows under
-- the top bar; a full clamp_window pinned them to the top).
-- Must live below refresh_window: a local used before its declaration is nil.
local function absorb_chrome_growth(w, old_x, old_y, old_w, old_h, old_chrome)
  w = refresh_window(w)
  if w == nil or drag_owns(w) then
    return
  end
  if not (w.floating and w.mapped) then
    return
  end
  local mon = w.monitor
  if mon == nil then
    return
  end
  local _, uy, _, uh = usable(mon)
  if uy == nil then
    return
  end
  local x, y = vec(w.at)
  local ww, wh = vec(w.size)
  local new_chrome = chrome_h(w)
  local grow = math.max(new_chrome - (old_chrome or 0), 0)
  local edge = GAP_OUT() + BORDER()
  local ny = old_y + grow
  local min_top = uy + edge + new_chrome
  if ny < min_top then
    ny = min_top
  end
  local nh = math.max(1, old_h - grow)
  local max_h = uh - edge - edge - new_chrome
  if nh > max_h then
    nh = max_h
  end
  if math.abs(wh - nh) >= 1 or math.abs(ww - old_w) >= 1 then
    hl.dispatch(hl.dsp.window.resize({ x = old_w, y = nh, relative = false, window = w }))
    -- Resize is centered: re-assert the preserved visual top afterwards.
    w = refresh_window(w) or w
    x, y = vec(w.at)
  end
  if math.abs(x - old_x) >= 1 or math.abs(y - ny) >= 1 then
    hl.dispatch(hl.dsp.window.move({ x = old_x, y = ny, relative = false, window = w }))
  end
end

local function already_together(a, b)
  a = refresh_window(a)
  b = refresh_window(b)
  if a == nil or b == nil or a.group == nil or b.group == nil then
    return false
  end
  return a.group == b.group
end

find_peer = function(w)
  w = refresh_window(w)
  if skip_group(w) then
    return nil
  end
  local class = window_class(w)
  local wid = ws_id(w)
  local windows = as_list(hl.get_windows())
  if type(windows) ~= "table" then
    return nil
  end
  local fallback = nil
  for _, other in ipairs(windows) do
    if other.address ~= w.address and window_class(other) == class and ws_id(other) == wid and not skip_group(other) then
      local peer = refresh_window(other)
      if peer ~= nil and peer.group ~= nil then
        -- Prefer an existing group so a new window joins it instead of
        -- creating yet another group of the same app.
        local current = peer.group.current
        return refresh_window(current) or peer
      end
      if fallback == nil then
        fallback = peer
      end
    end
  end
  return fallback
end

join_same_app = function(w)
  w = refresh_window(w)
  if skip_group(w) then
    return
  end
  local peer = find_peer(w)
  if peer == nil then
    return
  end
  if already_together(w, peer) then
    return
  end
  -- Grouping moves the group and grows the chrome. If either window is the one
  -- being dragged, wait until the drag (and its snap) has finished, otherwise
  -- the new tab steals the snap or hides the preview.
  if dragging() and (drag_owns(w) or drag_owns(peer)) then
    local key = hide_key(w)
    if key ~= nil then
      pending_join[key] = true
    end
    return
  end
  local px, py = vec(peer.at)
  local pw, ph = vec(peer.size)
  local old_chrome = chrome_h(peer)
  pcall(function()
    if peer.group == nil then
      hl.dispatch(hl.dsp.group.toggle({ window = peer }))
      peer = refresh_window(peer)
    end
    if peer ~= nil and peer.group ~= nil then
      peer.group:add(w)
    end
  end)
  -- The new tab is the group's current window now (CGroup::add sets m_current to
  -- it) and Hyprland focuses it in onMap; focusing routes through window.active,
  -- which raises the group.
  -- Adding a tab must not yank the group to the new window's position.
  -- absorb_chrome_growth places the group from the peer's pre-join box so
  -- the visual titlebar stays put when the tabbar appears.
  absorb_chrome_growth(peer, px, py, pw, ph, old_chrome)
  hl.timer(function()
    absorb_chrome_growth(peer, px, py, pw, ph, old_chrome)
  end, { timeout = 60, type = "oneshot" })
  hl.timer(function()
    absorb_chrome_growth(peer, px, py, pw, ph, old_chrome)
  end, { timeout = 120, type = "oneshot" })
end

-- New same-app windows are placed by Hyprland in the middle of the screen and
-- only get grouped into the existing window at window.open (openLate), so they
-- can be rendered at that middle position for a frame first ("flash"). Hide the
-- window as early as possible and reveal it once it has joined the group, so it
-- appears exactly where the existing window is.
local hidden_for_join = {}

local function reveal_if_hidden(w)
  local key = hide_key(w)
  if key == nil or not hidden_for_join[key] then
    return
  end
  -- Still waiting on an in-progress titlebar drag/snap.
  if pending_join[key] then
    return
  end
  hidden_for_join[key] = nil
  pcall(function()
    hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity", value = "1", window = w }))
  end)
end

hl.on("window.open_early", function(w)
  if w == nil then
    return
  end
  local key = hide_key(w)
  if key == nil then
    return
  end
  if find_peer(w) ~= nil then
    hidden_for_join[key] = true
    pcall(function()
      hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity", value = "0", window = w }))
    end)
  end
end)

flush_pending_joins = function()
  local addrs = {}
  for addr, _ in pairs(pending_join) do
    table.insert(addrs, addr)
  end
  pending_join = {}
  for _, addr in ipairs(addrs) do
    local w = window_by_addr(addr)
    if w ~= nil then
      pcall(join_same_app, w)
      reveal_if_hidden(w)
    else
      hidden_for_join[tostring(addr)] = nil
    end
  end
end

-- A window already in Hyprland's maximized mode (open across a reload, or a
-- dispatch) is just as stuck as a client request the rule above rejects.
-- Super+Alt+F is this same snap: drop the mode, then place the floating box,
-- which can be dragged. Mode 2 is real fullscreen and stays.
local function release_hypr_maximize(w)
  if w == nil then
    return
  end
  local internal = w.fullscreen or 0
  local client = w.fullscreen_client or 0
  if internal == 2 or client == 2 then
    return
  end
  if internal ~= 1 and client ~= 1 then
    return
  end
  hl.dispatch(hl.dsp.window.fullscreen({ action = "unset", window = w }))
  snap("maximize", w)
end

hl.on("window.fullscreen", function(w)
  release_hypr_maximize(w)
end)

hl.on("window.open", function(w)
  -- Group immediately to avoid a visible "ungrouped" flash, then retry shortly
  -- in case the window wasn't fully ready (class/size) on the first tick.
  -- Join must never leave a hidden window stuck: reveal even if join errors.
  pcall(join_same_app, w)
  reveal_if_hidden(w)
  local function retry_join()
    pcall(join_same_app, w)
    reveal_if_hidden(w)
  end
  hl.timer(retry_join, { timeout = 30, type = "oneshot" })
  -- Some apps map the window before reporting its class/size; give them a
  -- second chance so a slow same-app window does not stay ungrouped.
  hl.timer(retry_join, { timeout = 200, type = "oneshot" })
  -- Safety net: never keep a same-app window invisible if join/drag state
  -- got stuck after open_early hid it.
  hl.timer(function()
    local key = hide_key(w)
    if key ~= nil and hidden_for_join[key] then
      pending_join[key] = nil
      reveal_if_hidden(w)
    end
  end, { timeout = 500, type = "oneshot" })
end)

hl.on("window.close", function(w)
  local key = hide_key(w)
  if key == nil then
    return
  end
  pending_join[key] = nil
  hidden_for_join[key] = nil
end)

-- Hyprland gives a removed monitor's workspaces to the one that is left and
-- moves each floating window there by the monitor offset only. A window that
-- was snapped on the monitor to the left keeps that snap shifted by whole
-- screen widths, and one on the right of a wider screen keeps coordinates
-- past the right edge of the narrower one.
--
-- Powering the only monitor off has no backup: monitor.removed runs before
-- the windows have moved. The throw is on monitor.added (the virtual FALLBACK
-- output, then the real one returning) and on a later arrange that translates
-- floats again. Fit now, and once more after that arrange. The plugin pages a
-- window that is a whole screen away back onto the same half, configures the
-- client, and does not raise, so a click brings it to the front. Windows
-- already inside stay put.
local function refit_floats()
  local p = bars()
  if p == nil then
    return
  end
  if p.fit_all ~= nil then
    pcall(p.fit_all)
    return
  end
  if p.fit == nil then
    return
  end
  for _, w in ipairs(as_list(hl.get_windows())) do
    pcall(function()
      p.fit(w)
    end)
  end
end

local function schedule_refit()
  refit_floats()
  -- Arrange (CMonitor::moveTo) is scheduled after monitor.added/removed, so
  -- the first pass can run against the old origin. Fit again once that lands.
  hl.timer(refit_floats, { timeout = 200, type = "oneshot" })
end

hl.on("monitor.removed", function(_)
  schedule_refit()
end)
hl.on("monitor.added", function(_)
  schedule_refit()
end)
hl.on("monitor.layout_changed", function()
  schedule_refit()
end)

-- hyprbars.drag(active, window): save restore-geometry at press; grouping
-- waits while the drag is in progress, then joins after the snap.
--
-- The plugin is loaded from exec_on_start, so on the very first parse of this
-- config hl.plugin.hyprbars (and its "hyprbars.drag" event) does not exist yet;
-- loading the plugin then triggers a Hyprland reload that re-runs this file, by
-- which point it does. Guard on the plugin namespace and retry until it loads.
--
-- hl.on() reports an unknown event through Hyprland's config-error path: it
-- returns nothing and does *not* raise, so pcall() alone cannot detect the
-- failure. Check the returned subscription instead, otherwise drag_bound latches
-- on a failed registration and the callback never gets bound.
local drag_bound = false
local drag_timer = nil
local function bind_drag()
  if drag_bound or not bars() then
    return
  end
  local ok, sub = pcall(hl.on, "hyprbars.drag", function(active, w)
    if active then
      -- Remember where the window was, so a later restore snaps back to it. The
      -- drag clamps itself in C++ and may hang off an edge; the work-area clamp
      -- skips a window the drag owns, so nothing pulls it back mid-gesture.
      save(w)
    else
      flush_pending_joins()
    end
  end)
  if ok and sub ~= nil then
    drag_bound = true
    if drag_timer then
      drag_timer:set_enabled(false)
    end
  end
end
bind_drag()
drag_timer = hl.timer(bind_drag, { timeout = 250, type = "repeat" })

-- The dock's layer maps after this config (and again on every shell restart),
-- which is the moment its real width becomes known. config.reloaded covers a
-- reload where the layer was already mapped and no open event fires.
hl.on("layer.opened", function(layer)
  if layer ~= nil and layer.namespace == "x-mode-dock" then
    refresh_dock_card()
  end
end)
hl.on("config.reloaded", function()
  refresh_dock_card()
end)
refresh_dock_card()

-- Group every same-app window on a workspace into one group. Runs once after
-- the config loads: after an install/reload re-floats windows, or when several
-- same-app windows were opened while the config was reloading, they can end up
-- spread across separate groups. Pick a grouped window as the leader when there
-- is one, so the group keeps its position.
local function consolidate()
  local windows = as_list(hl.get_windows())
  if type(windows) ~= "table" then
    return
  end
  local by_class = {}
  for _, w in ipairs(windows) do
    if not skip_group(w) then
      local key = window_class(w) .. ":" .. tostring(ws_id(w))
      by_class[key] = by_class[key] or {}
      table.insert(by_class[key], w)
    end
  end
  for _, members in pairs(by_class) do
    if #members > 1 then
      local leader = nil
      for _, w in ipairs(members) do
        if w.group ~= nil then
          leader = w
          break
        end
      end
      leader = leader or members[1]
      ensure_tab_group(leader)
      leader = refresh_window(leader)
      if leader ~= nil and leader.group ~= nil then
        for _, w in ipairs(members) do
          if w.address ~= leader.address then
            local cur = refresh_window(w)
            if cur ~= nil and not already_together(cur, leader) then
              pcall(function()
                leader.group:add(cur)
              end)
            end
          end
        end
      end
    end
  end
end

-- The marker comes from install.sh (a fresh install) or from the off path
-- above (the desktop was just switched back on from the bar panel). Spread
-- the windows that were already open across the left and right halves, one
-- side per app, alternating in a shuffled order so the two sides come out
-- roughly even. Per workspace: each space is shuffled and split on its own,
-- and a window is never moved to another space. The marker is removed on
-- sight, so the second reload and every reload while already on leave windows
-- where the user put them. One window per class, because consolidate() has
-- already folded same-app windows into a single group.
local ARRANGE_MARKER = X_MODE_STATE .. "/arrange"

local function take_arrange_marker()
  local file = io.open(ARRANGE_MARKER, "r")
  if file == nil then
    return false
  end
  file:close()
  os.remove(ARRANGE_MARKER)
  return true
end

function x_mode.arrange_halves()
  local windows = as_list(hl.get_windows())
  if type(windows) ~= "table" then
    return
  end
  local seen = {}
  local by_space = {}
  for _, w in ipairs(windows) do
    w = refresh_window(w) or w
    if w.mapped and not w.hidden and not is_fullscreen(w) and w.monitor ~= nil then
      local cls = window_class(w)
      local wid = tostring(ws_id(w) or "")
      local key = cls .. "@" .. wid
      if cls ~= "" and not seen[key] then
        seen[key] = true
        by_space[wid] = by_space[wid] or {}
        table.insert(by_space[wid], w)
      end
    end
  end
  -- Fisher-Yates per workspace, so each space is split roughly evenly and a
  -- window stays on the space it was on. math.random is seeded from the clock
  -- below; without the shuffle the order is just whatever Hyprland enumerated.
  for _, leaders in pairs(by_space) do
    for i = #leaders, 2, -1 do
      local j = math.random(i)
      leaders[i], leaders[j] = leaders[j], leaders[i]
    end
    for i, w in ipairs(leaders) do
      snap(i % 2 == 1 and "left" or "right", w)
    end
  end
end

-- Hide the switch-over behind a fade. Everything turning X Mode back on does
-- to a window -- the titlebars coming back and the boxes being refitted on the
-- reload, the re-float, the tab grouping, the arrange -- moves it, and a fade
-- that starts at the arrange is already too late for the first of those: that
-- move is seen on screen and then the fade runs on the new positions. So the
-- fade starts here, as soon as the marker is read, and the windows stay
-- invisible while the rest happens. The reveal is one step at the end,
-- deliberately not animated, so the new layout simply appears.
local FADE_STEPS   = 10
local FADE_STEP_MS = 25
local SETTLE_MS    = 120

local function set_window_opacity(windows, value)
  for _, w in ipairs(windows) do
    if w ~= nil then
      pcall(function()
        -- Hyprland draws the focused window from "opacity" and every other one
        -- from "opacity_inactive" (Window.cpp: alpha() vs alphaInactive()), so
        -- both have to be set or only the focused window is seen to change.
        hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity", value = value, window = w }))
        hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity_inactive", value = value, window = w }))
      end)
    end
  end
end

-- The windows an arrange can touch, named when the fade starts so the reveal
-- targets the same set even after consolidate() folds same-app windows into a
-- group.
local function arrange_candidates()
  local out = {}
  for _, w in ipairs(as_list(hl.get_windows())) do
    w = refresh_window(w) or w
    if w.mapped and not w.hidden and not is_fullscreen(w) and w.monitor ~= nil then
      out[#out + 1] = w
    end
  end
  return out
end

-- Float anything still tiled. A 300ms timer does this normally; with an
-- arrange pending it is deferred to inside the fade, so the float happens on
-- invisible windows instead of moving them on screen before the fade.
local function float_tiled()
  for _, w in ipairs(as_list(hl.get_windows())) do
    if w.mapped and not w.floating and not is_fullscreen(w) then
      hl.dispatch(hl.dsp.window.float({ action = "enable", window = w }))
    end
  end
end

-- Fade the windows out and leave them invisible; the timer below reveals them
-- after the arrange. Every step is pcall'd: a window can close mid-fade, and
-- one bad handle must not leave the rest stuck at opacity 0.
local function fade_out(windows)
  if #windows == 0 then
    return
  end
  local step = 0
  local timer
  timer = hl.timer(function()
    step = step + 1
    set_window_opacity(windows, string.format("%.3f", math.max(0, 1 - step / FADE_STEPS)))
    if step >= FADE_STEPS then
      timer:set_enabled(false)
    end
  end, { timeout = FADE_STEP_MS, type = "repeat" })
end

-- The marker is dropped by install.sh before its reload and by the off path
-- when the desktop is switched back on. Arrange once per load: re-float the
-- still-tiled windows, gather same-app windows into tabs, deal them into
-- halves, and reveal once the new boxes have landed. The windows are named now,
-- at the fade, so the reveal targets exactly the ones that were faded.
local arrange_pending = take_arrange_marker()
local arrange_fade = {}
if arrange_pending then
  math.randomseed(os.time())
  arrange_fade = arrange_candidates()
  fade_out(arrange_fade)
end

hl.timer(function()
  if arrange_pending then
    arrange_pending = false
    float_tiled()
    consolidate()
    x_mode.arrange_halves()
    hl.timer(function()
      set_window_opacity(arrange_fade, "1")
      arrange_fade = {}
    end, { timeout = SETTLE_MS, type = "oneshot" })
  else
    consolidate()
  end
  for _, w in ipairs(as_list(hl.get_windows())) do
    release_hypr_maximize(refresh_window(w) or w)
  end
end, { timeout = 600, type = "oneshot" })

pcall(function()
  if hl.plugin and hl.plugin.hyprbars and hl.plugin.hyprbars.x_mode then
    hl.plugin.hyprbars.x_mode(true)
  end
end)

-- Catch-all float rule only applies to windows created after this config
-- loads; re-float anything still tiled (same as install.sh). With an arrange
-- pending the timer above does this after the fade instead, so the float is not
-- seen (this 300ms timer would move the windows on screen before the fade).
if not arrange_pending then
  hl.timer(float_tiled, { timeout = 300, type = "oneshot" })
end

-- A load re-applies the zone box to every window that is still zone-shaped (see
-- resnap_zoned). Not with an arrange pending: that one deals every window into
-- the halves itself.
if not arrange_pending then
  resnap_zoned()
end
