-- values.lua is pure, so this runs with plain lua: no Hyprland, no compositor.
local repo = os.getenv("X_MODE_REPO") or "."
local values = dofile(repo .. "/hypr/x-mode/values.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    io.stderr:write(string.format("FAIL %s: got %s, want %s\n", name, tostring(got), tostring(want)))
    failures = failures + 1
  end
end

local kept = { 1, 2 }
check("list.array", values.as_list(kept), kept)
check("list.empty", next(values.as_list({})), nil)
check("list.nil", next(values.as_list(nil)), nil)
check("list.map", next(values.as_list({ x = 1 })), nil)
check("list.text", next(values.as_list("nope")), nil)

check("cfg.missing", values.cfg_int(nil, 7), 7)
check("cfg.number", values.cfg_int(3.9, 7), 3)
check("cfg.top", values.cfg_int({ top = 10 }, 7), 10)
check("cfg.slot", values.cfg_int({ 4 }, 7), 4)
check("cfg.text", values.cfg_int("12px", 7), 12)
check("cfg.junk", values.cfg_int("nope", 7), 7)
-- Only false and nil fall through. A zero top is a real gap and stays zero.
check("cfg.zero-top", values.cfg_int({ top = 0 }, 7), 0)

local x, y = values.vec({ x = 1, y = 2 })
check("vec.xy", x .. "," .. y, "1,2")
x, y = values.vec({ x = 1 })
check("vec.x-only", x .. "," .. y, "1,0")
x, y = values.vec({ w = 3, h = 4 })
check("vec.wh", x .. "," .. y, "3,4")
x, y = values.vec({ 8, 9 })
check("vec.array", x .. "," .. y, "8,9")
x, y = values.vec(nil)
check("vec.nil", x .. "," .. y, "0,0")

if failures > 0 then
  os.exit(1)
end
print("values ok")
