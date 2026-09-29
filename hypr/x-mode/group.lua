-- Classes that are never same-app tabs. Pure: no Hyprland, so tests/unit can
-- load it. The plugin refuses the same classes in hyprbars.groupable
-- (main.cpp); this is the list Lua asks before it looks for a peer, and the
-- one it uses to pull an already-grouped window back out on load.
--
-- A nested Hyprland's wayland toplevel is class aquamarine (the backend's app
-- id). Some builds still report Hyprland. They keep the titlebar — a click on
-- it focuses that window. This is only the grouping exception. Chrome-off in
-- the panel is a separate switch and also removes the bar.
local M = {}

local NEVER = {
  aquamarine = true,
  hyprland = true,
}

function M.never_group(class)
  return NEVER[string.lower(tostring(class or ""))] == true
end

return M
