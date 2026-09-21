-- omarchy-x-mode: the macOS-like desktop layer, single file.
--
-- Loaded from a sentinel block at the end of ~/.config/hypr/hyprland.lua:
--   -- >>> omarchy-x-mode >>>
--   dofile((os.getenv("HOME") or "") .. "/.config/hypr/x-mode.lua")
--   -- <<< omarchy-x-mode <<<
--
-- This file holds everything the pack needs to work (never "taste"): the
-- floating desktop, the Mac titlebar/tabbar (patched hyprbars), and the
-- Rectangle-style snap + same-app grouping engine. Personal look'n'feel
-- (input, monitors, decoration, native snap, ...) lives in a separate file the
-- pack does not own — see omarchy-x-vm/taste.lua — so uninstalling the pack
-- never removes it.

-- ---------------------------------------------------------------------------
-- Runtime on/off. The bar widget writes ~/.local/state/omarchy-x-mode/enabled
-- then runs `hyprctl reload`. Off skips the rest of this file so Omarchy's
-- binds, tiling and animations come back; the plugin stays loaded.
-- ---------------------------------------------------------------------------

local X_MODE_STATE = (os.getenv("HOME") or "") .. "/.local/state/omarchy-x-mode"

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
  for _, w in ipairs(hl.get_windows() or {}) do
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
    for _, w in ipairs(hl.get_windows() or {}) do
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
local GROUPBAR_FALLBACK = 24

