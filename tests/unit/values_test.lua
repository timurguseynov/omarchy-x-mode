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

check("class.nil", values.window_class(nil), "")
check("class.initial", values.window_class({ initial_class = "Foot", class = "Other" }), "foot")
check("class.fallback", values.window_class({ class = "KITTY" }), "kitty")
check("class.empty", values.window_class({}), "")

check("tag.nil", values.window_tagged(nil, "xmode"), false)
check("tag.plain", values.window_tagged({ tags = { "xmode" } }, "xmode"), true)
check("tag.star", values.window_tagged({ tags = { "xmode*" } }, "xmode"), true)
check("tag.other", values.window_tagged({ tags = { "other" } }, "xmode"), false)

check("addr.plain", values.addr_sel({ address = "abc" }), "address:abc")
check("addr.prefixed", values.addr_sel({ address = "address:abc" }), "address:abc")
check("addr.missing-address", values.addr_sel({}), "address:nil")
-- Still the old contract: callers hand over a window that has an address.
check("addr.nil-window", (pcall(values.addr_sel, nil)), false)

check("hide.plain", values.hide_key({ address = "abc" }), "abc")
check("hide.nil", values.hide_key(nil), nil)
check("hide.no-address", values.hide_key({ class = "foot" }), nil)
check("hide.not-a-selector", values.hide_key({ address = "address:abc" }), "address:abc")

check("ws.nil", values.ws_id(nil), nil)
check("ws.number", values.ws_id({ workspace = 5 }), 5)
check("ws.string", values.ws_id({ workspace = "special:scratchpad" }), "special:scratchpad")
check("ws.table-id", values.ws_id({ workspace = { id = 3 } }), 3)
check("ws.table-name", values.ws_id({ workspace = { name = "5" } }), "5")
check("ws.empty", values.ws_id({ workspace = {} }), nil)

if failures > 0 then
  os.exit(1)
end
print("values ok")
