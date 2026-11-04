-- Pure value shapes shared by the event loop. No Hyprland: the config lookup
-- stays in x-mode.lua, and this only interprets the value it already got.
local M = {}

-- A Hyprland query proxy answers any index and has no __len, so # reads 0 and
-- ipairs would walk it forever. An empty or non-array value is no list.
function M.as_list(v)
  if type(v) ~= "table" or #v == 0 then
    return {}
  end
  return v
end

-- A config value as a whole number. A missing value, or one with no digits,
-- is the fallback. Zero is a real value: only false and nil fall through.
function M.cfg_int(value, fallback)
  if value == nil then
    return fallback
  end
  if type(value) == "number" then
    return math.floor(value)
  end
  if type(value) == "table" then
    return math.floor(value.top or value[1] or fallback)
  end
  if type(value) == "string" then
    local n = value:match("(%d+)")
    if n ~= nil then
      return tonumber(n)
    end
  end
  return fallback
end

-- A point or a size, in whichever shape the caller handed over.
function M.vec(value)
  if type(value) ~= "table" then
    return 0, 0
  end
  if value.x ~= nil then
    return value.x, value.y or 0
  end
  if value.w ~= nil then
    return value.w, value.h or 0
  end
  return value[1] or 0, value[2] or 0
end

-- The class the pack groups and matches on. initial_class wins; both are
-- lowercased so a rule written in lower case still hits the window.
function M.window_class(w)
  if w == nil then
    return ""
  end
  return string.lower(tostring(w.initial_class or w.class or ""))
end

-- A rule lists tags with a trailing "*". The window's own list is what counts,
-- and either spelling matches.
function M.window_tagged(w, tag)
  for _, t in ipairs((w and w.tags) or {}) do
    if t == tag or t == tag .. "*" then
      return true
    end
  end
  return false
end

return M
