-- The app switcher's most-recently-used order. Pure list work: x-mode.lua
-- feeds it the focused class and the entries it scanned. Hyprland's
-- focus_history_id is per window and is rewritten while the switcher cycles, so
-- the order is tracked here instead (tests/unit/mru_test.lua).
local M = {}

-- Move `cls` to the front (most recent first), dropping any older entry.
function M.touch(list, cls)
  cls = tostring(cls or "")
  if cls == "" then
    return list
  end
  for i = #list, 1, -1 do
    if list[i] == cls then
      table.remove(list, i)
    end
  end
  table.insert(list, 1, cls)
  return list
end

-- Step an index by `step` over `n` entries, wrapping into 1..n.
function M.step(index, n, step)
  if n <= 0 then
    return index
  end
  return ((index - 1 + step) % n) + 1
end

-- Order entries (each { cls, focus }) most recently used first: `mru` ranks the
-- classes that have been used, and `focus` breaks ties for the rest (e.g. right
-- after a config reload, when the MRU list is empty).
function M.sort(entries, mru)
  local rank = {}
  for i, cls in ipairs(mru or {}) do
    rank[cls] = i
  end
  table.sort(entries, function(a, b)
    local ra, rb = rank[a.cls], rank[b.cls]
    if ra ~= nil or rb ~= nil then
      if ra == nil then
        return false
      end
      if rb == nil then
        return true
      end
      return ra < rb
    end
    return a.focus < b.focus
  end)
  return entries
end

return M
