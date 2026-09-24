-- Pure snap geometry, shared by the desktop layer and its tests.
--
-- Nothing here touches Hyprland: gaps, border, the bar's top and the dock inset
-- all come in as arguments, so the whole file can be loaded and asserted on
-- without a compositor. See tests/unit/geometry_test.lua.
local M = {}

local function vec(v)
  if type(v) ~= "table" then
    return 0, 0
  end
  if v.x ~= nil then
    return v.x, v.y or 0
  end
  if v.w ~= nil then
    return v.w, v.h or 0
  end
  return v[1] or 0, v[2] or 0
end

-- The monitor's reserved area as left, top, right, bottom.
function M.reserved(monitor)
  local r = monitor.reserved
  if type(r) ~= "table" then
    return 0, 0, 0, 0
  end
  if r.left ~= nil then
    return r.left or 0, r.top or 0, r.right or 0, r.bottom or 0
  end
  return r[1] or 0, r[2] or 0, r[3] or 0, r[4] or 0
end

-- Hyprland reports a monitor's size in pixels plus a scale; the layout works in
-- logical pixels.
function M.monitor_box(monitor)
  local scale = tonumber(monitor.scale) or 1
  if scale <= 0 then
    scale = 1
  end
  local x, y = monitor.x, monitor.y
  if x == nil then
    x, y = vec(monitor.position)
  end
  local width = (monitor.width or select(1, vec(monitor.size))) / scale
  local height = (monitor.height or select(2, vec(monitor.size))) / scale
  return x, y, width, height
end

-- The work frame: the monitor minus the reserved area and the dock inset.
-- Rectangle's visibleFrame does the same, and every zone fraction is taken from
-- it, so a left and a right half split this narrower frame and never overlap.
-- `top` comes from the caller because it needs the bar's remembered height.
function M.frame(monitor, top, dock_pull)
  local left, _, right, bottom = M.reserved(monitor)
  local x, y, w, h = M.monitor_box(monitor)
  return x + left, y + top, w - left - right - dock_pull, h - top - bottom
end

-- Rectangle's HalfSplitFrameCalculation, adapted to a top-left origin.
function M.fractional_rect(frame, hside, vside, hf, vf)
  local w = math.floor(frame.w * hf + 0.0001)
  local h = math.floor(frame.h * vf + 0.0001)
  local x = frame.x
  local y = frame.y
  if hside == "right" then
    x = frame.x + frame.w - w
  end
  if vside == "bottom" then
    y = frame.y + frame.h - h
  end
  return x, y, w, h
end

-- The border is drawn outside the window box and reserves its own space, so it
-- comes off every side of the frame once. The gap is inset on top of that: a
-- full outer gap on the screen edges, half on an edge shared with another
-- window, so two snapped windows end up exactly one gap apart.
function M.apply_gaps(x, y, w, h, inner, gap, border)
  local half = math.floor(gap / 2)
  local left = border + (inner.l and half or gap)
  local right = border + (inner.r and half or gap)
  local top = border + (inner.t and half or gap)
  local bottom = border + (inner.b and half or gap)
  return x + left, y + top, w - left - right, h - top - bottom
end

-- Fraction of the frame each action occupies, plus which raw edges sit against a
-- neighbouring window (those get half the inner gap).
local ZONES = {
  ["left"] = { h = "left", v = nil, hf = 0.5, vf = 1, inner = { r = true } },
  ["right"] = { h = "right", v = nil, hf = 0.5, vf = 1, inner = { l = true } },
  ["top"] = { h = nil, v = "top", hf = 1, vf = 0.5, inner = { b = true } },
  ["bottom"] = { h = nil, v = "bottom", hf = 1, vf = 0.5, inner = { t = true } },
  ["top-left"] = { h = "left", v = "top", hf = 0.5, vf = 0.5, inner = { r = true, b = true } },
  ["top-right"] = { h = "right", v = "top", hf = 0.5, vf = 0.5, inner = { l = true, b = true } },
  ["bottom-left"] = { h = "left", v = "bottom", hf = 0.5, vf = 0.5, inner = { r = true, t = true } },
  ["bottom-right"] = { h = "right", v = "bottom", hf = 0.5, vf = 0.5, inner = { l = true, t = true } },
  ["maximize"] = { h = nil, v = nil, hf = 1, vf = 1, inner = {} },
}

M.ZONES = ZONES

-- The geometry of one snap zone within `frame`, or nil for an unknown kind.
function M.zone_geom(kind, frame, gap, border, almost)
  if kind == "almost-maximize" then
    local w = math.floor(frame.w * almost + 0.5)
    local h = math.floor(frame.h * almost + 0.5)
    return frame.x + math.floor((frame.w - w) / 2 + 0.5), frame.y + math.floor((frame.h - h) / 2 + 0.5), w, h
  end
  local z = ZONES[kind]
  if z == nil then
    return nil
  end
  local x, y, w, h = M.fractional_rect(frame, z.h, z.v, z.hf, z.vf)
  return M.apply_gaps(x, y, w, h, z.inner, gap, border)
end

-- A Rectangle-style cycle size: half, two-thirds, a third.
function M.cycle_geom(side, hf, frame, gap, border)
  local inner = side == "left" and { r = true } or { l = true }
  local x, y, w, h = M.fractional_rect(frame, side, nil, hf, 1)
  return M.apply_gaps(x, y, w, h, inner, gap, border)
end

return M
