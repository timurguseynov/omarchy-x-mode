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

dofile(os.getenv("X_MODE_LUA") or ((os.getenv("HOME") or "") .. "/.config/hypr/x-mode.lua"))
