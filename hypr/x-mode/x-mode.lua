-- omarchy-x-mode: the macOS-like desktop layer.
--
-- Loaded from a sentinel block at the end of ~/.config/hypr/hyprland.lua:
--   -- >>> omarchy-x-mode >>>
--   dofile((os.getenv("HOME") or "") .. "/.config/hypr/x-mode/x-mode.lua")
--   -- <<< omarchy-x-mode <<<
--
-- This file holds the pack: the floating desktop, the Mac titlebar/tabbar
-- (patched hyprbars), the key/mouse bindings, and the state that comes from
-- events (groups, focus, the switcher). Everything that puts a *window on a
-- zone* -- snap, restore, the re-apply a load or a moved frame needs, the
-- one-shot arrange -- is layout.lua next to this file, so there is one place to
-- read when a window is not where it should be. Geometry is not in either: the
-- plugin owns it (hyprbars/snap.cpp -- zones, the snap cycle, the work frame,
-- the chrome) and both only ask for it. Pure parsing lives in the same directory
-- so it can be tested on its own (tests/unit). Personal look'n'feel (input, monitors, decoration, native snap,
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
local layout = dofile(X_MODE_DIR .. "layout.lua")
local modes = dofile(X_MODE_DIR .. "modes.lua")

-- Workspace modes. Omarchy keeps one per workspace -- dwindle, scrolling, its own
-- floating -- in $XDG_STATE_HOME/omarchy/workspace-layouts, and replays those
-- files while the config loads, which is before this file. So the pack reads the
-- same files here rather than learning the modes from o.workspace_mode alone:
-- that call only sees what changes afterwards. The pack adds one mode of its own,
-- xmode, and owns everything about it.
local X_MODE_MODES = modes.new()
-- Every window the pack has claimed carries this, so leaving xmode knows which
-- windows to hand back and hyprbars knows whose titlebar to draw.
local XMODE_TAG = "xmode-workspace"
-- Defined at the end of the file, once ws_id exists.
local claim_window

local function workspace_layouts_dir()
  local state_home = os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")
  return state_home .. "/omarchy/workspace-layouts"
end

local function read_saved_modes()
  local listing = io.popen("ls -1 '" .. workspace_layouts_dir() .. "'/*.lua 2>/dev/null")
  if listing == nil then
    return
  end
  for path in listing:lines() do
    local file = io.open(path, "r")
    if file ~= nil then
      modes.load(X_MODE_MODES, modes.parse_saved(file:read("*a")))
      file:close()
    end
  end
  listing:close()
end

read_saved_modes()

-- Whether the modes can live in Omarchy's own files at all. 4.5 defines
-- o.workspace_mode and replays them; 4.0.x has no such function and replays
-- `hl.workspace_rule(...)`, so a file calling `o.workspace_mode` there fails
-- every config load -- a hard error in the desktop, not a warning. Everything
-- about recording a mode hangs off this one table, and none of it is a local of
-- its own: this file is at Lua's 200-local limit for a function.
local mode_sync = { shared = modes.can_persist(os.getenv("OMARCHY_PATH")) }

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

-- The pack's own record of the workspace modes, in the same format Omarchy's
-- files use and read only where hers cannot be replayed: on 4.5 her saved files
-- are already loaded above, and a second record would be a second truth.
function mode_sync.path()
  return X_MODE_STATE .. "/workspace-modes.lua"
end

function mode_sync.persist()
  if mode_sync.shared then
    return
  end
  os.execute("mkdir -p " .. string.format("%q", X_MODE_STATE))
  local file = io.open(mode_sync.path(), "w")
  if file == nil then
    return
  end
  file:write(modes.dump(X_MODE_MODES))
  file:close()
end

if not mode_sync.shared then
  local file = io.open(mode_sync.path(), "r")
  if file ~= nil then
    local text = file:read("*a")
    file:close()
    modes.load_text(X_MODE_MODES, text)
  end
end

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

-- The pack owns the gaps -- the panel's "No gaps" is the switch -- so Omarchy's
-- own gaps toggle is kept off. Its state is a file Omarchy sources on every load,
-- so a desktop that ever pressed its key has gaps_out, gaps_in and the border
-- zeroed for good: no reload brings the values back, and every titlebar sits at
-- gap 0. Removing the file is exactly what that toggle's own "off" does (see
-- omarchy-hyprland-toggle), which is why it is done here instead of by running the
-- script: the script ends with a reload, and a reload cannot start inside a config
-- load. The reload that puts the values back is scheduled instead -- and only when
-- there was a file to remove, so it cannot loop. Runs on both paths: switching
-- x-mode on from the panel reloads, and that load has to do it too.
local function retire_omarchy_gaps_toggle()
  local path = (os.getenv("HOME") or "") .. "/.local/state/omarchy/toggles/hypr/window-no-gaps.lua"
  local file = io.open(path, "r")
  if file == nil then
    return
  end
  file:close()
  os.remove(path)
  hl.timer(function()
    hl.exec_cmd("hyprctl reload >/dev/null")
  end, { timeout = 1200, type = "oneshot" })
end

retire_omarchy_gaps_toggle()

if not x_mode_wanted() then
  -- Remember that the desktop was switched off, so the next time it comes on
  -- (the bar panel writes "on" and reloads) the windows get dealt out again,
  -- the same as a fresh install. Only the off path writes it:
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
  o.exec_on_start("sh -c 'd=\"$HOME/.local/share/hyprbars\"; hyprctl plugin unload \"$d/hyprbars.so\" >/dev/null 2>&1; hyprctl plugin list 2>/dev/null | grep -q hyprbars || hyprctl plugin load \"$d/x-mode-hyprbars.so\"'")
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
    -- Hyprland's default puts a new tab after the current one. Append instead:
    -- a window opened while looking at an earlier tab still lands at the end.
    insert_after_current = false,
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
-- the existing window's position in the same frame, and switching a group tab must
-- not animate borders (it looked like a flicker).
--
-- Off for the whole compositor, not per workspace: turning a leaf back *on* needs its
-- speed and bezier (`hl.animation` refuses a leaf with no `speed`), and Hyprland does
-- not report an animation leaf's settings (hyprctl says "no such option" for one), so
-- a mode switch could only put a guessed curve in Omarchy's place. One animation tree
-- for the compositor, then, with the pack's leaves quiet everywhere.

hl.animation({ leaf = "windowsIn", enabled = false })
hl.animation({ leaf = "windowsOut", enabled = false })
hl.animation({ leaf = "windowsMove", enabled = false })
hl.animation({ leaf = "fadeIn", enabled = false })
hl.animation({ leaf = "fadeOut", enabled = false })
hl.animation({ leaf = "border", enabled = false })

-- Desktop-style window rules: the pack floats the windows on its own workspaces.
-- Registered here, early, and not from a helper later in the file: window rules
-- are applied in registration order, so one registered late loses to every rule
-- the config (or a scenario) put in before it -- a nest rule that tiles
-- Chromium-based apps beat this one and left a window tiled but still carrying the
-- pack's tag.
--
-- The rule matches on the class, not on the workspace: a rule with a workspace
-- match is what Hyprland turns into a work-area sized window (measured in a nest:
-- `match = { workspace = "r[1-5]" }, float = true` opened a 148x178 terminal at
-- 831x924, the whole work area). So the float applies everywhere and the mode is
-- enforced per window: claim_window, on window.open, hands a window back to
-- Omarchy when its workspace is not the pack's, and leaving xmode does the same
-- for the windows already there.
--
-- suppress_event = maximize: a client request to maximize (Zed does this on
-- startup) would enter Hyprland's FSMODE_MAXIMIZED. That mode is not a floating
-- window, and a later move is ignored, so the titlebar drag does nothing until
-- something (Super+Alt+F) takes it back out. Real fullscreen is a different
-- request and is not suppressed.
hl.window_rule({
  name = "x-mode-float",
  enabled = true,
  match = { class = ".*" },
  float = true,
  opacity = "1.0 override 1.0 override",
  suppress_event = "maximize",
})
-- Omarchy's browser defaults force Chromium-based apps to tile, and that tag rule
-- would win over the one above.
hl.window_rule({ name = "x-mode-float-browser", enabled = true, match = { class = ".*", tag = "chromium-based-browser" }, tile = false, float = true })
--
-- suppress_event = maximize: a client request to maximize (Zed does this on
-- startup) would enter Hyprland's FSMODE_MAXIMIZED. That mode is not a
-- floating window, and a later move is ignored, so the titlebar drag does
-- nothing until something (Super+Alt+F) takes it back out. Real fullscreen
-- is a different request and is not suppressed.

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

-- The plugin has to be loaded before its own keys are set. Hyprland parses this file
-- before anything has loaded it, and a `plugin:hyprbars:*` key that no plugin
-- registered is reported as an unknown key and dropped -- a dozen errors on every
-- login, with the bar height, the tab height and the colours lost on that parse.
-- So it is loaded here, the way Omarchy's own titlebars module does it. The
-- installer has already unloaded the previous copy and written this path, so
-- there is no second file to move into place.
local function ensure_hyprbars()
  local dir = (os.getenv("HOME") or "") .. "/.local/share/hyprbars/"
  local so = dir .. "x-mode-hyprbars.so"
  -- Only when there is a build to load: the nest has no installed copy (its
  -- harness loads the repo build itself), and asking the loader for a missing file
  -- there is not something the config should do.
  local base = io.open(so, "r")
  if base ~= nil then
    base:close()
    if hl.plugin ~= nil and hl.plugin.load ~= nil then
      pcall(hl.plugin.load, so)
    end
  end
end
ensure_hyprbars()