hl.config({
  cursor = {
    -- Do not move the pointer when a window is focused (e.g. from the dock).
    no_warps = true,
  },
  input = {
    -- Click to focus: a window does not become active just because the pointer
    -- is over it.
    follow_mouse = 0,
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
o.window(".*", { float = true, opacity = "1.0 override 1.0 override" })
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
  local colors = {}
  for line in file:lines() do
    local key, value = line:match("^%s*([%w_%-]+)%s*=%s*(.-)%s*$")
    if key ~= nil and value ~= nil and value ~= "" then
      -- Strip an inline comment first: a TOML comment '#' must be preceded by
      -- whitespace, so this leaves '#rrggbb' color values intact.
      value = value:gsub("%s+#.*$", "")
      value = value:gsub('^"', ""):gsub('"$', ""):gsub("^'", ""):gsub("'$", "")
      colors[key] = value
    end
  end
  file:close()
  return colors
end

local function to_hypr_color(value)
  local v = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if v == "" then
    return nil
  end
  if v:match("^rgba?%(") then
    return v
  end
  local h = v:gsub("#", "")
  if #h == 3 then
    h = h:sub(1, 1):rep(2) .. h:sub(2, 2):rep(2) .. h:sub(3, 3):rep(2)
  end
  if #h < 6 then
    return nil
  end
  local r = tonumber(h:sub(1, 2), 16)
  local g = tonumber(h:sub(3, 4), 16)
  local b = tonumber(h:sub(5, 6), 16)
  if r == nil or g == nil or b == nil then
    return nil
  end
  return string.format("rgb(%d,%d,%d)", r, g, b)
end

local theme = omarchy_theme_colors()
local bar_bg = to_hypr_color(theme.background or theme.bg or theme.color0) or "rgb(55, 55, 58)"
local bar_fg = to_hypr_color(theme.foreground or theme.fg or theme.color7) or "rgb(255, 255, 255)"

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
local GROUPBAR          = cfg_int("plugin:hyprbars:tab_height", GROUPBAR_FALLBACK)
local GAP_OUT           = cfg_int("general:gaps_out", GAP_FALLBACK)
local BORDER            = cfg_int("general:border_size", 2)
-- The dock overlays windows (it reserves no screen space), so snap zones are
-- inset by the dock's visible width; keep plugin:hyprbars:x_mode_dock_inset in
-- sync with Dock.qml (iconSize + pad*2 + panel padding, minus the card margin).
local DOCK_INSET        = cfg_int("plugin:hyprbars:x_mode_dock_inset", 46)
local ALMOST_MAXIMIZE   = cfg_int("plugin:hyprbars:x_mode_almost_maximize_percent", 90) / 100
local GROUP_MIN_W       = cfg_int("plugin:hyprbars:x_mode_group_min_width", 400)
local GROUP_MIN_H       = cfg_int("plugin:hyprbars:x_mode_group_min_height", 300)

-- Open floating windows with the outer gap under the top bar. Hyprland measures
-- float_gaps from the work area (which already starts below the top bar) and
-- hyprbars draws its titlebar *above* the window box, so the titlebar lands at
-- float_gaps.top - TITLEBAR below the bar. Add the effective outer gap and the
-- border so the titlebar sits exactly at topbar + gap + border, and give the
-- other sides the same gap + border so a window never opens flush to an edge.
local FLOAT_EDGE = GAP_OUT + BORDER
hl.config({
  general = {
    float_gaps = {
      top = TITLEBAR + FLOAT_EDGE,
      left = FLOAT_EDGE,
      right = FLOAT_EDGE,
      bottom = FLOAT_EDGE,
    },
  },
})

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

local function reserved(monitor)
  local r = monitor.reserved
  if type(r) ~= "table" then
    return 0, 0, 0, 0
  end
  if r.left ~= nil then
    return r.left or 0, r.top or 0, r.right or 0, r.bottom or 0
  end
  return r[1] or 0, r[2] or 0, r[3] or 0, r[4] or 0
end

local function monitor_box(monitor)
  local scale = tonumber(monitor.scale) or 1
  if scale <= 0 then
    scale = 1
  end
  local x, y = monitor.x, monitor.y
  if x == nil then
    x, y = vec(monitor.position)
  end
  local width = (monitor.width or select(1, vec(monitor.size))) / scale
  local height = (monitor.height or select(2, vec(monitor.size))) / scale
  return x, y, width, height
end

local function usable(monitor)
  local left, top, right, bottom = reserved(monitor)
  right = right + DOCK_INSET
  local x, y, width, height = monitor_box(monitor)
  return x + left, y + top, width - left - right, height - top - bottom
end

local function window_class(w)
  if w == nil then
    return ""
  end
  return string.lower(tostring(w.initial_class or w.class or ""))
end

local function chrome_h(window)
  if window ~= nil then
    local e = apps_cfg and apps_cfg[window_class(window)]
    -- chrome=false → no titlebar/tabbar at all (mirrors Snap::chromeH's
    -- no_bar check in hyprbars/snap.cpp). Without this the Lua cycle branch
    -- of snap_or_expand added the bar height to a window that has no bar.
    if e and e.chrome == false then
      return 0
    end
  end
  local h = TITLEBAR
  if window ~= nil and window.group ~= nil then
    h = h + GROUPBAR
  elseif window ~= nil then
    local e = apps_cfg and apps_cfg[window_class(window)]
    if e and e.always_tabbar then
      h = h + GROUPBAR
    end
  end
  return h
end

local function with_chrome(x, y, w, h, window)
  local bar = chrome_h(window)
  return x, y + bar, w, h - bar
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

-- Fraction of the screen frame each action occupies, plus which raw edges
-- sit against a neighbouring window (those get half the inner gap).
local ZONES = {
  ["left"] = { h = "left", v = nil, hf = 0.5, vf = 1, inner = { r = true } },
  ["right"] = { h = "right", v = nil, hf = 0.5, vf = 1, inner = { l = true } },
  ["top"] = { h = nil, v = "top", hf = 1, vf = 0.5, inner = { b = true } },
  ["bottom"] = { h = nil, v = "bottom", hf = 1, vf = 0.5, inner = { t = true } },
  ["top-left"] = { h = "left", v = "top", hf = 0.5, vf = 0.5, inner = { r = true, b = true } },
  ["top-right"] = { h = "right", v = "top", hf = 0.5, vf = 0.5, inner = { l = true, b = true } },
  ["bottom-left"] = { h = "left", v = "bottom", hf = 0.5, vf = 0.5, inner = { r = true, t = true } },
  ["bottom-right"] = { h = "right", v = "bottom", hf = 0.5, vf = 0.5, inner = { l = true, t = true } },
  ["maximize"] = { h = nil, v = nil, hf = 1, vf = 1, inner = {} },
}

-- Rectangle's HalfSplitFrameCalculation, adapted to a top-left origin.
local function fractional_rect(frame, hside, vside, hf, vf)
  local w = math.floor(frame.w * hf + 0.0001)
  local h = math.floor(frame.h * vf + 0.0001)
  local x = frame.x
  local y = frame.y
  if hside == "right" then
    x = frame.x + frame.w - w
  end
  if vside == "bottom" then
    y = frame.y + frame.h - h
  end
  return x, y, w, h
end

-- Rectangle's GapCalculation. Every edge gets GAP_OUT: edges touching the screen
-- keep the full outer gap, edges shared with another window keep half, so two
-- snapped windows end up exactly GAP_OUT apart too. BORDER is added to every edge
-- because the border is drawn outside the box (see above), so the *visible* gap
-- equals GAP_OUT.
local function apply_gaps(x, y, w, h, inner)
  local half = math.floor(GAP_OUT / 2)
  local left = (inner.l and half or GAP_OUT) + BORDER
  local right = (inner.r and half or GAP_OUT) + BORDER
  local top = (inner.t and half or GAP_OUT) + BORDER
  local bottom = (inner.b and half or GAP_OUT) + BORDER
  return x + left, y + top, w - left - right, h - top - bottom
end

local function snap_geom(kind, monitor)
  local fx, fy, fw, fh = usable(monitor)
  if kind == "almost-maximize" then
    local w = math.floor(fw * ALMOST_MAXIMIZE + 0.5)
    local h = math.floor(fh * ALMOST_MAXIMIZE + 0.5)
    return fx + math.floor((fw - w) / 2 + 0.5), fy + math.floor((fh - h) / 2 + 0.5), w, h
  end
  local z = ZONES[kind]
  if z == nil then
    return nil
  end
  local x, y, w, h = fractional_rect({ x = fx, y = fy, w = fw, h = fh }, z.h, z.v, z.hf, z.vf)
  return apply_gaps(x, y, w, h, z.inner)
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
  local p = bars()
  if p and p.snap then
    p.snap({ kind = kind, window = window })
    return
  end
  local monitor = window.monitor or hl.get_monitor_at_cursor() or hl.get_active_monitor()
  if monitor == nil then
    return
  end
  local gx, gy, gw, gh = snap_geom(kind, monitor)
  if gx then
    gx, gy, gw, gh = with_chrome(gx, gy, gw, gh, window)
    place(gx, gy, gw, gh, window)
  end
end

local function almost(a, b, tol)
  return math.abs(a - b) <= (tol or 32)
end

-- Super+Alt+Left/Right: Rectangle default cycle sizes 1/2 → 2/3 → 1/3.
local CYCLE_HF = { 0.5, 2 / 3, 1 / 3 }

local function cycle_geom(side, hf, monitor)
  local fx, fy, fw, fh = usable(monitor)
  local inner = side == "left" and { r = true } or { l = true }
  local x, y, w, h = fractional_rect({ x = fx, y = fy, w = fw, h = fh }, side, nil, hf, 1)
  return apply_gaps(x, y, w, h, inner)
end

local function snap_or_expand(side)
  local window = hl.get_active_window()
  local monitor = hl.get_monitor_at_cursor() or hl.get_active_monitor()
  if window == nil or monitor == nil then
    return
  end

  local wx, wy = vec(window.at)
  local ww, wh = vec(window.size)
  for i, hf in ipairs(CYCLE_HF) do
    local zx, zy, zw, zh = cycle_geom(side, hf, monitor)
    local cx, cy, cw, ch = with_chrome(zx, zy, zw, zh, window)
    local on_left = almost(wx, cx) and almost(wy, cy) and almost(wh, ch) and almost(ww, cw)
    local on_right = almost(wx + ww, cx + cw) and almost(wy, cy) and almost(wh, ch) and almost(ww, cw)
    if (side == "left" and on_left) or (side == "right" and on_right) then
      local next_hf = CYCLE_HF[(i % #CYCLE_HF) + 1]
      local nx, ny, nw, nh = cycle_geom(side, next_hf, monitor)
      nx, ny, nw, nh = with_chrome(nx, ny, nw, nh, window)
      place(nx, ny, nw, nh, window)
      return
    end
  end
  snap(side, window)
end

-- Super+LMB window dragging is disabled in x-mode. Titlebar drag-to-edge
-- lives in hyprbars (CDragSession).
hl.unbind("SUPER + mouse:272")

-- Fit a floating window into the work area, keeping GAP_OUT + BORDER on every
-- side. Hyprland fits a floating window to the work area, but hyprbars draws its
-- titlebar *above* the window box (so the visual top is higher), and apps with an
-- explicit rule geometry ignore float_gaps. Nudge the window so its visual top,
-- content bottom and sides stay that far from the work-area edges, so nothing
-- hides under the bar and nothing opens flush to an edge.
-- Fit one floating window into the work area. Hyprland's resize is centered, so
-- a shrink would otherwise be paired with the *pre-resize* y and look like the
-- window jumped to the top (old y + new h overflowed the bottom clamp).
local function clamp_window(w)
  if w == nil or drag_owns(w) then
    return
  end
  if not (w.floating and w.mapped and not w.hidden and (not w.fullscreen or w.fullscreen == 0)) then
    return
  end
  local mon = w.monitor
  if mon == nil then
    return
  end
  local ux, uy, uw, uh = usable(mon)
  local x, y = vec(w.at)
  local ww, wh = vec(w.size)
  local edge = GAP_OUT + BORDER
  local chrome = 0
  if not apps_off[window_class(w)] then
    chrome = TITLEBAR
    if w.group ~= nil then
      chrome = chrome + GROUPBAR
    end
  end

  local max_w = uw - edge - edge
  local max_h = uh - edge - edge - chrome
  local nw = math.min(ww, max_w)
  local nh = math.min(wh, max_h)
  if nw ~= ww or nh ~= wh then
    hl.dispatch(hl.dsp.window.resize({ x = nw, y = nh, relative = false, window = w }))
    -- Resize is centered: re-read so we never clamp with a stale y.
    w = window_by_addr(w.address) or w
    x, y = vec(w.at)
    ww, wh = vec(w.size)
  end

  local min_top = uy + edge + chrome
  local max_bottom = uy + uh - edge
  local ny = y
  if ny < min_top then
    ny = min_top
  elseif ny + wh > max_bottom then
    ny = max_bottom - wh
    if ny < min_top then
      ny = min_top
    end
  end

  local min_left = ux + edge
  local max_right = ux + uw - edge
  local nx = x
  if nx < min_left then
    nx = min_left
  elseif nx + ww > max_right then
    nx = max_right - ww
  end

  if math.abs(x - nx) >= 1 or math.abs(y - ny) >= 1 then
    hl.dispatch(hl.dsp.window.move({ x = nx, y = ny, relative = false, window = w }))
  end
end

local function keep_below_topbar(window)
  if window ~= nil then
    clamp_window(window)
    return
  end
  for _, w in ipairs(hl.get_windows()) do
    clamp_window(w)
  end
end

-- keep_below_topbar is not polled: the drags clamp themselves (hyprbars in C++)
-- and Hyprland's own placement respects float_gaps. On window.open / join it
-- clamps only the window that changed. consolidate() still walks all windows
-- once after the config loads.

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

-- Raise + focus the most recently focused window of a class (any workspace;
-- focusing it also switches to its workspace).
local function switcher_focus(cls)
  local best = nil
  local best_focus = nil
  for _, w in ipairs(hl.get_windows()) do
    if tostring(w.class or "") == cls then
      local f = tonumber(w.focus_history_id) or 999999
      if best == nil or f < best_focus then
        best = w
        best_focus = f
      end
    end
  end
  if best ~= nil then
    hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = best }))
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
    for _, w in ipairs(hl.get_windows()) do
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
    -- Most recently focused first (like macOS Cmd+Tab).
    table.sort(entries, function(a, b)
      return a.focus < b.focus
    end)
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
  switcher_index = ((switcher_index - 1 + step) % n) + 1
  local cls = switcher_order[switcher_index]
  switcher_focus(cls)
  switcher_write("show " .. cls .. " " .. table.concat(switcher_tokens, " "))
end

local function switcher_hide()
  if not switcher_active then
    return
  end
  switcher_active = false
  switcher_order = {}
  switcher_index = 0
  switcher_write("hide")
end

-- Super (keycode 133/134 + 8) released: hide the switcher.
hl.on("input.keyboard.key", function(keycode, _, state)
  if switcher_active and state == 0 and (keycode == 133 or keycode == 134) then
    switcher_hide()
  end
end)

-- Restore Super+arrows to window focus (Omarchy default).
hl.unbind("SUPER + LEFT")
hl.unbind("SUPER + RIGHT")
o.bind("SUPER + LEFT", "Focus on left window", hl.dsp.focus({ direction = "l" }))
o.bind("SUPER + RIGHT", "Focus on right window", hl.dsp.focus({ direction = "r" }))

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

-- Cmd+W closes the active window (Omarchy's killactive). Closing the current
-- tab of a group makes Hyprland focus/raise a window outside the group, so the
-- plugin's close_window switches to the previous tab and raises it first. It is
-- the same helper the tabbar close button uses (hyprbars closeTabWindow), so the
-- two paths cannot drift apart.
hl.unbind("SUPER + W")
o.bind("SUPER + W", "Close window", function()
  local w = hl.get_active_window()
  if w == nil then
    return
  end
  local p = bars()
  if p and p.close_window then
    p.close_window(w)
  else
    hl.dispatch(hl.dsp.window.close({ window = w }))
  end
end)

-- Cmd+Q closes the whole app: all tabs of the group (like the titlebar close
-- button), or just the window when it is not grouped.
hl.unbind("SUPER + Q")
o.bind("SUPER + Q", "Close app", function()
  local w = hl.get_active_window()
  if w == nil then
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

-- Cmd+Tab cycles through windows (like an app switcher) instead of Omarchy's
-- next/previous workspace; Cmd+Shift+Tab goes the other way.
hl.unbind("SUPER + TAB")
hl.unbind("SUPER + SHIFT + TAB")
o.bind("SUPER + TAB", "Focus on next window", function()
  switcher_step(1)
end)
o.bind("SUPER + SHIFT + TAB", "Focus on previous window", function()
  switcher_step(-1)
end)

-- Alt+Tab switches between the tabs of the focused group (Omarchy binds it to
-- cyclenext, which we do not want). Set the group's active index directly (not
-- group.next(), which briefly focuses something else) and focus the target tab.
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
  local target = members[idx]
  hl.dispatch(hl.dsp.group.active({ index = idx, window = w }))
  -- Switching the tab focuses the target but does not raise it, so the group can
  -- stay behind another app; raise it first, then focus.
  hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = target }))
  hl.dispatch(hl.dsp.focus({ window = target }))
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

