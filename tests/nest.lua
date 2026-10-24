-- Nest config for the x-mode test suite: the real x-mode.lua in a nested
-- Hyprland, so snap/group/no-gaps/focus can be exercised without touching the
-- live session.
--
-- $X_MODE_LUA   x-mode.lua to load (tests/lib.sh points it at the repo copy)
-- $X_MODE_STATE state directory for the nest
-- helpers.lua defines the `o.*` the pack uses; nothing else from Omarchy is
-- needed for the desktop layer itself.
--
-- helpers.lua loads its own modules with require("default.hypr.paths"), and only
-- bootstrap.lua puts $OMARCHY_PATH/?.lua on package.path, so the bootstrap has to
-- run first: the live config starts with the same dofile (~/.config/hypr/
-- hyprland.lua), and this is the one line that makes the nest load the way the
-- desktop does. Without it the config dies inside helpers.lua, and every
-- statement below -- the geometry, the planted binds, the pack itself -- is
-- skipped, which shows up as nest scenarios failing (or passing on the plugin
-- alone, with no pack loaded).
o = o or {}
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/helpers.lua")

-- The nest's output is a window on the host, and it came up with whatever scale
-- the host handed the toplevel -- two, on this machine -- which made every
-- coordinate and every size in these scenarios half of what they say: a 900x1000
-- nest was 450x500 logical, so a window that should fill it could not, a default
-- 700x500 client was clamped to fit, and the bar's own reserved area came out at
-- 62 instead of its 24. Pinned to 1, the nest is the size it claims to be and the
-- geometry scenarios measure the desktop's own arithmetic.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

hl.config({
  -- The same general values Omarchy's looknfeel.lua sets, so the snap geometry
  -- here matches the real desktop (x-mode.lua does not set gaps itself).
  general = { gaps_in = 5, gaps_out = 10, border_size = 2 },
  decoration = { rounding = 0 },
  animations = { enabled = false },
  misc = { disable_hyprland_logo = true },
})

-- Omarchy binds these. The nest does not load default/hypr/bindings, so plant
-- them before x-mode: the pack must unbind them, and the unbound-key tests
-- check they are gone.
o.bind("SUPER + LEFT", "Focus on left window", hl.dsp.focus({ direction = "l" }))
o.bind("SUPER + RIGHT", "Focus on right window", hl.dsp.focus({ direction = "r" }))
o.bind("SUPER + UP", "Focus on above window", hl.dsp.focus({ direction = "u" }))
o.bind("SUPER + DOWN", "Focus on below window", hl.dsp.focus({ direction = "d" }))
o.bind("SUPER + G", "Toggle window grouping", hl.dsp.group.toggle())
o.bind("SUPER + ALT + G", "Move active window out of group", hl.dsp.window.move({ out_of_group = true }))
o.bind("SUPER + S", "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
o.bind("SUPER + ALT + S", "Move window to scratchpad", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))
-- Omarchy writes the workspace digits by keycode (code:12 is the 3 key). The
-- pack takes Cmd+Shift+3..6 for its screenshot keys, so the keycode spellings
-- of the window moves have to be dropped for the keys it takes. The plain 3 is
-- planted too: while Omarchy's workspace key owns it, the pack must leave the
-- digit to the desktop rather than switching its own tabs with it.
o.bind("SUPER + code:12", "Switch to workspace 3", hl.dsp.no_op())
o.bind("SUPER + SHIFT + code:12", "Move window to workspace 3", hl.dsp.window.move({ workspace = "3" }))
o.bind("SUPER + SHIFT + code:13", "Move window to workspace 4", hl.dsp.window.move({ workspace = "4" }))
o.bind("SUPER + SHIFT + code:14", "Move window to workspace 5", hl.dsp.window.move({ workspace = "5" }))
o.bind("SUPER + SHIFT + code:15", "Move window to workspace 6", hl.dsp.window.move({ workspace = "6" }))
-- Omarchy's Calculator sits on Ctrl+Cmd+Q, which is where macOS puts Lock Screen.
-- The pack takes that one key for the lock when its option is on, so the key has
-- to be occupied here for the scenario to see who holds it.
o.bind("SUPER + CTRL + Q", "Calculator", "omarchy-menu toggle trigger.app.calculator")
-- Omarchy's browser defaults, as the desktop writes them: chromium-based apps are
-- tagged, and the tag rule then forces them to tile and to opt out of the
-- desktop's opacity. A tag is added while the window opens, so that rule is
-- applied after the pack's catch-all and wins where the two disagree -- which is
-- why the pack carries a browser rule of its own.
o.window("footbrowser", { tag = "+chromium-based-browser" })
o.window({ tag = "chromium-based-browser" }, { tag = "-default-opacity", tile = true, opacity = "1.0 0.985" })
-- Omarchy's own gaps toggle. The pack owns the gaps (the panel's "No gaps"), so
-- its key has to come out; the bind is planted here so the scenario can tell
-- "the pack took it away" from "the nest never had it".
o.bind("SUPER + SHIFT + BACKSPACE", "Toggle window gaps", "omarchy-hyprland-window-gaps-toggle")

