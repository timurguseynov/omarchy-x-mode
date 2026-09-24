-- geom.lua is pure, so this runs with plain lua: no Hyprland, no compositor.
local repo = os.getenv("X_MODE_REPO") or "."
local geom = dofile(repo .. "/hypr/x-mode/geom.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    io.stderr:write(string.format("FAIL %s: got %s, want %s\n", name, tostring(got), tostring(want)))
    failures = failures + 1
  end
end

-- A 1920x1080 monitor with the 24px bar reserved at the top and a 45px dock pull.
local mon = {
  reserved = { top = 24, left = 0, right = 0, bottom = 0 },
  width = 1920, height = 1080, scale = 1, x = 0, y = 0,
  name = "TEST",
}

-- frame: the monitor minus reserved and the dock inset.
local fx, fy, fw, fh = geom.frame(mon, 24, 45)
check("frame.x", fx, 0)
check("frame.y", fy, 24)
check("frame.w", fw, 1875)
check("frame.h", fh, 1056)

-- scale is applied: pixel size over scale.
local s = { reserved = {}, width = 1800, height = 1000, scale = 2, x = 0, y = 0 }
local _, _, sw, sh = geom.frame(s, 0, 0)
check("scaled.w", sw, 900)
check("scaled.h", sh, 500)

-- A left half with gaps 10 / border 2. The border comes off every side, then the
-- gap: full on the outer edges, half where the window meets its neighbour.
local frame = { x = 0, y = 24, w = 1875, h = 1056 }
local x, y, w, h = geom.zone_geom("left", frame, 10, 2, 0.9)
check("left.x", x, 12)
check("left.y", y, 36)
check("left.w", w, math.floor(1875 * 0.5) - 12 - 7)
check("left.h", h, 1056 - 24)

-- A right half and a left half must not overlap.
local rx, _, rw = geom.zone_geom("right", frame, 10, 2, 0.9)
check("halves-do-not-overlap", rx >= x + w, true)
check("right-right-edge", rx + rw, frame.x + frame.w - 12)

-- No gaps keeps a hairline border.
local nx, ny, nw = geom.zone_geom("left", frame, 0, 1, 0.9)
check("nogap.x", nx, 1)
check("nogap.y", ny, 25)
check("nogap.w", nw, math.floor(1875 * 0.5) - 2)

-- Maximize: the whole frame minus the border/gap inset on every side.
local mx, _, mw, mh = geom.zone_geom("maximize", frame, 10, 2, 0.9)
check("max.x", mx, 12)
check("max.w", mw, 1875 - 24)
check("max.h", mh, 1056 - 24)

-- almost-maximize: 90% of the frame, centred.
local ax, _, aw, ah = geom.zone_geom("almost-maximize", frame, 10, 2, 0.9)
check("almost.w", aw, math.floor(1875 * 0.9 + 0.5))
check("almost.h", ah, math.floor(1056 * 0.9 + 0.5))
check("almost.centred", ax, frame.x + math.floor((1875 - aw) / 2 + 0.5))

-- Unknown kind.
check("unknown", geom.zone_geom("nope", frame, 10, 2, 0.9), nil)

-- Cycle sizes: 1/2, 2/3, 1/3.
local cw2 = select(3, geom.cycle_geom("left", 0.5, frame, 10, 2))
local cw3 = select(3, geom.cycle_geom("left", 2 / 3, frame, 10, 2))
check("cycle.half", cw2, math.floor(1875 * 0.5) - 19)
check("cycle.two-thirds", cw3, math.floor(1875 * (2 / 3)) - 19)
check("cycle.grows", cw3 > cw2, true)

-- fit_box: cap the size, keep the titlebar below the bar and the box inside
-- the edges.
local ff = { x = 0, y = 24, w = 1875, h = 1056 }
local _, ty, tw, th = geom.fit_box({ x = 0, y = 0, w = 100, h = 100 }, ff, 12, 28)
check("fit.top", ty, 24 + 12 + 28)
check("fit.unchanged.w", tw, 100)
check("fit.unchanged.h", th, 100)

local _, _, cw, ch = geom.fit_box({ x = 0, y = 0, w = 99999, h = 99999 }, ff, 12, 28)
check("fit.max.w", cw, 1875 - 24)
check("fit.max.h", ch, 1056 - 24 - 28)

local _, by, _, bh = geom.fit_box({ x = 0, y = 5000, w = 100, h = 100 }, ff, 12, 28)
check("fit.bottom", by + bh, 24 + 1056 - 12)

check("fit.left", select(1, geom.fit_box({ x = -50, y = 100, w = 100, h = 100 }, ff, 12, 28)), 12)
local rx, _, rw = geom.fit_box({ x = 5000, y = 100, w = 100, h = 100 }, ff, 12, 28)
check("fit.right", rx + rw, 1875 - 12)

-- cycle_index: which candidate the window is sitting on, by the anchored edge.
local cands = {
  { x = 0, y = 0, w = 100, h = 100 },
  { x = 100, y = 0, w = 100, h = 100 },
}
check("cycle.left.first", geom.cycle_index({ x = 0, y = 0, w = 100, h = 100 }, cands, "left"), 1)
check("cycle.right.second", geom.cycle_index({ x = 100, y = 0, w = 100, h = 100 }, cands, "right"), 2)
check("cycle.tolerance", geom.cycle_index({ x = 2, y = 0, w = 100, h = 100 }, cands, "left", 4), 1)
check("cycle.none", geom.cycle_index({ x = 500, y = 0, w = 100, h = 100 }, cands, "left"), nil)

if failures > 0 then
  os.exit(1)
end
print("geometry ok")
