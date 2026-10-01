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
-- The keycode `send_shortcut` sends for a name, so a Cyrillic layout (where the
-- name does not resolve) still gets the physical key.
check("code.W", supermap.key_code("W"), 25)
check("code.digit", supermap.key_code("1"), 10)
check("code.tab", supermap.key_code("TAB"), 23)
check("code.unknown", supermap.key_code("nope"), nil)
check("code.nil", supermap.key_code(nil), nil)

-- A bind table shaped like `hyprctl binds` prints them:
--   SUPER + T           occupied (Omarchy)
--   SUPER + SHIFT + N   occupied
--   SUPER + ALT + LEFT  a different modmask, so LEFT stays free
--   SUPER + H           only inside a submap, so free at the top level
--   SUPER + L           one of ours (the description marks it), so free as well
--   SUPER + code:20     the minus key, written by keycode
--   SUPER + code:10     and its Shift form: Omarchy's workspace binds are
--                       written this way, so SUPER+1 is taken even though no
--                       bind above names the key "1"
local raw = [[
bind
	modmask: 64
	submap: 
	key: T
	keycode: 0
	catchall: false
	description: 
	dispatcher: exec
	arg: x

bind
	modmask: 65
	submap: 
	key: N
	keycode: 0
	catchall: false
	description: 
	dispatcher: exec
	arg: x

bind
	modmask: 72
	submap: 
	key: LEFT
	keycode: 0
	catchall: false
	description: 
	dispatcher: exec
	arg: x

bind
	modmask: 64
	submap: resize
	key: H
	keycode: 0
	catchall: false
	description: 
	dispatcher: submap
	arg: reset

bind
	modmask: 64
	submap: 
	key: L
	keycode: 0
	catchall: false
	description: x-mode-super-ctrl L
	dispatcher: __lua
	arg: 1

bind
	modmask: 64
	submap: 
	key: SUPER + code:20
	keycode: 0
	catchall: false
	description: 
	dispatcher: __lua
	arg: 2

bind
	modmask: 64
	submap: 
	key: SUPER + code:10
	keycode: 0
	catchall: false
	description: 
	dispatcher: __lua
	arg: 3

bind
	modmask: 65
	submap: 
	key: SUPER + code:10
	keycode: 0
	catchall: false
	description: 
	dispatcher: __lua
	arg: 4
]]

local set = index(supermap.plan(raw))
check("plan.t.occupied", set["T/plain"], nil)
check("plan.t.shift.free", set["T/shift"], true)
check("plan.n.occupied", set["N/shift"], nil)
check("plan.n.plain.free", set["N/plain"], true)
check("plan.nav.other-mods", set["LEFT/plain"], true)
check("plan.submap.ignored", set["H/plain"], true)
check("plan.own.ignored", set["L/plain"], true)
check("plan.code.minus", set["minus/plain"], nil)
check("plan.code.digit", set["1/plain"], nil)
check("plan.code.digit.shift", set["1/shift"], nil)

-- No binds at all: every key is free.
local empty_plan = index(supermap.plan("bind\n\tmodmask: 4\n\tkey: X\n\n"))
check("plan.empty.t", empty_plan["T/plain"], true)
check("plan.empty.t.shift", empty_plan["T/shift"], true)
check("plan.empty.punct", empty_plan["comma/plain"], true)

-- Punctuation gets no Shift variant: the shifted keysym is a different key, so
-- the bind would never match.
check("plan.punct.no-shift", empty_plan["comma/shift"], nil)

-- Junk input plans nothing rather than raising.
check("plan.junk", #supermap.plan("not a bind table"), 0)

if failures > 0 then
  os.exit(1)
end
print("supermap ok")