pcall(function()
  -- A reload re-runs Omarchy's titlebars() before this file. She writes her
  -- floating-workspace look into the plugin that is already loaded (this one)
  -- and appends her buttons. Keep that look for her windows, then put the
  -- pack's own back: the two never share a bar.
  local ok_tag, tag = pcall(hl.get_config, "plugin:hyprbars:workspace_tag")
  if ok_tag and type(tag) == "string" and tag ~= "" and hl.plugin and hl.plugin.hyprbars and hl.plugin.hyprbars.stash_omarchy then
    pcall(hl.plugin.hyprbars.stash_omarchy)
  end
  hl.config({
    plugin = {
      hyprbars = {
        enabled = true,
        bar_height = TITLEBAR_FALLBACK,
        on_double_click = "",
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
    if hl.plugin.hyprbars.clear_buttons then
      hl.plugin.hyprbars.clear_buttons()
    end
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
-- The panel's "Show dock" row turns the card -- and so this inset -- off with
-- the dock: the zones then end at the outer gap, as if no dock were there. The
-- flag is forward-declared here (load_options, far below, is what reads it) and
-- asked through DOCK_INSET at every publish, so the option is never a copy.
-- The dock's two facts in one table -- whether the panel's "Show dock" option
-- has it on, and the card width the layer last reported (40 before it has ever
-- been seen). One table rather than a local each because this file is at Lua's
-- 200-local limit for the top-level function.
local dock = { on = true, card = 40 }
-- Declared up here so the dock inset can see it. The panel's No gaps is filled
-- in when the settings load; until then the desktop's own gap is the margin.
local no_gaps = false
-- The card width is only part of the inset while the dock is shown: with the
-- option off there is no card to clear, and the inset is the outer gap alone.
-- Read here rather than at the callers so the no-gap pass (which publishes the
-- card on its own) cannot put a width back behind the option's back.
local function DOCK_INSET()
  if not dock.on then
    return 0
  end
  return dock.card
end
local function DOCK_PULL()
  -- The dock is only on xmode workspaces, and No gaps is only for those, so the
  -- card sits on the screen edge instead of half a gap in.
  if no_gaps then
    return DOCK_INSET()
  end
  return DOCK_INSET() + math.floor(GAP_OUT() / 2)
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
  if w == nil or w == dock.card then
    return
  end
  dock.card = w
  apply_gap_geometry()
  -- The zones moved with the card; put the windows that were on one back on it,
  -- matched against the frame they were placed in (layout.lua keeps it).
  layout.frame_changed()
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
-- the window, draws the preview, and applies the snap. The zones, the restore
-- and the Super+Alt hotkeys are layout.lua's; this file binds them, unbinds what
-- Omarchy had on the same keys, and defers same-app grouping during a drag.

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

local function window_class(w)
  if w == nil then
    return ""
  end
  return string.lower(tostring(w.initial_class or w.class or ""))
end

-- layout.lua owns everything that puts a window on a zone: the snap, the
-- restore, the re-apply a load or a moved frame needs, and the one-shot arrange.
-- It asks the plugin for geometry and remembers the frame it asked with; this
-- file gives it the pieces of the pack it cannot reach -- the plugin handle, the
-- drag, the dock card, the window queries and the grouping -- and the state dir
-- the arrange marker lives in.
--
-- ws_id, refresh_window and consolidate are defined further down (they need
-- helpers from the grouping section); forward-declared here so the closures
-- below see the real functions rather than a global that never exists.
local find_peer
local ws_id
local refresh_window
local consolidate
local window_by_addr

-- The mode of a workspace, and whether a window is on one of the pack's.
-- Everything that belongs to the pack -- the float rule, the titlebar, the tabs,
-- the keys, the geometry -- asks this, and answers no on a workspace Omarchy is
-- tiling, scrolling or floating itself.
local function ws_mode(id)
  return modes.get(X_MODE_MODES, id)
end

local function in_xmode(w)
  if w == nil then
    return false
  end
  return modes.is_xmode(X_MODE_MODES, ws_id(w))
end

layout.init({
  plugin = bars,
  dragging = dragging,
  -- layout.lua keeps its hands off a window that is not the pack's: the float on
  -- load, the arrange and the re-apply all ask this first, so a tiled workspace
  -- is never dealt into the pack's zones.
  in_xmode = in_xmode,
  dock_card = function()
    return dock.card
  end,
  -- What the right inset actually counts, which the no-gap pass publishes and
  -- so has to be the option's answer and not the last card the dock had.
  dock_inset = DOCK_INSET,
  -- The frame numbers the pack publishes. layout.lua asks for them instead of
  -- keeping a copy: a frame that moved is what asks for a re-apply, so the
  -- numbers it compares have to be the ones the plugin was actually told.
  gap_out = GAP_OUT,
  border = BORDER,
  dock_pull = DOCK_PULL,
  state_dir = X_MODE_STATE,
  list = function()
    return as_list(hl.get_windows())
  end,
  window_at = function(addr)
    return window_by_addr(addr)
  end,
  class_of = window_class,
  space_of = function(w)
    return ws_id(w)
  end,
  refresh = function(w)
    return refresh_window(w)
  end,
  find_peer = function(w)
    return find_peer(w)
  end,
  consolidate = function()
    consolidate()
  end,
})

local function ensure_tab_group(window)
  if window == nil or window.group ~= nil then
    return
  end
  pcall(function()
    hl.dispatch(hl.dsp.group.toggle({ window = window }))
  end)
end

-- join_same_app is defined with the rest of the grouping below.
local join_same_app
local apps_off = {}
-- Keyboard replacements the main panel forces on for every class, keyed by the
-- same name the parsed apps use (options.keys). This is the fallback: a class with
-- its own three-state setting wins over it, so a card can say Always off where the
-- desktop says on (settings.key_flag is where the two meet).
local key_flags = {}
-- Occupied Super keys stolen for every class (options.keys.steal), the same kind of
-- fallback for the per-key lists.
local global_steal = {}
-- Whether the pack takes Ctrl+Cmd+Q for the lock (options.lockScreenKey, on
-- unless the file says false). Declared here because the lock bind is applied
-- with the capture keys, above the options block that reads it.
local lock_key = true

-- One keyboard flag for a class: the app's own three-state setting (true is Always
-- on, false is Always off) or, when it has none, the desktop's forced one. Nothing
-- is pre-built into sets here, so a card that says Always off wins over a global on
-- without a second source of truth.
local function key_flag(name, cls)
  return settings.key_flag(apps_cfg, cls, key_flags, name)
end

-- Whether anything has the flag on at all. The generated binds exist only then, so
-- one card's Always on is enough to put them in place.
local function key_flag_any(name)
  return settings.key_flag_any(apps_cfg, key_flags, name)
end
local ctrl_c_binds = {}
-- Defined with the other option appliers (it reads the bind table out of band),
-- forward-declared so the app refresh can call it.
local apply_super_ctrl

-- Send a chord to a window as its own down/up pair. `send_shortcut` pairs the
-- press with the physical key and the release with its release, so the app is
-- left *holding* a key whose Ctrl is already gone: its own key repeat then types
-- the bare letter -- holding Cmd+D in an editor selected once and then wrote "d".
-- The pair is what Omarchy's clipboard and the text chords below send by hand for
-- the same stuck/repeating synthetic key (hyprland discussion 14099). A key held
-- down is the bind's business, not the app's: see `repeating` in bind_super_ctrl.
--
-- The key goes as a keycode, not as a name: `send_shortcut` resolves a name by
-- looking the keysym up in the *active* layout, so on a Cyrillic layout Ctrl+T
-- would not resolve at all. A keycode is what "Cmd+T means the physical T key"
-- wants anyway.
local function send_chord(mods, key, w)
  local code = supermap.key_code(key)
  if code == nil then
    return false
  end
  local k = "code:" .. tostring(code)
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = k, state = "down", window = w }))
  hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = k, state = "up", window = w }))
  return true
end

local function send_ctrl(key, shift, w)
  return send_chord(shift and "CTRL SHIFT" or "CTRL", key, w)
end

local function key_stolen(cls, key, shift)
  return settings.key_stolen(apps_cfg, cls, global_steal, supermap.key_id(key, shift))
end

function window_by_addr(addr)
  if addr == nil then
    return nil
  end
  local a = tostring(addr)
  if a:sub(1, 8) ~= "address:" then
    a = "address:" .. a
  end
  return hl.get_window(a)
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
-- Does the app switcher (below) hold the pointer right now? It is set with the
-- rest of the switcher's state, and declared here because the Ctrl+click bind
-- below has to know. The row is drawn over the windows, and a click on one of its
-- icons is a click on the icon: the window the icon covers must not be read as
-- the click's target. It was, whenever that window carried the flag -- the click
-- went to it as a Ctrl+click and the row never saw it, so clicking an icon did
-- nothing exactly when a flagged app (the browser) was under the row.
local switcher_active = false

local function super_ctrl_click(button)
  return function()
    -- The switcher is up: the click belongs to its row (a layer surface takes
    -- the pointer over a window), so the event only has to be let through.
    if switcher_active then
      return { pass_event = true }
    end
    -- Titlebar / empty space: let the click through (hyprbars, focus).
    -- The window under the cursor, not the focused one: Cmd+click a link in
    -- a background window should still be Ctrl+click there.
    local w = window_at_cursor()
    if w == nil or not key_flag("ctrl_click", window_class(w)) then
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
-- The fullscreen check a zone re-apply needs is layout.lua's (is_fullscreen
-- there); what is left here is the comment about keeping a window below the bar.
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
-- when Super is released. `switcher_active` is declared above the Ctrl+click
-- bind, which is the one other place that has to know the row holds the pointer.
local SWITCHER_PATH = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/omarchy-switcher.cmd"
local last_switcher = ""

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

-- --- tiling keys: the pack's only on its own workspaces -----------------------
-- These are the keys the pack takes from Omarchy's tiler -- focus direction, the
-- resize steps, floating/pseudo/split, pop-out, the tiled-width pair, the gaps
-- toggle. Tiling, scrolling and Omarchy's own floating each still need them, so
-- the key is bound once and the *mode* decides: inside xmode the key belongs to
-- the pack (and to the app, since the Mac side of this desktop keeps the arrows
-- and the resize steps free -- `pass_event` hands the key on), everywhere else it
-- does exactly what Omarchy binds.
--
-- Omarchy's half is performed here rather than replayed from her files: her arrow
-- and resize steps are Lua function dispatchers, and hyprctl prints `__lua` for
-- those, so there is no command to replay -- the pack calls the same dispatcher
-- instead. The four she wrote as commands are run as commands.
local function resize_step(x, y)
  return function()
    hl.dispatch(hl.dsp.window.resize({ x = x, y = y, relative = true }))
  end
end

