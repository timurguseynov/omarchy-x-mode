-- Nest config for the x-mode test suite: the real x-mode.lua in a nested
-- Hyprland, so snap/group/no-gaps/focus can be exercised without touching the
-- live session.
--
-- $X_MODE_LUA   x-mode.lua to load (tests/lib.sh points it at the repo copy)
-- $X_MODE_STATE state directory for the nest
-- helpers.lua defines the `o.*` the pack uses; nothing else from Omarchy is
-- needed for the desktop layer itself.
o = o or {}
dofile("/usr/share/omarchy/default/hypr/helpers.lua")

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

dofile(os.getenv("X_MODE_LUA") or ((os.getenv("HOME") or "") .. "/.config/hypr/x-mode.lua"))