-- Per-app chrome: ~/.local/state/omarchy-x-mode/apps.json
-- { "class": { "chrome": true, "alwaysTabbar": false } }
-- chrome=false → no titlebar/tabbar/grouping. alwaysTabbar → tab strip even
-- when the window is not grouped. Missing entries mean chrome on.
local APPS_PATH = X_MODE_STATE .. "/apps.json"

local function load_apps()
  local file = io.open(APPS_PATH, "r")
  local raw = ""
  if file then
    raw = file:read("*a") or ""
    file:close()
  else
    -- Old list of chrome-off classes.
    local oldf = io.open(X_MODE_STATE .. "/apps-off.json", "r")
    if oldf then
      raw = oldf:read("*a") or ""
      oldf:close()
    end
  end
  local cfg = {}
  -- Object form: "class": { ... "chrome": false ... }
  for cls, body in raw:gmatch('"([^"]+)"%s*:%s*(%b{})') do
    local chrome = not body:find('"chrome"%s*:%s*false')
    local always = body:find('"alwaysTabbar"%s*:%s*true') ~= nil
    cfg[string.lower(cls)] = { chrome = chrome, always_tabbar = always }
  end
  -- Legacy array: ["class", ...] means chrome off.
  if next(cfg) == nil then
    for cls in raw:gmatch('"([^"]+)"') do
      cfg[string.lower(cls)] = { chrome = false, always_tabbar = false }
    end
  end
  return cfg
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

