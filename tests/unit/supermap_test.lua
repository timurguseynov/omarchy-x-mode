-- supermap.lua is pure, so this runs with plain lua: no Hyprland, no hyprctl.
local repo = os.getenv("X_MODE_REPO") or "."
local supermap = dofile(repo .. "/hypr/x-mode/supermap.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    io.stderr:write(string.format("FAIL %s: got %s, want %s\n", name, tostring(got), tostring(want)))
    failures = failures + 1
  end
end

-- The plan is a list; index it as "<key>/<plain|shift>" for the checks.
local function index(plan)
  local set = {}
  for _, b in ipairs(plan) do
    set[b.key .. "/" .. (b.shift and "shift" or "plain")] = true
  end
  return set
end

-- The keysym list has to carry the keys the app shortcuts need, in the spelling
-- bind strings use.
local function has_key(list, key)
  for _, k in ipairs(list) do
    if k == key then
      return true
    end
  end
  return false
end
check("keys.letter", has_key(supermap.KEYS, "T"), true)
check("keys.nav", has_key(supermap.KEYS, "LEFT"), true)
check("keys.punct", has_key(supermap.KEYS, "comma"), true)

-- A bind table shaped like `hyprctl -j binds`:
--   SUPER + T        occupied (Omarchy)
--   SUPER + SHIFT + N occupied
--   SUPER + ALT + LEFT  a different modmask, so LEFT stays free
--   SUPER + H        only inside a submap, so free at the top level
--   SUPER + L        one of ours (the description marks it), so free as well
--   SUPER + code:20  a raw keycode bind, no key name to match against
local raw = [[
[
  {"modmask": 64, "submap": "", "key": "T", "keycode": 0, "catch_all": false, "description": "", "dispatcher": "exec", "arg": "x"},
  {"modmask": 65, "submap": "", "key": "N", "keycode": 0, "catch_all": false, "description": "", "dispatcher": "exec", "arg": "x"},
  {"modmask": 72, "submap": "", "key": "LEFT", "keycode": 0, "catch_all": false, "description": "", "dispatcher": "exec", "arg": "x"},
  {"modmask": 64, "submap": "resize", "key": "H", "keycode": 0, "catch_all": false, "description": "", "dispatcher": "submap", "arg": "reset"},
  {"modmask": 64, "submap": "", "key": "L", "keycode": 0, "catch_all": false, "description": "x-mode-super-ctrl L", "dispatcher": "__lua", "arg": "1"},
  {"modmask": 64, "submap": "", "key": "code:20", "keycode": 20, "catch_all": false, "description": "", "dispatcher": "exec", "arg": "x"}
]
]]

local set = index(supermap.plan(raw))
check("plan.t.occupied", set["T/plain"], nil)
check("plan.t.shift.free", set["T/shift"], true)
check("plan.n.occupied", set["N/shift"], nil)
check("plan.n.plain.free", set["N/plain"], true)
check("plan.nav.other-mods", set["LEFT/plain"], true)
check("plan.submap.ignored", set["H/plain"], true)
check("plan.own.ignored", set["L/plain"], true)

-- No binds at all: every key is free.
local empty_plan = index(supermap.plan("[]"))
check("plan.empty.t", empty_plan["T/plain"], true)
check("plan.empty.t.shift", empty_plan["T/shift"], true)
check("plan.empty.punct", empty_plan["comma/plain"], true)

-- Punctuation gets no Shift variant: the shifted keysym is a different key, so
-- the bind would never match.
check("plan.punct.no-shift", empty_plan["comma/shift"], nil)

-- Junk input plans nothing rather than raising.
check("plan.junk", #supermap.plan("not json"), 0)

if failures > 0 then
  os.exit(1)
end
print("supermap ok")
