-- mru.lua is pure, so this runs with plain lua: no Hyprland, no compositor.
local repo = os.getenv("X_MODE_REPO") or "."
local mru = dofile(repo .. "/hypr/x-mode/mru.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    io.stderr:write(string.format("FAIL %s: got %s, want %s\n", name, tostring(got), tostring(want)))
    failures = failures + 1
  end
end

-- touch moves the class to the front, without duplicates.
local list = {}
mru.touch(list, "foot")
mru.touch(list, "kitty")
mru.touch(list, "foot")
check("touch.order", table.concat(list, ","), "foot,kitty")
check("touch.no-duplicate", #list, 2)
mru.touch(list, "")
check("touch.empty-ignored", #list, 2)
mru.touch(list, nil)
check("touch.nil-ignored", #list, 2)

-- step wraps in both directions.
check("step.forward", mru.step(1, 3, 1), 2)
check("step.forward-wrap", mru.step(3, 3, 1), 1)
check("step.back", mru.step(1, 3, -1), 3)
check("step.back-wrap", mru.step(2, 3, -1), 1)
check("step.empty", mru.step(1, 0, 1), 1)

-- sort: the MRU list ranks first, focus breaks ties for the rest.
local entries = {
  { cls = "a", focus = 5 },
  { cls = "b", focus = 1 },
  { cls = "c", focus = 2 },
}
mru.sort(entries, { "c", "a" })
local ordered = entries[1].cls .. "," .. entries[2].cls .. "," .. entries[3].cls
check("sort.mru-first", ordered, "c,a,b")

local fresh = { { cls = "a", focus = 5 }, { cls = "b", focus = 1 } }
mru.sort(fresh, {})
check("sort.focus-tiebreak", fresh[1].cls .. "," .. fresh[2].cls, "b,a")

if failures > 0 then
  os.exit(1)
end
print("mru ok")