local nobar_applied = {}
local always_applied = {}

local function set_rule(name, cls, effect, on)
  pcall(function()
    hl.window_rule({
      name = name .. cls,
      enabled = on and true or false,
      match = { class = cls },
      [effect] = true,
    })
  end)
end

local function apply_apps()
  apps_cfg = load_apps()
  sync_apps_off()
  local seen_nobar, seen_always = {}, {}
  for cls, e in pairs(apps_cfg) do
    if e.chrome == false then
      seen_nobar[cls] = true
      set_rule("x-mode-nobar-", cls, "hyprbars:no_bar", true)
    end
    if e.always_tabbar and e.chrome ~= false then
      seen_always[cls] = true
      set_rule("x-mode-always-tabbar-", cls, "hyprbars:always_tabbar", true)
    end
  end
  for cls, _ in pairs(nobar_applied) do
    if not seen_nobar[cls] then
      set_rule("x-mode-nobar-", cls, "hyprbars:no_bar", false)
    end
  end
  for cls, _ in pairs(always_applied) do
    if not seen_always[cls] then
      set_rule("x-mode-always-tabbar-", cls, "hyprbars:always_tabbar", false)
    end
  end
  nobar_applied = seen_nobar
  always_applied = seen_always
end

local function ungroup_chrome_off()
  for _, w in ipairs(hl.get_windows() or {}) do
    if apps_off[window_class(w)] and w.group ~= nil then
      pcall(function()
        hl.dispatch(hl.dsp.window.move({ out_of_group = true, window = w }))
      end)
    end
  end
