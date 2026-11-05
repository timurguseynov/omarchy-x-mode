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

-- The selector Hyprland takes for a window: "address:" plus the bare address.
-- Already-prefixed input is left alone, so this is safe to call twice. Callers
-- guarantee a window with an address -- this is a straight move of the helper
-- that was inline in x-mode.lua, guards included or, rather, not included.
function M.addr_sel(w)
  local a = tostring(w.address)
  if a:sub(1, 8) == "address:" then
    return a
  end
  return "address:" .. a
end

-- The key the pack hides a window under: the address exactly as Hyprland gives
-- it. No prefix is added and none is stripped -- this is an opaque key, not a
-- selector, so a value that already reads "address:..." stays as it is.
function M.hide_key(w)
  if w == nil or w.address == nil then
    return nil
  end
  return tostring(w.address)
end

-- Whether the pack has to write follow_mouse again: only on its own workspaces,
-- and only while the live value is not the pack's 2. Omarchy writes this setting
-- too, so "we set it once" is not a fact and is never cached. A value that could
-- not be read (`nil`) is not proof either: the pack writes then, because leaving
-- Omarchy's 0 in place is the behaviour this exists to prevent.
function M.needs_follow_mouse(ours, current)
  if not ours then
    return false
  end
  return tonumber(current) ~= 2
end

-- A workspace's id, whichever shape Hyprland hands over: a number, a name, or a
-- table with id or name. A missing workspace stays nil rather than the number 0,
-- because 0 is a real workspace the pack has rules about.
function M.ws_id(w)
  local ws = w and w.workspace
  if ws == nil then
    return nil
  end
  local ok, id = pcall(function()
    return ws.id or ws.name
  end)
  if ok and id ~= nil then
    return id
  end
  if type(ws) == "number" or type(ws) == "string" then
    return ws
  end
  return nil
end

return M
