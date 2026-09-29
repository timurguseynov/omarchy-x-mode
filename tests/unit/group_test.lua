-- group.lua is pure, so this runs with plain lua: no Hyprland, no compositor.
local repo = os.getenv("X_MODE_REPO") or "."
local group = dofile(repo .. "/hypr/x-mode/group.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    io.stderr:write(string.format("FAIL %s: got %s, want %s\n", name, tostring(got), tostring(want)))
    failures = failures + 1
  end
end

-- A nested Hyprland toplevel is class aquamarine. Some builds still report
-- Hyprland. Either way it is never a same-app tab. The match is the class
-- only, and it is case-insensitive: the stored comparison lowercases.
check("aquamarine", group.never_group("aquamarine"), true)
check("Aquamarine", group.never_group("Aquamarine"), true)
check("hyprland", group.never_group("hyprland"), true)
check("Hyprland", group.never_group("Hyprland"), true)

check("foot", group.never_group("foot"), false)
check("empty", group.never_group(""), false)
check("nil", group.never_group(nil), false)
check("prefix", group.never_group("aquamarine-extra"), false)

if failures > 0 then
  os.exit(1)
end
print("group ok")