end

local function regroup_chrome_on()
  for _, w in ipairs(hl.get_windows() or {}) do
    if chrome_on(window_class(w)) then
      join_same_app(w)
    end
  end
end

apply_apps()
hl.timer(ungroup_chrome_off, { timeout = 250, type = "oneshot" })

x_mode = x_mode or {}
function x_mode.refresh_apps_off()
  apply_apps()
  ungroup_chrome_off()
  regroup_chrome_on()
end

-- Desktop options (native scroll). Written by the bar panel.
-- Ctrl+1..9 switches group tabs when the focused app has chrome/titlebar on;
-- otherwise the key is passed through to the app. Cmd+1..9 stay as Omarchy
-- workspace binds.
local OPTIONS_PATH = X_MODE_STATE .. "/options.json"
local native_scroll = false

local function load_options()
  native_scroll = false
  local file = io.open(OPTIONS_PATH, "r")
  if not file then
    return
  end
  local raw = file:read("*a") or ""
  file:close()
  if raw:find('"nativeScroll"%s*:%s*true') then
    native_scroll = true
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
  local target = members[index]
  hl.dispatch(hl.dsp.group.active({ index = index, window = w }))
  if target ~= nil then
    hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = target }))
    hl.dispatch(hl.dsp.focus({ window = target }))
  end
  return { pass_event = false }