-- Omarchy sources every file in the permanent-toggle directory on each load, after
-- its look and feel and before the pack. The nest does the same, so a scenario can
-- plant one (its own gaps toggle, say) and see its real effect, which is what the
-- pack has to notice and retire.
do
  local dir = (os.getenv("HOME") or "") .. "/.local/state/omarchy/toggles/hypr"
  local listing = io.popen("ls " .. dir .. "/*.lua 2>/dev/null")
  if listing ~= nil then
    for path in listing:lines() do
      dofile(path)
    end
    listing:close()
  end
end

-- Omarchy's titlebars module queues its own hyprbars the moment a workspace
-- floats. The pack's plugin is already that hyprbars; a second copy reloads the
-- config and the two decorations fight. Drop the queue before workspace-modes
-- runs, on a reload as well as the first parse. x-mode.lua wraps the same call
-- again for a click that happens after this file.
do
  local ok, load_plugin = pcall(function() return hl.plugin.load end)
  if ok and type(load_plugin) == "function" then
    hl.plugin.load = function(path)
      if type(path) == "string" and path:find("omarchy-hyprland-titlebars", 1, true) then
        return
      end
      return load_plugin(path)
    end
  end
end

-- Workspace modes. Omarchy keeps one per workspace in
-- $XDG_STATE_HOME/omarchy/workspace-layouts and replays those files while the
-- config loads, before the pack is required; the pack adds its own, xmode, and
-- owns it. The nest is in xmode for every workspace that does not say otherwise,
-- which is what every scenario here assumes -- a window that opens is the pack's
-- floating window. A scenario switches one workspace to dwindle (or scrolling,
-- or floating) to see the pack step aside there.
require("default.hypr.workspace-modes")
do
  local state_home = os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")
  local dir = state_home .. "/omarchy/workspace-layouts"
  os.execute("mkdir -p '" .. dir .. "'")
  -- Both the default and workspace 1 by name: the default covers every workspace
  -- that has no mode of its own, and 1 is written out explicitly so a scenario that
  -- reloads cannot depend on the default still being the one this file set.
  local file = io.open(dir .. "/default.lua", "w")
  if file ~= nil then
    file:write('o.workspace_mode({ default = "xmode" })\n')
    file:close()
  end
  local one = io.open(dir .. "/1.lua", "w")
  if one ~= nil then
    one:write('o.workspace_mode({ workspace = "1", mode = "xmode" })\n')
    one:close()
  end
end
o.workspace_mode({ default = "xmode" })

dofile(os.getenv("X_MODE_LUA") or ((os.getenv("HOME") or "") .. "/.config/hypr/x-mode/x-mode.lua"))