local TILING_KEYS = {
  -- Focus, the four arrows.
  { keys = "SUPER + LEFT", label = "Focus on left window", omarchy = function() hl.dispatch(hl.dsp.focus({ direction = "l" })) end },
  { keys = "SUPER + RIGHT", label = "Focus on right window", omarchy = function() hl.dispatch(hl.dsp.focus({ direction = "r" })) end },
  { keys = "SUPER + UP", label = "Focus on above window", omarchy = function() hl.dispatch(hl.dsp.focus({ direction = "u" })) end },
  { keys = "SUPER + DOWN", label = "Focus on below window", omarchy = function() hl.dispatch(hl.dsp.focus({ direction = "d" })) end },
  -- Swap with the neighbour (Omarchy's Shift+arrows).
  { keys = "SUPER + SHIFT + LEFT", label = "Swap window to the left", omarchy = function() hl.dispatch(hl.dsp.window.swap({ direction = "l" })) end },
  { keys = "SUPER + SHIFT + RIGHT", label = "Swap window to the right", omarchy = function() hl.dispatch(hl.dsp.window.swap({ direction = "r" })) end },
  { keys = "SUPER + SHIFT + UP", label = "Swap window up", omarchy = function() hl.dispatch(hl.dsp.window.swap({ direction = "u" })) end },
  { keys = "SUPER + SHIFT + DOWN", label = "Swap window down", omarchy = function() hl.dispatch(hl.dsp.window.swap({ direction = "d" })) end },
  -- The resize steps: Cmd +/- and its Shift, Alt and Ctrl variants.
  { keys = "SUPER + code:20", label = "Expand window left", omarchy = resize_step(-100, 0) },
  { keys = "SUPER + code:21", label = "Shrink window left", omarchy = resize_step(100, 0) },
  { keys = "SUPER + SHIFT + code:20", label = "Shrink window up", omarchy = resize_step(0, -100) },
  { keys = "SUPER + SHIFT + code:21", label = "Expand window down", omarchy = resize_step(0, 100) },
  { keys = "SUPER + ALT + code:20", label = "Expand window left a little", omarchy = resize_step(-25, 0) },
  { keys = "SUPER + ALT + code:21", label = "Shrink window left a little", omarchy = resize_step(25, 0) },
  { keys = "SUPER + SHIFT + ALT + code:20", label = "Shrink window up a little", omarchy = resize_step(0, -25) },
  { keys = "SUPER + SHIFT + ALT + code:21", label = "Expand window down a little", omarchy = resize_step(0, 25) },
  { keys = "SUPER + CTRL + code:20", label = "Expand window left a lot", omarchy = resize_step(-300, 0) },
  { keys = "SUPER + CTRL + code:21", label = "Shrink window left a lot", omarchy = resize_step(300, 0) },
  { keys = "SUPER + CTRL + SHIFT + code:20", label = "Shrink window up a lot", omarchy = resize_step(0, -300) },
  { keys = "SUPER + CTRL + SHIFT + code:21", label = "Expand window down a lot", omarchy = resize_step(0, 300) },
  -- The layout toggles.
  { keys = "SUPER + T", label = "Toggle window floating/tiling", omarchy = function() hl.dispatch(hl.dsp.window.float({ action = "toggle" })) end },
  { keys = "SUPER + J", label = "Toggle window split", omarchy = function() hl.dispatch(hl.dsp.layout("togglesplit")) end },
  { keys = "SUPER + P", label = "Pseudo window", omarchy = function() hl.dispatch(hl.dsp.window.pseudo()) end },
  { keys = "SUPER + O", label = "Pop window out (float & pin)", omarchy = function() hl.exec_cmd("omarchy-hyprland-window-pop") end },
  { keys = "SUPER + CTRL + F", label = "Tiled full screen", omarchy = function() hl.exec_cmd("omarchy-hyprland-window-tiled-fullscreen-toggle") end },
  { keys = "SUPER + Home", label = "Restore window width", omarchy = function() hl.exec_cmd("omarchy-hyprland-window-width restore") end },
  { keys = "SUPER + ALT + Home", label = "Save window width", omarchy = function() hl.exec_cmd("omarchy-hyprland-window-width save") end },
  -- The scratchpad pair.
  { keys = "SUPER + S", label = "Toggle scratchpad", omarchy = function() hl.dispatch(hl.dsp.workspace.toggle_special("scratchpad")) end },
  { keys = "SUPER + ALT + S", label = "Move window to scratchpad", omarchy = function() hl.dispatch(hl.dsp.window.move({ workspace = "special:scratchpad", follow = false })) end },
}

-- The gaps toggle is the pack's own switch (the panel's "No gaps"), so in xmode
-- the key is taken and does nothing; every other mode keeps Omarchy's key. Both
-- spellings, since Omarchy writes it by keycode.
for _, keys in ipairs({ "SUPER + SHIFT + BACKSPACE", "SUPER + SHIFT + code:22" }) do
  table.insert(TILING_KEYS, { keys = keys, label = "Toggle window gaps", omarchy = "omarchy-hyprland-window-gaps-toggle" })
end

