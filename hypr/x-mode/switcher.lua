-- What the switcher row is built from and what it tells the shell: the classes to
-- show, in most-recently-used order, and the one command line Switcher.qml reads.
-- The state machine (which entry is current, when the row closes) stays in
-- x-mode.lua; this is the part that can be wrong without a compositor.
local M = {}

local mru = dofile(((debug.getinfo(1, "S").source or ""):match("^@(.*/)") or "./") .. "mru.lua")

-- One entry per window class, using the class's most recently focused window:
-- a class can have several windows, and taking whichever came first in the
-- compositor's list would sort it by the wrong one. `focus_history_id` is the
-- compositor's own counter, smaller meaning more recent.
function M.class_entries(windows, order)
  local by_class = {}
  for _, w in ipairs(windows or {}) do
    local cls = tostring(w.class or "")
    if cls ~= "" then
      local f = tonumber(w.focus_history_id) or 999999
      if by_class[cls] == nil or f < by_class[cls].focus then
        by_class[cls] = { focus = f, addr = tostring(w.address or "") }
      end
    end
  end
  local entries = {}
  for cls, e in pairs(by_class) do
    table.insert(entries, { cls = cls, focus = e.focus, addr = e.addr })
  end
  -- Most recently used first, like macOS Cmd+Tab; see mru.sort.
  mru.sort(entries, order or {})
  return entries
end

-- The token the row uses for an entry: the class and the address of the window it
-- stands for, so the shell can tell two windows of one class apart.
function M.tokens(entries)
  local out = {}
  for _, e in ipairs(entries or {}) do
    table.insert(out, e.cls .. "|" .. e.addr)
  end
  return out
end

-- The line Switcher.qml reads while the row is up: which class is current, then
-- every token in row order.
function M.show_line(cls, tokens)
  return "show " .. tostring(cls) .. " " .. table.concat(tokens or {}, " ")
end

-- What the shell reads when the row goes away.
function M.hide_line()
  return "hide"
end

return M