end

for i = 1, 9 do
  o.bind("CTRL + code:" .. tostring(i + 9), "Switch to tab " .. i, function()
    return focus_group_tab(i)
  end)
end

function x_mode.refresh_options()
  load_options()
  apply_native_scroll()
end

load_options()
apply_native_scroll()

local function skip_group(w)
  if w == nil or w.pinned or w.hidden then
    return true
  end
  local class = window_class(w)
  if apps_off[class] then
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
  local x, y = vec(w.at)
  local ww, wh = vec(w.size)
  local new_chrome = chrome_h(w)
  local grow = math.max(new_chrome - (old_chrome or 0), 0)
  local edge = GAP_OUT + BORDER
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
  local windows = hl.get_windows()
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
  -- Ungrouped windows that ignore float_gaps can land under the top bar.
  -- Grouped ones already have their position from join_same_app; clamping
  -- them here would pin the whole group to the top.
  hl.timer(function()
    local cur = refresh_window(w)
    if cur and cur.group == nil then
      keep_below_topbar(cur)
    end
  end, { timeout = 60, type = "oneshot" })
  hl.timer(function()
    local cur = refresh_window(w)
    if cur and cur.group == nil then
      keep_below_topbar(cur)
    end
  end, { timeout = 200, type = "oneshot" })
end)

hl.on("window.close", function(w)
  local key = hide_key(w)
  if key == nil then
    return
  end
  pending_join[key] = nil
  hidden_for_join[key] = nil
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

-- Group every same-app window on a workspace into one group. Runs once after
-- the config loads: after an install/reload re-floats windows, or when several
-- same-app windows were opened while the config was reloading, they can end up
-- spread across separate groups. Pick a grouped window as the leader when there
-- is one, so the group keeps its position.
local function consolidate()
  local windows = hl.get_windows()
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
  -- Only nudge ungrouped windows under the top bar. A full walk with
  -- clamp_window resizes groups and pins them to the top after reload.
  for _, w in ipairs(windows) do
    if w.group == nil then
      keep_below_topbar(w)
    end
  end
end

hl.timer(function()
  consolidate()
end, { timeout = 250, type = "oneshot" })

pcall(function()
  if hl.plugin and hl.plugin.hyprbars and hl.plugin.hyprbars.x_mode then
    hl.plugin.hyprbars.x_mode(true)
  end
end)

-- Catch-all float rule only applies to windows created after this config
-- loads; re-float anything still tiled (same as install.sh).
hl.timer(function()
  for _, w in ipairs(hl.get_windows() or {}) do
    if w.mapped and not w.floating and (not w.fullscreen or w.fullscreen == 0) then
      hl.dispatch(hl.dsp.window.float({ action = "enable", window = w }))
    end
  end
end, { timeout = 300, type = "oneshot" })