for _, e in ipairs(TILING_KEYS) do
  hl.unbind(e.keys)
  local command = e.omarchy
  local own = e.xmode
  -- The key an app with the Super-as-Ctrl flag would get. The plan that generates
  -- those binds works off the live bind table and leaves alone whatever the
  -- desktop binds -- which is every key below now -- so the pack sends the Ctrl
  -- chord itself for the app that asked for it, and only on its own workspaces
  -- (elsewhere these keys are the tiler's).
  local id = supermap.steal_id_of(e.keys)
  if id == nil then
    -- A keycode spelling (`code:20`) has no id of its own: Omarchy writes the
    -- resize steps that way, and without this an app with the Super-as-Ctrl flag
    -- got the raw Super+minus, which zooms nothing.
    local shift_code, code = e.keys:match("SHIFT%s*%+%s*code:(%d+)")
    if shift_code == nil then
      code = e.keys:match("code:(%d+)")
    end
    if code ~= nil then
      local name = supermap.code_name(code)
      if name ~= nil then
        id = (shift_code ~= nil) and ("SHIFT+" .. name) or name
      end
    end
  end
  local shift = false
  if id ~= nil then
    local unshifted = id:match("^SHIFT%+(.+)$")
    if unshifted ~= nil then
      shift = true
      id = unshifted
    end
  end
  pcall(o.bind, e.keys, e.label or "", function()
    local w = hl.get_active_window()
    if in_xmode(w) then
      if own ~= nil then
        return own()
      end
      if id ~= nil and window_class(w) ~= "" and key_flag("ctrl_as_super", window_class(w)) then
        send_ctrl(id, shift, w)
        return
      end
      -- In xmode the key is not the tiler's: hand it to the app.
      return { pass_event = true }
    end
    if type(command) == "string" then
      hl.exec_cmd(command)
      return
    end
    if command ~= nil then
      command()
    end
  end)
end

-- [id] = true for every key the pack binds itself, in the steal list's spelling
-- (Super or Super+Shift + one key). Omarchy's files describe what used to be on
-- such a key -- her focus on Cmd+Left, window transparency on Cmd+Backspace --
-- and both are text chords here now, so a file-derived replay must not claim one
-- of them, or stealing the key would break every app that did not steal it.
local pack_keys = {}
local function note_pack_key(keys)
  local id = supermap.steal_id_of(keys)
  if id ~= nil then
    pack_keys[id] = true
  end
end
-- Cmd+Shift+T is the Shortcuts row "reopen tab", not one more occupied key.
-- Omarchy's Activity stays on the key until that row is on; listing it here keeps
-- the steal screen from offering the same chord a second time as "Activity".
note_pack_key("SUPER + SHIFT + T")
-- Cmd+W closes the active window (Omarchy's killactive). Just close it: the
-- patched hyprbars keeps the group focused on the previous tab and raises it
-- from its single window.close listener, which Cmd+W, the tabbar close button
-- and apps closing their own window all share.
--
-- An app that steals W sends Ctrl+W instead, so Cmd+W closes the tab rather
-- than the whole window (a browser, a terminal). The key goes to the focused
-- window as a real Ctrl+W; the close path above stays out of the way. W used to
-- be a replacement of its own (the panel's ctrlW flag) -- it is one of the
-- occupied keys now, with the same toggle as Cmd+Q and Cmd+F.
hl.unbind("SUPER + W")
o.bind("SUPER + W", "Close window", function()
  local w = hl.get_active_window()
  if w == nil then
    return
  end
  if key_stolen(window_class(w), "W", false) then
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

-- --- Universal clipboard ------------------------------------------------------
-- Cmd+A/C/V/X send the app its own select all/copy/paste/cut. Omarchy has her own
-- version of this, and hers hands the chord over *by name* ("A", "C", "Insert"):
-- Hyprland resolves a name in the *active* layout group, where a Russian group has
-- no Latin A on the A key, so the dispatch raises "runtime error in lua,
-- send_key_state: key not found" and the chord never reaches the app -- until the
-- name happens to have been resolved once and cached, which is why it only bit
-- sometimes. The pack owns the key from load and sends a keycode, so the chord is
-- the physical key whatever the layout says.
--
-- No window target on purpose: the chord goes to whatever surface has focus, so a
-- layer-shell panel (the clipboard manager's search field) receives it too, which
-- is what her version does with the same trick.
--
-- The terminal split is hers as well: readline has no clipboard, so a terminal gets
-- the Insert chords, where Ctrl+C would be the interrupt. Cmd+A has no split of
-- its own (Ctrl+A is what she sent everywhere, and readline's beginning of line is
-- what a terminal gets from it). Cmd+A/C/V/X are not offered in the panel's steal
-- list: the chord they send *is* what a steal would send, so there is nothing to
-- choose between.
local CLIPBOARD = {
  { keys = "SUPER + A", label = "Select all", mods = "CTRL", code = "A" },
  { keys = "SUPER + C", label = "Universal copy", mods = "CTRL", code = "C", terminal_mods = "CTRL", terminal_code = "INSERT" },
  { keys = "SUPER + V", label = "Universal paste", mods = "CTRL", code = "V", terminal_mods = "SHIFT", terminal_code = "INSERT" },
  { keys = "SUPER + X", label = "Universal cut", mods = "CTRL", code = "X" },
}

for _, e in ipairs(CLIPBOARD) do
  hl.unbind(e.keys)
  note_pack_key(e.keys)
  pcall(o.bind, e.keys, e.label, function()
    local mods, name = e.mods, e.code
    local w = hl.get_active_window()
    if e.terminal_code ~= nil and w ~= nil and textkeys.is_terminal(w.tags) then
      mods, name = e.terminal_mods, e.terminal_code
    end
    local code = supermap.key_code(name)
    if code == nil then
      return
    end
    local key = "code:" .. tostring(code)
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  end)
end

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
note_pack_key("SUPER + SHIFT + TAB")
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
--
-- A window that has no group to step through -- the app's second window that is
-- not a tab of the first, which is what Hyprland floats a dialog into and what
-- hyprbars.groupable refuses a tab (KeePassXC's access prompt is a second window
-- of the class of the vault it asks about) -- steps to the app's next window on
-- the workspace instead of doing nothing: the keys then reach every window the
-- app has, which Cmd+Tab cannot (it lists apps, and the app is already one
-- entry). Order is most recently focused first, the same focus_history_id order
-- the switcher uses, and it wraps.
local function switch_app_window(next)
  local w = hl.get_active_window()
  if w == nil then
    return false
  end
  local cls = window_class(w)
  local space = ws_id(w)
  local list = {}
  for _, other in ipairs(as_list(hl.get_windows())) do
    if other.address ~= nil and other.mapped ~= false and not other.hidden and window_class(other) == cls and ws_id(other) == space then
      list[#list + 1] = other
    end
  end
  local n = #list
  if n < 2 then
    return false
  end
  table.sort(list, function(a, b)
    return (tonumber(a.focus_history_id) or 999999) < (tonumber(b.focus_history_id) or 999999)
  end)
  local idx = 1
  for i, other in ipairs(list) do
    if other.address == w.address then
      idx = i
      break
    end
  end
  local target = list[mru.step(idx, n, next and 1 or -1)]
  if target == nil or target.address == w.address then
    return false
  end
  -- A focus dispatch raises too, so the window that comes up is drawn on top.
  hl.dispatch(hl.dsp.focus({ window = target }))
  return true
end

local function switch_group_tab(next)
  local w = hl.get_active_window()
  if w == nil then
    return
  end
  local members = w.group and w.group.members or {}
  local n = #members
  if n < 2 then
    switch_app_window(next)
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

-- Super+Alt+arrows were Omarchy's "move window into the neighbour's group". Inside
-- xmode the pack snaps with them instead; every other mode keeps Omarchy's move,
-- so those four keys are the pack's only on its own workspaces.
hl.unbind("SUPER + ALT + LEFT")
hl.unbind("SUPER + ALT + RIGHT")
hl.unbind("SUPER + ALT + UP")
hl.unbind("SUPER + ALT + DOWN")
-- The dispatchers are built inside the handlers: at load they would be built while
-- Omarchy's keybindings scan reads the config with a stub `hl`, and there the dsp
-- table only answers one level deep (hl.dsp.window.move would index a function).
local function alt_arrow(own, into_group)
  pcall(o.bind, own.keys, own.label, function()
    if in_xmode(hl.get_active_window()) then
      return own.action()
    end
    hl.dispatch(hl.dsp.window.move({ into_group = into_group }))
  end)
end
alt_arrow({ keys = "SUPER + ALT + LEFT", label = "Snap or expand window left", action = function() layout.cycle("left") end }, "l")
alt_arrow({ keys = "SUPER + ALT + RIGHT", label = "Snap or expand window right", action = function() layout.cycle("right") end }, "r")
alt_arrow({ keys = "SUPER + ALT + UP", label = "Move window into the group above", action = function() return { pass_event = true } end }, "u")
alt_arrow({ keys = "SUPER + ALT + DOWN", label = "Move window into the group below", action = function() return { pass_event = true } end }, "d")

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
  layout.snap("maximize")
end)
hl.unbind("SUPER + ALT + A")
o.bind("SUPER + ALT + A", "Almost maximize window", function()
  layout.snap("almost-maximize")
end)
o.bind("CTRL + ALT + UP", "Maximize window", function()
  layout.snap("maximize")
end)
o.bind("CTRL + ALT + DOWN", "Restore window size", function()
  layout.snap("restore")
end)
o.bind("CTRL + ALT + U", "Snap window top-left", function()
  layout.snap("top-left")
end)
o.bind("CTRL + ALT + I", "Snap window top-right", function()
  layout.snap("top-right")
end)
o.bind("CTRL + ALT + J", "Snap window bottom-left", function()
  layout.snap("bottom-left")
end)
o.bind("CTRL + ALT + K", "Snap window bottom-right", function()
  layout.snap("bottom-right")
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
--
-- The typography a Mac's layout carries is in the same table: the pack cannot
-- send a character its keymap does not have, so the dash goes as the *compose*
-- sequence the keymap does have and everything else is unchanged -- the same
-- send, which is also what keeps the held Option out of the app. A virtual
-- keyboard cannot stand in for it: wtype types through the seat, so the held
-- Option is still in the app's modifier state and a terminal reads the dash as
-- Alt+dash and prefixes Escape (measured in the nest: an em dash arrived as
-- 1b e2 80 94, and a tap meant to clear the modifier did not hold).
-- One sequence of chords at a time: the bind repeats while the key is held (see
-- the bind loop below), and a sequence is longer than the repeat interval -- two
-- chords and their 80ms gap. A new Shift+Home landing inside the previous pair
-- (Shift+Home, Shift+Home, Backspace, Backspace) deletes one character where it
-- meant to delete the line, so a repeat that arrives mid-sequence is dropped and
-- the next one starts a fresh sequence.
local chords_busy = false

local function send_chords(list, w)
  if chords_busy then
    return
  end
  -- One chord as its own down/up pair rather than `send_shortcut`, which sends
  -- the press and the release in one call: a *second* chord sent that way right
  -- after the first arrives twice (Shift+End then two Deletes), the same
  -- stuck/repeating synthetic key Omarchy's clipboard sends key state by hand
  -- to avoid (hyprland discussion 14099). Sending it by hand also keeps a
  -- synthetic Shift from being left held for the next keystroke.
  -- A chord whose key the pack has no keycode for goes as its name: the compose
  -- key is the one such key -- which physical key carries Multi_key is the
  -- user's input option, so there is no code to hard-code -- and Hyprland
  -- resolves the name in the keymap it just checked had one. Every other chord
  -- stays a keycode, so it is the physical key whatever the layout says.
  local function send(c)
    local code = supermap.key_code(c.key)
    local key = code ~= nil and ("code:" .. tostring(code)) or c.key
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
  -- Held until the last chord's release: the down goes out now and its up 50ms
  -- later, one gap per further chord.
  chords_busy = true
  hl.timer(function()
    chords_busy = false
  end, { timeout = (#list - 1) * 80 + 60, type = "oneshot" })
end

-- Whether the desktop's keymap has a compose key at all. The typography
-- entries need one (see textkeys.lua), and it is the user's input option: read
-- live, so an edit to it takes effect on the next press.
local function compose_key()
  local ok, options = pcall(hl.get_config, "input:kb_options")
  if not ok then
    return false
  end
  return textkeys.compose_key(options)
end

local function text_chord(e)
  return function()
    local w = hl.get_active_window()
    if w == nil then
      return { pass_event = true }
    end
    if e.needs == "compose" and not compose_key() then
      -- Nothing in the keymap to spell the character with, so the key stays
      -- the app's: sending Multi_key at a keymap that has no such key is a
      -- Hyprland error on every press and types nothing anyway.
      return { pass_event = true }
    end
    -- "⌘[ ] move code" in Shortcuts: this app's Cmd+[ / Cmd+] indent instead of
    -- going back and forward. Every other chord ignores the flag.
    local chords = textkeys.chords(e.id, textkeys.is_terminal(w.tags), key_flag("move_code", window_class(w)))
    if chords == nil or #chords == 0 then
      -- Nothing to send in this context (readline has no selection to
      -- extend), so the key stays the app's rather than being swallowed.
      return { pass_event = true }
    end
    send_chords(chords, w)
    return { pass_event = false }
  end
end

-- `repeating`: a held Option+Backspace keeps deleting words and a held Cmd+Left
-- keeps jumping, the way a Mac repeats them. The repeat has to be the bind's --
-- the pack hands the app a whole chord and nothing held, so the app has no key of
-- its own to repeat with.
for _, e in ipairs(textkeys.plan()) do
  -- Drop whatever held the key: Omarchy's default (Cmd+Backspace, Cmd+Home) or
  -- a Super-as-Ctrl bind left over from the previous config evaluation.
  hl.unbind(e.keys)
  note_pack_key(e.keys)
  pcall(o.bind, e.keys, e.label, text_chord(e), { repeating = true })
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
  note_pack_key(e.keys)
  hl.unbind(e.keys)
  if e.code ~= nil then
    hl.unbind(e.code)
  end
  pcall(o.bind, e.keys, e.label, e.cmd)
end

-- The macOS lock key. Omarchy locks on Ctrl+Cmd+L and keeps its Calculator on
-- Ctrl+Cmd+Q; macOS puts Lock Screen on Ctrl+Cmd+Q, so the pack takes that one
-- key -- both spellings, since Omarchy may write it by keycode -- and binds
-- Omarchy's own lock command to it. Unlike the capture keys this takes a key a
-- user may want, so it is an option: with it off nothing is unbound, and the
-- reload that applies an option brings Omarchy's Calculator back. It is applied
-- at the bottom with the other option appliers, not inline here: the option is
-- read from the settings file further down, and binding before that would take
-- the key whatever the file says.
local LOCK_KEYS = "SUPER + CTRL + Q"
local LOCK_CODE = "SUPER + CTRL + code:24"
local lock_binds = {}

local function apply_lock_key()
  for _, kb in ipairs(lock_binds) do
    pcall(function()
      kb:unbind()
    end)
  end
  lock_binds = {}
  if not lock_key then
    return
  end
  hl.unbind(LOCK_KEYS)
  hl.unbind(LOCK_CODE)
  local ok, kb = pcall(o.bind, LOCK_KEYS, "Lock the screen", "omarchy-system-lock")
  if ok and kb then
    lock_binds[#lock_binds + 1] = kb
  end
end

function ws_id(w)
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
--                      "ctrlAsSuper": false, "ctrlCShift": false,
--                      "ctrlClick": false, "digitTabs": false,
--                      "ctrlAsSuperKeys": [] } } }
-- chrome=false → no titlebar/tabbar/grouping. alwaysTabbar → tab strip even
-- when the window is not grouped. compactTabs → one Chrome-like titlebar row
-- (tabs of limited width, leftover drags the window) instead of titlebar +
-- tabbar; the same flag in options turns it on for every app. ctrlAsSuper → unbound Super+key reaches the
-- app as Ctrl+key; digitTabs → the
-- freed Super+1..0 are the pack's own tabs for this class (reserved: the app
-- never sees the digit); ctrlAsSuperKeys →
-- occupied Super keys stolen for this app (Cmd+W, Cmd+Q, Cmd+F, ... all the same
-- toggle now); ctrlClick →
-- Super+click is Ctrl+click; ctrlCShift →
-- Ctrl+C reaches it as Ctrl+Shift+C, so the app's own binding can make it the
-- interrupt while Super+C stays the copy. Missing entries mean chrome on, flags
-- off. An older file's ctrlW is folded onto the W steal on the way in.
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
-- A settings file is written by truncating it first (the panel does exactly that),
-- so a read can catch a prefix of one. The parser looks for keys rather than
-- requiring a document, so a prefix parses -- as "every flag off, no app cards".
-- With the plan dropping the installed binds before it reads the flags, that torn
-- read took the whole Super-as-Ctrl map away mid-write: Cmd+Z stopped reaching
-- every app. A prefix is not an answer; `{` at the start and no closing `}` means
-- the writer has not finished, and the caller keeps what it already has.
local function complete_settings(raw)
  local s = tostring(raw or "")
  if s:find("^%s*{") == nil then
    return s ~= ""
  end
  return s:find("}%s*$") ~= nil
end

local function current_settings()
  local raw = read_settings()
  if raw ~= nil and not complete_settings(raw) then
    return nil
  end
  if raw == nil then
    return ""
  end
  return raw
end

local function apps_raw()
  local raw = current_settings()
  if raw == nil then
    return nil
  end
  return settings.apps_section(raw)
end

local function load_apps()
  local raw = apps_raw()
  if raw == nil then
    -- Same rule: a torn read leaves the app cards as they are (`{}` on the very
    -- first load, where there is nothing to keep yet).
    return apps_cfg or {}
  end
  return settings.parse_apps(raw)
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

-- The flags themselves are not collected into sets any more: settings.key_flag
-- answers for one class and one flag on the spot, from the app's three-state
-- setting and the desktop's fallback.

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
  if #ctrl_c_binds > 0 or not key_flag_any("ctrl_c_shift") then
    return
  end
  local ok, kb = pcall(hl.bind, "CTRL + C", function()
    local w = hl.get_active_window()
    if w == nil or not key_flag("ctrl_c_shift", window_class(w)) then
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
local compact_applied = {}

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
  apply_ctrl_c_shift()
  local wanted_nobar, wanted_always, wanted_compact = settings.desired_rules(apps_cfg)
  local add_nobar, drop_nobar = settings.rule_diff(wanted_nobar, nobar_applied)
  local add_always, drop_always = settings.rule_diff(wanted_always, always_applied)
  local add_compact, drop_compact = settings.rule_diff(wanted_compact, compact_applied)
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
  for _, cls in ipairs(add_compact) do
    set_rule("x-mode-compact-tabs-", cls, "hyprbars:compact_tabs", true)
  end
  for _, cls in ipairs(drop_compact) do
    set_rule("x-mode-compact-tabs-", cls, "hyprbars:compact_tabs", false)
  end
  nobar_applied = wanted_nobar
  always_applied = wanted_always
  compact_applied = wanted_compact
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
-- Defined with the other per-app key appliers further down; forward-declared
-- because this is the call the panel makes after writing an app's flag, and the
-- Ctrl+1..0 binds are planned only there.
local apply_ctrl_tab_switch
local apply_reopen_tab

-- What the panel's "for one app" rows run after they write the settings file
-- (the rows that change a desktop option reload instead). Everything a per-app
-- flag decides has to be re-planned here, whether it went on or off:
--   apply_apps        re-reads the file (apps_cfg = load_apps()) and applies the
--                     window rules, the grouping, and apply_ctrl_c_shift -- the
--                     Ctrl+C bind hangs off a flag being on anywhere;
--   apply_super_ctrl  the Super-as-Ctrl map, which apply_apps does not touch;
--   apply_ctrl_tab_switch  the Ctrl+1..0 binds. Missing here is why pinning
--                     "⌃1..0 switch tabs" for one app wrote the file and did
--                     nothing until some other click happened to reload.
--   apply_reopen_tab  Cmd+Shift+T. Same hole: a per-app pin has to bind it
--                     without a reload.
function x_mode.refresh_apps_off()
  apply_apps()
  -- Before the Super-as-Ctrl read, so that snapshot already shows Cmd+Shift+T
  -- taken when the row is on.
  apply_reopen_tab()
  apply_super_ctrl()
  apply_ctrl_tab_switch()
  ungroup_chrome_off()
  ungroup_never()
  regroup_chrome_on()
end

-- Desktop options (native scroll, compact tabs, Ctrl+1..0 tab switching, no gaps, workspaces
-- on F1..F10), read from settings.json. Ctrl+1..0 switches group tabs when the
-- focused app has chrome/titlebar on; otherwise the key is passed through to the
-- app. Off by default, so those shortcuts reach the app. No gaps is xmode only:
-- the desktop's gaps stay, and an xmode workspace gets a rule that zeros its
-- own. Workspaces on F1..F10 is what gives the pack the Super+1..0 digits (see
-- apply_workspace_keys) -- where they are reserved, handed over or left alone
-- per app; off is Omarchy's layout, Cmd+1..0 on the workspaces.
local native_scroll = false
local ctrl_tab_binds = {}
local compact_tabs = false
-- Workspace switching on Super+F1..F10 instead of Super+1..0.
local workspaces_fkeys = false
local workspace_key_binds = {}

local function load_options()
  local raw = current_settings()
  if raw == nil then
    -- A torn read keeps every option as it was: falling back to the defaults here
    -- is what switched Super as Ctrl off in the middle of a panel write.
    return
  end
  local o = settings.parse_options(raw)
  native_scroll = o.native_scroll
  no_gaps = o.no_gaps
  compact_tabs = o.compact_tabs
  workspaces_fkeys = o.workspaces_fkeys
  dock.on = o.dock
  lock_key = o.lock_key
  key_flags = o.key_flags
  global_steal = o.global_steal
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

-- No gaps is the panel's switch for xmode workspaces only. general:gaps_* stay
-- whatever Omarchy set, so dwindle, scrolling and her floating keep them. An
-- xmode workspace gets a rule that zeros its own gaps and leaves a 1px border.
-- The snap plugin reads that rule, so the zones move with it and nowhere else.
local gap_rules = {}

local function want_no_gap(id)
  id = tonumber(id)
  return no_gaps and id ~= nil and id >= 1 and modes.is_xmode(X_MODE_MODES, id)
end

local function no_gap_rule(id)
  id = tonumber(id)
  if id == nil or id < 1 then
    return
  end
  local existing = gap_rules[id]
  if existing ~= nil then
    pcall(function()
      existing:set_enabled(true)
    end)
  end
  -- The border stays a hairline so two windows do not merge into one. The top
  -- float gap is the titlebar: hyprbars draws it above the window box.
  local edge = 1
  local ok, rule = pcall(hl.workspace_rule, {
    workspace = tostring(id),
    gaps_in = 0,
    gaps_out = 0,
    border_size = edge,
    float_gaps = {
      top = TITLEBAR + edge,
      left = edge,
      right = edge,
      bottom = edge,
    },
  })
  if ok and rule ~= nil then
    gap_rules[id] = rule
  end
end

local function clear_gap_rule(id)
  id = tonumber(id)
  local rule = id ~= nil and gap_rules[id] or nil
  if rule ~= nil then
    pcall(function()
      rule:set_enabled(false)
    end)
  end
end

local function each_workspace(fn)
  local ok, list = pcall(hl.get_workspaces)
  if not ok or type(list) ~= "table" then
    return
  end
  if #list > 0 then
    for _, ws in ipairs(list) do
      fn(ws)
    end
  else
    for _, ws in pairs(list) do
      fn(ws)
    end
  end
end

local function sync_gap_rules()
  local seen = {}
  each_workspace(function(ws)
    local id = tonumber(ws and ws.id)
    if id == nil or id < 1 then
      return
    end
    seen[id] = true
    if want_no_gap(id) then
      no_gap_rule(id)
    else
      clear_gap_rule(id)
    end
  end)
  for id, _ in pairs(X_MODE_MODES.workspaces) do
    local n = tonumber(id)
    if n ~= nil and n >= 1 and not seen[n] then
      seen[n] = true
      if want_no_gap(n) then
        no_gap_rule(n)
      else
        clear_gap_rule(n)
      end
    end
  end
  for id, _ in pairs(gap_rules) do
    if not seen[id] then
      clear_gap_rule(id)
    end
  end
end

local function xmode_hits(hits)
  local out = {}
  for _, hit in ipairs(hits) do
    local id = tonumber(ws_id(hit.window))
    if id ~= nil and modes.is_xmode(X_MODE_MODES, id) then
      out[#out + 1] = hit
    end
  end
  return out
end

-- The two-layout match a gaps change needs is layout.zoned_hits: it returns
-- the windows in the *other* layout (matched against the live gaps, then, for
-- whatever is left, against the no-gap layout), and the pass below applies them.
local function apply_no_gaps()
  -- Name the zones while the windows are still in the layout they were snapped
  -- in. Turning the option off drops the rules first: those rules are the
  -- no-gap layout, and matching against them would see a window that is
  -- already there and leave it.
  if not no_gaps then
    sync_gap_rules()
  end
  local hits = layout.zoned_hits(no_gaps and "no-gap" or "live")
  if no_gaps then
    sync_gap_rules()
  end
  -- float_gaps stay the desktop's. The dock inset is the card alone while No
  -- gaps is on, because the dock only shows on the workspaces this applies to.
  apply_gap_geometry()
  flush_layout()
  layout.apply_hits(xmode_hits(hits))
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

-- One Chrome-like titlebar row for every app. Per-app compactTabs is a window
-- rule (apply_apps); this is the desktop-wide plugin config those windows
-- inherit when they have no rule of their own.
local function apply_compact_tabs()
  pcall(function()
    hl.config({
      plugin = {
        hyprbars = {
          compact_tabs = compact_tabs,
        },
      },
    })
  end)
end

local function focus_group_tab(index, reserve)
  local w = hl.get_active_window()
  -- Without `reserve` (the Ctrl+1..0 option) a window with no chrome of ours, no
  -- group, or no such tab passes the key through -- the app's own binding is what
  -- it should be. With `reserve` (a digit the card claimed for the pack's tabs)
  -- the key is eaten either way: a dead Cmd+3 is what reserved promises, a key
  -- that leaks to the app is not.
  if w == nil or w.group == nil or not chrome_on(window_class(w)) then
    return { pass_event = not reserve }
  end
  local members = w.group.members
  if index < 1 or index > #members then
    return { pass_event = not reserve }
  end
  -- group.active focuses the tab; the raise is the focus handler's.
  hl.dispatch(hl.dsp.group.active({ index = index, window = w }))
  return { pass_event = false }
end

-- Bind or release Ctrl+1..0. The handles are kept so turning the option off
-- removes exactly these binds (hl.unbind would also drop any the user set on
-- the same keys). A removed bind lets the key fall through to the app.
apply_ctrl_tab_switch = function()
  if key_flag_any("ctrl_tab_switch") then
    if #ctrl_tab_binds > 0 then
      return
    end
    for i = 1, 10 do
      local ok, kb = pcall(o.bind, "CTRL + code:" .. tostring(i + 9), "Switch to tab " .. i, function()
        -- The bind is global, the class decides: a card can turn this off for one
        -- app (Always off) while the desktop has it on, and then the key has to
        -- reach that app untouched. Same shape as the Super+1..0 digits.
        local w = hl.get_active_window()
        if w == nil or not key_flag("ctrl_tab_switch", window_class(w)) then
          return { pass_event = true }
        end
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

-- "Super as Ctrl": for an app with the flag, every Super+key the
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
  if w == nil or not key_flag("ctrl_as_super", window_class(w)) then
    return { pass_event = true }
  end
  send_ctrl(key, shift, w)
end

-- Pack-owned Super binds (Q, Tab, W, F): their own handler already asks the
-- steal list, so they need no wrap -- only the key has to count as occupied and
-- be listed for the panel. Everything else that is stealable is an Omarchy
-- command we unbind and replay: hyprctl prints those as __lua, so the command is
-- recovered from Omarchy's bind files.
local STEAL_OWN = { Q = true, TAB = true, F = true, W = true }
-- ...and every one of them is a key the pack binds itself (see pack_keys).
for id in pairs(STEAL_OWN) do
  pack_keys[id] = true
end
-- [id] = { keys, originals, handle } for wraps we installed on Omarchy keys.
local steal_wraps = {}
-- What the pack can replay of Omarchy's own binds: the command Omarchy wrote
-- (`omarchy_menu toggle ...`), read out of her files, since hyprctl prints
-- `__lua` for anything she bound as a Lua value and the behaviour is in her Lua
-- state, out of our reach.
--
-- The keys the pack bound itself are left out: what her file says used to be on
-- Cmd+Left (her focus) or Cmd+Backspace (window transparency) is not what the key
-- does here (a text chord), so a wrap on one of them has to replay the pack's own
-- chord -- which its handler does, and which is why those keys are offered through
-- lua_ok below and not through this map.
local omarchy_exec = nil
-- Omarchy's command for Super+Shift+T (Activity / btop). The key is pack-owned
-- for the panel, so it never lands in omarchy_exec; the reopen handler still
-- needs it for an app that does not take the key.
local reopen_activity = nil

local function ensure_omarchy_replay()
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
        -- Kept even though the key is pack-owned: the Shortcuts row, when off for
        -- this app, still has to launch Activity, and pack_keys hides that command
        -- from the steal list on purpose.
        if id == "SHIFT+T" and reopen_activity == nil then
          reopen_activity = cmd
        end
        if omarchy_exec[id] == nil and not pack_keys[id] then
          omarchy_exec[id] = cmd
        end
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
-- already wrapped at the source (Q, Tab, W, F). "Somewhere" is the desktop's list
-- plus every app's own Always on list -- an Always off list only takes a key away
-- from an app, and a key nothing steals needs no wrap. Iterated on every replan, so
-- the union is built here rather than kept in a set.
local function needed_steals()
  local set = {}
  local function add(id)
    if id ~= "Q" and id ~= "TAB" and id ~= "SHIFT+TAB" and id ~= "W" and id ~= "F" then
      set[id] = true
    end
  end
  for id in pairs(global_steal) do
    add(id)
  end
  for _, e in pairs(apps_cfg) do
    for id in pairs(e.ctrl_as_super_keys or {}) do
      add(id)
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

-- What the plan produced, next to the files the panel and the tests read. The
-- bind table itself is the nest's most contended socket -- the compositor, the
-- harness's own IPC proxy and this read all go through it -- so "did the plan
-- make binds" has to be answerable without asking it again. Written on every pass,
-- including the ones that bind nothing: a file that only a successful plan
-- rewrites keeps the last good numbers through a map that has been dropped, which
-- is how a dead Super as Ctrl looked healthy.
local function write_super_ctrl(planned, bound, keys)
  local out = io.open(X_MODE_STATE .. "/super-ctrl.json", "w")
  if out ~= nil then
    out:write(string.format('{"planned":%d,"bound":%d,"keys":%d}\n', planned, bound, keys))
    out:close()
  end
end

local function bind_super_ctrl(raw, gen)
  if gen ~= super_ctrl_gen then
    return
  end
  -- A bind table that did not land is not an answer: the writers that feed this
  -- (hyprctl, the panel's settings write) truncate before they write, so a read can
  -- catch half of one. Reading that as "nothing is occupied" blanked the panel's
  -- list, and reading the flags out of a torn settings file read as "Super as Ctrl
  -- is off" -- which, with the drop below, took the whole map away until the next
  -- reload: Cmd+Z stopped reaching every app.
  local valid = (raw or ""):find("modmask:%s*%d") ~= nil
  if valid then
    ensure_omarchy_replay()
    write_occupied(raw)
    apply_steal_wraps(raw)
  end
  if not key_flag_any("ctrl_as_super") then
    -- The user turned it off: the installed map has to go.
    drop_super_ctrl()
    write_super_ctrl(0, 0, 0)
    return
  end
  local plan = valid and supermap.plan(raw) or {}
  if #plan == 0 then
    -- On, but nothing planned: keep the map that is installed and let the next
    -- read try again, rather than dropping 32 binds to install none.
    return
  end
  -- A new plan replaces the last one instead of adding to it: the request that
  -- triggered it may have arrived while an earlier plan was already installed.
  drop_super_ctrl()
  local planned, bound = 0, 0
  for _, b in ipairs(plan) do
    -- The Shortcuts row owns Cmd+Shift+T once any app asks for it. A plan built
    -- from a snapshot taken before that bind landed still thinks the key is free,
    -- and a second bind would send the chord twice.
    if not (b.shift and b.key == "T" and key_flag_any("reopen_tab")) then
      local keys = b.shift and ("SUPER + SHIFT + " .. b.key) or ("SUPER + " .. b.key)
      -- `repeating`: a key that stays down keeps sending the chord, the way holding
      -- Cmd+D on a Mac keeps adding the next occurrence. The repeat has to be the
      -- bind's: `send_chord` hands over a whole chord and nothing held, so the app
      -- has no key of its own to repeat (and could only type the bare letter with).
      local ok, kb = pcall(hl.bind, keys, function()
        return super_ctrl_key(b.key, b.shift)
      end, { description = supermap.PREFIX .. (b.shift and " SHIFT" or "") .. " " .. b.key, repeating = true })
      planned = planned + 1
      if ok and kb then
        bound = bound + 1
        super_ctrl_binds[#super_ctrl_binds + 1] = kb
      end
    end
  end
  write_super_ctrl(planned, bound, #super_ctrl_binds)
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
      return
    end
    -- Twenty seconds without a table: report what is actually bound instead of
    -- leaving the last good numbers in a file the panel and the tests read as
    -- "the plan is fine".
    write_super_ctrl(0, 0, #super_ctrl_binds)
  end, { timeout = 200, type = "oneshot" })
end

apply_super_ctrl = function()
  -- The binds already installed stay until the new plan replaces them
  -- (bind_super_ctrl drops them right before it binds), and the file on disk is
  -- left alone until a fresh one has been written: a read that never lands -- an
  -- exec that fails, a machine that is busy -- then leaves the last good plan and
  -- the last good table in place instead of none of either. Clearing both first
  -- is what made "no binds" possible with a perfectly good table on disk.
  super_ctrl_gen = super_ctrl_gen + 1
  local path = X_MODE_STATE .. "/binds.txt"
  hl.exec_cmd("sh -c 'hyprctl binds > \"" .. path .. ".tmp\" 2>/dev/null && mv \"" .. path .. ".tmp\" \"" .. path .. "\"'")
  -- 200ms a try. `hyprctl binds` writes a table of several hundred lines, and the
  -- budget has to cover a loaded machine: ten tries (two seconds) ran out under a
  -- full suite, the read gave up, and no Super-as-Ctrl bind was ever made -- which
  -- looks exactly like a plan that refused to run. Twenty seconds, because a nest
  -- under load has been measured taking more than ten.
  super_ctrl_read(path, 100, super_ctrl_gen)
end

apply_super_ctrl()

-- The map lives in Hyprland's bind table, and a reload throws that away while the
-- replan is asynchronous. If the read that plans it never lands -- a busy machine,
-- a second reload -- nothing ever tries again: the map stays empty for the session
-- and Cmd+Z stops reaching every app, with no error anywhere. A window opening is
-- the event this hangs on (and the one a session cannot go long without), and a
-- five-second gap keeps it from hammering hyprctl while a read is in flight.
--
-- Not workspace.active: that one fires while the config is still loading, and
-- replanning there starved the shell's bring-up -- the bar of a nest never reserved
-- its top, so every slot died before a scenario could run.
-- Globals on purpose: the main chunk of this file is at Lua's limit of 200 locals,
-- and two more is all it took to make the whole config fail to parse (the bar never
-- came up and every nest died at bring-up). `luac -p` is in tests/lint.sh now.
super_ctrl_retry_at = 0
function super_ctrl_self_heal()
  if #super_ctrl_binds > 0 or not key_flag_any("ctrl_as_super") then
    return
  end
  local now = os.time()
  if now < super_ctrl_retry_at then
    return
  end
  super_ctrl_retry_at = now + 5
  apply_super_ctrl()
end

-- Workspace switching on F1..F10 instead of Super+1..0. Off is Omarchy's layout:
-- the pack does nothing. On, the digit binds (Omarchy writes them as
-- `SUPER + code:10..19`) are released and the pack takes the ten digits itself,
-- because the class of the focused window is what decides what a digit does (see
-- digit_key); the F keys switch the desktop's workspaces. Turning it back off
-- goes through a reload, which re-creates the Omarchy binds, so only the pack's
-- own binds have to go.
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

-- The digit with the workspaces on the F keys. The pack binds it itself, because
-- the answer is per class and can change while the pack runs: the card's reserve
-- switch claims the digit for the pack's own tab and eats it; else "Super works as
-- Ctrl" hands it over as Ctrl+digit; else the key is not ours and is passed
-- through. Nothing is claimed by default, so a fresh pack switches no tab. The
-- generated Super-as-Ctrl binds cannot carry the reserved half either: they exist
-- only while some app has that flag.
local function digit_name(index)
  if index == 10 then
    return "0"
  end
  return tostring(index)
end

local function digit_key(index)
  return function()
    local w = hl.get_active_window()
    local cls = w ~= nil and window_class(w) or nil
    if cls ~= nil and key_flag("digit_tabs", cls) then
      return focus_group_tab(index, true)
    end
    if cls ~= nil and key_flag("ctrl_as_super", cls) then
      send_ctrl(digit_name(index), false, w)
      return
    end
    return { pass_event = true }
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
    -- Tabs, not workspaces: the tenth digit is the 0 key, and the class of the
    -- focused window decides at press time what the digit does (digit_key).
    local digit = digit_name(i)
    add_workspace_key("SUPER + " .. digit, "Tab " .. i .. ", or Ctrl+" .. digit .. " for an app that asked", digit_key(i))
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

-- Cmd+Shift+T reopens the last closed tab (the app's Ctrl+Shift+T). Omarchy
-- puts Activity on that key, so it is not a free Super-as-Ctrl chord: the
-- Shortcuts row takes it, and only while some app has the flag. Off, the key is
-- put back to Activity. An app without the flag still gets Activity, the way a
-- stolen key keeps its original action everywhere else.
local reopen_tab_binds = {}
local reopen_took = false

local function drop_reopen_tab()
  for _, kb in ipairs(reopen_tab_binds) do
    pcall(function()
      kb:unbind()
    end)
  end
  reopen_tab_binds = {}
end

apply_reopen_tab = function()
  drop_reopen_tab()
  if not key_flag_any("reopen_tab") then
    if reopen_took then
      reopen_took = false
      ensure_omarchy_replay()
      if reopen_activity ~= nil and reopen_activity ~= "" then
        pcall(o.bind, "SUPER + SHIFT + T", "Activity", reopen_activity)
      end
    end
    return
  end
  if not reopen_took then
    hl.unbind("SUPER + SHIFT + T")
    local code = supermap.key_code("T")
    if code ~= nil then
      hl.unbind("SUPER + SHIFT + code:" .. tostring(code))
    end
    reopen_took = true
  end
  local ok, kb = pcall(hl.bind, "SUPER + SHIFT + T", function()
    local w = hl.get_active_window()
    if w ~= nil and key_flag("reopen_tab", window_class(w)) then
      send_ctrl("T", true, w)
      return
    end
    ensure_omarchy_replay()
    if reopen_activity ~= nil and reopen_activity ~= "" then
      hl.exec_cmd(reopen_activity)
    end
  end, { description = "Reopen closed tab" })
  if ok and kb then
    reopen_tab_binds[#reopen_tab_binds + 1] = kb
  end
end

function x_mode.refresh_options()
  load_options()
  apply_native_scroll()
  apply_compact_tabs()
  apply_ctrl_tab_switch()
  apply_no_gaps()
  apply_workspace_keys()
  apply_lock_key()
  apply_reopen_tab()
  -- The digits this took are occupied now, and the ones it gave back are free:
  -- the Super-as-Ctrl plan has to be read again or it would keep binding a key
  -- the pack has taken, and one press would run both.
  apply_super_ctrl()
end

load_options()
apply_native_scroll()
apply_compact_tabs()
apply_ctrl_tab_switch()
apply_no_gaps()
apply_workspace_keys()
apply_lock_key()
apply_reopen_tab()

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

function refresh_window(w)
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
  local _, uy, _, uh = layout.usable(mon)
  if uy == nil then
    return
  end
  local x, y = vec(w.at)
  local ww, wh = vec(w.size)
  local new_chrome = layout.chrome_h(w)
  local grow = math.max(new_chrome - (old_chrome or 0), 0)
  -- The window's own edge, from the plugin: on a No gaps workspace the gap and
  -- border are the workspace rule's 0 and 1, while GAP_OUT()/BORDER() still
  -- report the desktop's 10 and 2. Measuring the fit with those cut 22px off a
  -- snapped box and pushed it 11px down when a tab joined.
  local edge = layout.edge(w)
  if edge == nil then
    edge = GAP_OUT() + BORDER()
  end
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
  -- Tabs are the pack's, and the pack is only on its own workspaces: a window on
  -- a workspace Omarchy tiles, scrolls or floats itself stays a window.
  if not in_xmode(w) then
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
  local old_chrome = layout.chrome_h(peer)
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
  if w == nil or not in_xmode(w) then
    -- Omarchy's floating titlebar maximizes with this same mode. Undoing it
    -- there makes her fullscreen button look dead. Only the pack's windows
    -- are turned into its own snap.
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
  layout.snap("maximize", w)
end

hl.on("window.fullscreen", function(w)
  release_hypr_maximize(w)
end)

hl.on("window.open", function(w)
  -- The pack's float rule matches on the class, so a window on a workspace that is
  -- not the pack's opens floating and tagged; hand it back before anything else
  -- looks at it (grouping already refuses it, but the titlebar and the placement
  -- would not).
  pcall(claim_window, w)
  super_ctrl_self_heal()
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
  -- Hyprland 0.56.2 segfaults when a window that is still in a group unmaps: its
  -- unmapWindow runs CGroup::remove -> updateWindowVisibility -> CWindow::setInputBlocked
  -- with the window's surface already being destroyed (measured this session: nests
  -- died mid-run with exactly that stack, and every scenario after them on that nest
  -- read nonsense -- an ipc error, a monitor at 1763, windows that never mapped).
  -- window.close is emitted from the same function, a few lines *before* that removal,
  -- so taking the closing window out of its group here leaves nothing for the removal
  -- to walk. The window is going away either way; this only means the group does not
  -- have to be told about it during the teardown.
  if w ~= nil and w.group ~= nil then
    pcall(function()
      hl.dispatch(hl.dsp.window.move({ out_of_group = true, window = w }))
    end)
  end
  -- The restore point dies with the window: a later window at the same address
  -- must not inherit its box.
  layout.forget(w)
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
  -- The reserved top (the bar) is per monitor: a monitor coming or going is a
  -- frame change for the windows that moved with it.
  layout.frame_changed()
end)
hl.on("monitor.added", function(_)
  schedule_refit()
  layout.frame_changed()
end)
hl.on("monitor.layout_changed", function()
  schedule_refit()
  layout.frame_changed()
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
      layout.save(w)
    else
      flush_pending_joins()
      -- A pass held back by the drag (re-applying a zone would fight the
      -- gesture) runs now rather than at the next tick.
      layout.flush()
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
-- which is the moment its real width becomes known; the bar's layer is what
-- reserves the top, and a shell restart takes it away for a moment. Both are
-- frame changes, and layout.lua re-applies the windows that are on a zone when
-- the frame moves: this is what brings a window placed while the bar was away
-- back under the bar when the bar returns.
hl.on("layer.opened", function(layer)
  if layer ~= nil and layer.namespace == "x-mode-dock" then
    refresh_dock_card()
  end
  layout.frame_changed()
end)
hl.on("layer.closed", function(_)
  layout.frame_changed()
end)
hl.on("config.reloaded", function()
  refresh_dock_card()
  layout.frame_changed()
end)
refresh_dock_card()
layout.frame_changed()

-- Group every same-app window on a workspace into one group. Runs once after
-- the config loads: after an install/reload re-floats windows, or when several
-- same-app windows were opened while the config was reloading, they can end up
-- spread across separate groups. Pick a grouped window as the leader when there
-- is one, so the group keeps its position. only_id limits it to one workspace,
-- which is what a mode change wants: the others are not part of this deal.
function consolidate(only_id)
  local windows = as_list(hl.get_windows())
  if type(windows) ~= "table" then
    return
  end
  local by_class = {}
  for _, w in ipairs(windows) do
    local on_space = only_id == nil or tostring(ws_id(w)) == tostring(only_id)
    if on_space and not skip_group(w) then
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

-- The arrange and its marker are layout.lua's now: the marker is read, not
-- taken, and removed only once the deal has actually happened. Kept as a name
-- on x_mode so `hyprctl eval` can still ask for one deal by hand.
function x_mode.arrange()
  layout.arrange()
end


-- A reload in the middle of a fade leaves the windows at whatever step the
-- timers reached; those timers die with the config, so the state has to be put
-- back before anything else touches opacity. layout.lua owns the fade (and the
-- switch-over it hides), including the reveal and its deadline.
layout.clear_fade()

-- The restore points a previous parse wrote (theme switches and installs reload
-- the config; the windows do not move). Read before anything can ask for a
-- restore, and after this file's helpers exist, which is why it is here.
layout.load_restore()

-- The marker is dropped by install.sh before its reload and by the off path when
-- the desktop is switched back on. layout.lua owns it: it reads the marker,
-- starts the fade, and removes the marker only once the windows have actually
-- been dealt -- a parse that cannot deal (no plugin yet) keeps the request
-- instead of dropping it. This file asks once per load and gives it the tick.
local arrange_pending = layout.arrange_pending()

hl.timer(function()
  for _, w in ipairs(as_list(hl.get_windows())) do
    release_hypr_maximize(refresh_window(w) or w)
  end
  layout.settle(arrange_pending)
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
  hl.timer(layout.float_tiled, { timeout = 300, type = "oneshot" })
end

-- A load re-applies the zone box to every window that is still zone-shaped
-- (layout.resnap). Not with an arrange pending: that one deals every window into
-- the halves itself. The pass waits for the plugin like the others: on the first
-- parse of a session there is none yet, and it used to run into that and
-- silently do nothing.
if not arrange_pending then
  layout.resnap()
end

-- The alignment module, reachable from `hyprctl eval` (`x_mode.layout.state()`
-- says where each window was snapped from and what frame the zones were built
-- from). The panel and the binds go through the calls above, not this.
x_mode.layout = layout

-- --- workspace modes ---------------------------------------------------------
-- xmode is one of the modes Omarchy keeps per workspace, and the only one the
-- pack owns. Its float rules are generated, because a rule matches a workspace
-- range and the set of xmode workspaces changes while the session runs.

-- A rule's tags are listed with a trailing "*", so a strict compare passes them
-- over; the window's own list is what counts.
local function window_tagged(w, tag)
  for _, t in ipairs((w and w.tags) or {}) do
    if t == tag or t == tag .. "*" then
      return true
    end
  end
  return false
end

local function set_window_tag(w, tag, on)
  pcall(function()
    hl.dispatch(hl.dsp.window.tag({ tag = (on and "+" or "-") .. tag, window = w }))
  end)
end

local function windows_on(id)
  local out = {}
  for _, w in ipairs(as_list(hl.get_windows())) do
    local win = refresh_window(w) or w
    if win ~= nil and ws_id(win) == id then
      out[#out + 1] = win
    end
  end
  return out
end

-- The pack takes the workspace: its windows carry the tag, and the tiled ones are
-- floated. `place` is a mode change. The panel's switch-on deals the open windows
-- (one app centred, two or more split left and right, same-app windows already
-- one group), and arriving through the cycle or the menu has to do that same
-- deal -- restoring whatever box the previous layout left is how they came back
-- stacked. On a load the boxes are already the pack's and nothing moves.
local function enter_xmode(id, place)
  if no_gaps then
    no_gap_rule(id)
  end
  for _, win in ipairs(windows_on(id)) do
    if win.mapped and not win.hidden then
      if not win.floating then
        hl.dispatch(hl.dsp.window.float({ action = "enable", window = win }))
        win = refresh_window(win) or win
      end
      -- The rule that floats a new window tags it as well, so a window that came in
      -- that way must not get the tag twice (the second one is a plain tag next to
      -- the rule's starred one, and both are then read back).
      if not window_tagged(win, XMODE_TAG) then
        set_window_tag(win, XMODE_TAG, true)
      end
    end
  end
  if place then
    consolidate(id)
    layout.arrange(id)
  end
end

-- And gives it back: a tab is the pack's, not Omarchy's, so the group goes, then
-- the tag, and the window is tiled by whatever mode took the workspace over.
local function leave_xmode(id)
  -- Drop the no-gap rule before the windows tile, or dwindle lays them out
  -- with the gaps this workspace just left behind.
  clear_gap_rule(id)
  for _, win in ipairs(windows_on(id)) do
    if window_tagged(win, XMODE_TAG) then
      if win.group ~= nil then
        pcall(function()
          hl.dispatch(hl.dsp.window.move({ out_of_group = true, window = win }))
        end)
        win = refresh_window(win) or win
      end
      set_window_tag(win, XMODE_TAG, false)
      -- Floating is Omarchy's own mode. She has already arranged the window (her
      -- call runs before this one); tiling it here takes the titlebar's window
      -- away. Dwindle and scrolling do want it tiled.
      if modes.get(X_MODE_MODES, id) ~= "floating" and win.floating then
        hl.dispatch(hl.dsp.window.float({ action = "disable", window = win }))
      end
    end
  end
end

-- A window that just opened. The float rule matches on the class, so a window on a
-- workspace that is not the pack's arrives floating and tagged: this hands it back
-- to Omarchy, which tiles it, and takes the tag with it so no titlebar is drawn for
-- a window the pack does not own. Runs from window.open, before grouping.
claim_window = function(w)
  local win = refresh_window(w) or w
  if win == nil then
    return
  end
  local id = tonumber(ws_id(win))
  if id ~= nil and modes.is_xmode(X_MODE_MODES, id) then
    -- The pack's: tagged here, so the titlebar knows whose window it is, and
    -- floated in case the rule did not get to it (a window that came in before
    -- this handler ran).
    if not window_tagged(win, XMODE_TAG) then
      set_window_tag(win, XMODE_TAG, true)
    end
    if not win.floating then
      hl.dispatch(hl.dsp.window.float({ action = "enable", window = win }))
    end
    return
  end
  if id == nil then
    return
  end
  -- Omarchy's floating mode owns this window: it floated it and tagged it so her
  -- titlebar can draw. The pack's catch-all float rule is what made a window on
  -- a tiled workspace float, and handing that one back is tiling it. Doing the
  -- same here undoes the layout the click just chose, and the titlebar has
  -- nothing to sit on.
  if modes.get(X_MODE_MODES, id) == "floating" then
    return
  end
  -- Someone else's tiled workspace: hand it back. The float rule matches on the
  -- class, so it arrived floating, and there is no tag to take off -- the rule
  -- does not carry one.
  if win.floating then
    hl.dispatch(hl.dsp.window.float({ action = "disable", window = win }))
  end
end

local function apply_all_modes(place)
  local seen = {}
  for _, w in ipairs(as_list(hl.get_windows())) do
    local win = refresh_window(w) or w
    local id = tonumber(ws_id(win))
    if id ~= nil and not seen[id] then
      seen[id] = true
      if modes.is_xmode(X_MODE_MODES, id) then
        enter_xmode(id, place)
      else
        leave_xmode(id)
      end
    end
  end
end

-- The dock is a layer surface, so it belongs to the monitor and not to a
-- workspace: "the dock on xmode desktops only" is the dock hiding itself, and it
-- cannot read this Lua state. The active workspace's mode is published next to the
-- other files the shell reads, and Dock.qml watches it.
local ACTIVE_MODE_PATH = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/omarchy-x-mode.workspace"

-- forward-declared for the mode hook above
local publish_active_mode

publish_active_mode = function()
  local workspace = hl.get_active_workspace()
  -- The id is not always a number: the Lua workspace object can hand one out as a
  -- table, and `%s` then writes "table: 0x55a2..." into the line the dock reads.
  -- Dock.qml took the second field for the mode, so the dock hid itself on every
  -- xmode workspace and looked crashed. Read the id either way, and write a number.
  local id = workspace and (tonumber(workspace.id) or tonumber(workspace.name))
  local mode = "unknown"
  if id ~= nil then
    mode = modes.get(X_MODE_MODES, id) or "unknown"
  elseif X_MODE_MODES.default ~= nil then
    mode = X_MODE_MODES.default
  end
  local out = io.open(ACTIVE_MODE_PATH, "w")
  if out ~= nil then
    out:write(string.format("%s %s\n", tostring(id or 0), mode))
    out:close()
  end
end

local function apply_active_mode()
  publish_active_mode()
end

-- `input.follow_mouse` is Omarchy's as much as the pack's: its workspace modes set
-- 0 on their floating workspaces and put back the value they captured when they
-- started watching -- which is not the pack's 2, because this file runs later. So
-- the pack says it again on its own workspaces, both when the active workspace
-- changes and after every o.workspace_mode call (Omarchy's update_input runs inside
-- that call and puts its value back).
local function assert_follow_mouse()
  local workspace = hl.get_active_workspace()
  local id = workspace and workspace.id
  -- No workspace yet is the load path (Hyprland has not focused one when the
  -- config is parsed), and there the answer is the default mode: this is the
  -- desktop's own value, and every workspace without a mode of its own follows it.
  local ours = (id == nil and X_MODE_MODES.default == modes.XMODE) or (id ~= nil and modes.is_xmode(X_MODE_MODES, id))
  if not ours then
    return
  end
  hl.config({ input = { follow_mouse = 2 } })
end

hl.on("workspace.active", assert_follow_mouse)
hl.on("monitor.focused", assert_follow_mouse)
hl.on("window.active", assert_follow_mouse)
assert_follow_mouse()

hl.on("workspace.active", apply_active_mode)
hl.on("monitor.focused", apply_active_mode)
apply_active_mode()

hl.on("workspace.created", function(ws)
  local id = ws and tonumber(ws.id)
  if want_no_gap(id) then
    no_gap_rule(id)
  end
end)

-- Where the pack hears about a mode change. Omarchy's own function runs first (its
-- table, its rules, its tags); then the pack records the mode and hands the
-- workspace over or gives it back.
--
-- Her titlebars() loads a second hyprbars and, because this plugin is already
-- loaded, also writes her metrics and buttons into it. hl.plugin.load only
-- queues a plugin for the next config reload, so the click that floats a
-- workspace never brings her plugin in: it restyles every bar the pack draws
-- and leaves her windows with no bar of their own (the pack's tag is the only
-- one the bar used to check). Refuse that .so, and keep the look she asks for
-- beside the pack's instead of on top of it.
local in_omarchy_mode = false
local applying_tag = false

if hl.plugin and type(hl.plugin.load) == "function" then
  local load_plugin = hl.plugin.load
  hl.plugin.load = function(path)
    if type(path) == "string" and path:find("omarchy-hyprland-titlebars", 1, true) then
      return
    end
    return load_plugin(path)
  end
end

if type(hl.config) == "function" then
  local config = hl.config
  hl.config = function(spec)
    local hb = type(spec) == "table" and type(spec.plugin) == "table" and spec.plugin.hyprbars or nil
    if in_omarchy_mode and not applying_tag and type(hb) == "table" then
      if hb.workspace_tag ~= nil then
        applying_tag = true
        pcall(config, { plugin = { hyprbars = { workspace_tag = hb.workspace_tag } } })
        applying_tag = false
      end
      local bars = hl.plugin and hl.plugin.hyprbars
      if bars and bars.omarchy_style then
        bars.omarchy_style(hb)
      end
      return
    end
    return config(spec)
  end
end

do
  local bars = hl.plugin and hl.plugin.hyprbars
  if type(bars) == "table" and type(bars.add_button) == "function" and not bars._xmode_button_wrapped then
    local add_button = bars.add_button
    bars.add_button = function(button)
      if in_omarchy_mode then
        if bars.omarchy_button then
          return bars.omarchy_button(button)
        end
        -- An older plugin has no second list. Her three buttons would join the
        -- pack's one close button, and the bar draws every button it has: one
        -- small circle and her three big ones, on the same titlebar.
        return
      end
      return add_button(button)
    end
    bars._xmode_button_wrapped = true
  end
end

-- Omarchy's own file for a workspace, so her bar, her current-layout script and
-- the next login follow the mode. Only where she can replay it: on 4.0.x the
-- call is a config error, and the pack's record is the only one kept.
function mode_sync.write_workspace(id, mode)
  if not mode_sync.shared then
    return
  end
  local dir = workspace_layouts_dir()
  os.execute("mkdir -p " .. string.format("%q", dir))
  local file = io.open(dir .. "/" .. tostring(id) .. ".lua", "w")
  if file == nil then
    return
  end
  file:write(string.format('o.workspace_mode({ workspace = "%s", mode = "%s" })\n', tostring(id), mode))
  file:close()
end

-- Where the pack hears about a mode change. Two callers: Omarchy's own
-- o.workspace_mode, wrapped below, and the pack's `xmode` script, which on an
-- Omarchy without that function (4.0.x) cannot change a mode any other way.
function mode_sync.apply_default(mode)
  modes.set_default(X_MODE_MODES, mode)
  mode_sync.persist()
  -- Every workspace without a mode of its own just changed. The windows keep
  -- their boxes: this is not a placement, only who owns them.
  apply_all_modes(false)
  assert_follow_mouse()
  -- The dock reads the published mode. Changing the default does not move the
  -- focus, so workspace.active will not publish it.
  publish_active_mode()
end

function mode_sync.apply(id, mode)
  modes.set(X_MODE_MODES, id, mode)
  mode_sync.persist()
  if modes.is_xmode(X_MODE_MODES, id) then
    enter_xmode(id, true)
  else
    leave_xmode(id)
  end
  assert_follow_mouse()
  -- The dock watches the published mode, and switching the mode of the workspace
  -- already on screen fires no workspace.active: it has to be published here.
  publish_active_mode()
end

local omarchy_workspace_mode = o.workspace_mode

if type(omarchy_workspace_mode) == "function" then
  o.workspace_mode = function(spec)
    in_omarchy_mode = true
    local ok, err = pcall(omarchy_workspace_mode, spec)
    in_omarchy_mode = false
    if not ok then
      error(err, 0)
    end

    if type(spec) ~= "table" then
      return
    end

    if spec.default ~= nil then
      mode_sync.apply_default(spec.default)
      return
    end

    local id = tonumber(spec.workspace)
    if id == nil or spec.mode == nil then
      return
    end

    mode_sync.apply(id, spec.mode)
  end
end

-- The `xmode` script's way in on an Omarchy that has no o.workspace_mode
-- (4.0.x): there is no her setter to call, so the pack applies the mode and
-- records it itself. Used by the tests, the panel and `hyprctl eval` too.
x_mode.set_mode = function(workspace, mode)
  local id = tonumber(workspace)
  if id == nil or type(mode) ~= "string" or mode == "" then
    return false
  end
  mode_sync.apply(id, mode)
  return true
end

x_mode.set_default_mode = function(mode)
  if type(mode) ~= "string" or mode == "" then
    return false
  end
  mode_sync.apply_default(mode)
  return true
end

-- An install (and switching the pack back on) drops an arrange marker and deals
-- the open windows out as the pack's desktop. That deal floats them. The
-- titlebar is drawn only for the pack's tag, and the tag is applied only on an
-- xmode workspace, so a workspace that was still dwindle ended up floating with
-- no bar. Claim those workspaces before the deal: the mode file is what the
-- next login replays, and enter_xmode tags the windows that are already open.
local function arrange_marker_present()
  local file = io.open(X_MODE_STATE .. "/arrange", "r")
  if file == nil then
    return false
  end
  file:close()
  return true
end

function x_mode.claim_arranged()
  if not arrange_marker_present() then
    return
  end
  local seen = {}
  for _, w in ipairs(as_list(hl.get_windows())) do
    local win = refresh_window(w) or w
    local id = tonumber(ws_id(win))
    if id ~= nil and id >= 1 and not seen[id] then
      seen[id] = true
      if not modes.is_xmode(X_MODE_MODES, id) then
        mode_sync.write_workspace(id, modes.XMODE)
        modes.set(X_MODE_MODES, id, modes.XMODE)
      end
      enter_xmode(id, false)
    end
  end
  mode_sync.persist()
  publish_active_mode()
end

-- The modes were replayed before this file was required, so the windows that were
-- already open are in Omarchy's layout: on the pack's workspaces they are tagged
-- and floated here. New windows get both from the rule. An install's marker
-- claims the occupied workspaces first, so this pass tags them too.
x_mode.claim_arranged()
apply_all_modes(false)

-- The layout cycle is Omarchy's key with a fourth layout in it: the pack's own
-- xmode script walks dwindle -> scrolling -> floating -> xmode and writes the same
-- state files her toggle does, so the bar's glyph and the next login follow along.
do
  hl.unbind("SUPER + L")
  hl.unbind("SUPER + ALT + L")
  local path = X_MODE_DIR .. "xmode"
  -- Quoted here, not through Omarchy's o.shell_quote: Omarchy's keybindings scan
  -- loads this file with a stub `o` that has no such field, and the scan died on it.
  local bin = (o.shell_quote and o.shell_quote(path)) or ("'" .. path:gsub("'", "'\\''") .. "'")
  pcall(o.bind, "SUPER + L", "Cycle workspace layout", bin .. " next")
  pcall(o.bind, "SUPER + ALT + L", "Cycle workspace layout back", bin .. " back")
end

-- For the tests, the panel and `hyprctl eval`: which mode a workspace is in, and
-- whether it is the pack's.
x_mode.mode = function(workspace)
  return ws_mode(tonumber(workspace) or workspace)
end
x_mode.is_xmode = function(workspace)
  return modes.is_xmode(X_MODE_MODES, tonumber(workspace) or workspace)
end
-- The default, for the `xmode` script: on an Omarchy without mode files (4.0.x)
-- there is nothing on disk to read it back from.
x_mode.default_mode = function()
  return X_MODE_MODES.default
end
