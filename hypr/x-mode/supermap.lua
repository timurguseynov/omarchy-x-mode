-- The "Super works as Ctrl" map: every Super+key the desktop does not already
-- bind is re-sent to the focused app as Ctrl+key.
--
-- Pure list work: x-mode.lua asks hyprctl for the bind table, hands the text
-- here, and binds what comes back (tests/unit/supermap_test.lua). The occupied
-- set has to be the real one rather than a list kept here, because Hyprland
-- dispatches every matching bind: a generated Super+key layered on an existing
-- one runs both, so an Omarchy action would fire under the app's Ctrl shortcut.
-- Reading `hyprctl binds` keeps that set right on its own as Omarchy grows.
--
-- The text output is used, not `-j`: a bind written with a raw keycode
-- (`SUPER + code:10`, which is how Omarchy binds the workspaces) has no name, so
-- the JSON prints an empty `key` and a `keycode` of 0 and the key it occupies
-- cannot be recovered. The text prints the bind string it was written as.
local M = {}

-- Modmask bits (eKeyboardModifiers): SUPER is 1 << 6, SHIFT is 1 << 0.
local SUPER = 64
local SHIFT = 1

-- Hyprland's `code:` values are the evdev keycode plus 8 (7 is reserved): the
-- number row is 10..19, Q is 24, A is 38. Only the keys that can be planned are
-- listed; a keycode outside the map is not guessed at.
local CODE = {
  -- digits and the row's other keys
  [10] = "1", [11] = "2", [12] = "3", [13] = "4", [14] = "5",
  [15] = "6", [16] = "7", [17] = "8", [18] = "9", [19] = "0",
  [20] = "minus", [21] = "equal",
  [34] = "bracketleft", [35] = "bracketright", [51] = "backslash",
  [47] = "semicolon", [48] = "apostrophe", [49] = "grave",
  [59] = "comma", [60] = "period", [61] = "slash",
  -- letters
  [24] = "Q", [25] = "W", [26] = "E", [27] = "R", [28] = "T", [29] = "Y",
  [30] = "U", [31] = "I", [32] = "O", [33] = "P",
  [38] = "A", [39] = "S", [40] = "D", [41] = "F", [42] = "G", [43] = "H",
  [44] = "J", [45] = "K", [46] = "L",
  [52] = "Z", [53] = "X", [54] = "C", [55] = "V", [56] = "B", [57] = "N",
  [58] = "M",
  -- named keys
  [9] = "ESCAPE", [22] = "BACKSPACE", [23] = "TAB", [36] = "RETURN",
  [65] = "SPACE", [110] = "HOME", [115] = "END",
  [112] = "PAGE_UP", [117] = "PAGE_DOWN", [119] = "DELETE",
  [111] = "UP", [116] = "DOWN", [113] = "LEFT", [114] = "RIGHT",
}

-- name -> Hyprland keycode (the inverse of CODE). `send_shortcut` resolves a
-- key *name* by looking the keysym up in the active layout, so on a Cyrillic
-- layout Ctrl+T does not resolve at all; the keycode it is, then, and the app
-- gets the physical key it means.
local CODE_BY_KEY = {}
for code, name in pairs(CODE) do
  CODE_BY_KEY[name:lower()] = code
end

function M.key_code(name)
  return CODE_BY_KEY[tostring(name or ""):lower()]
end

-- The description every generated bind carries, so a replan does not read back
-- its own binds as occupied.
M.PREFIX = "x-mode-super-ctrl"

-- The keys a Ctrl+<key> rebind is worth generating for: letters first (the app
-- shortcuts that matter: T, W, R, L, P, ...), then digits, punctuation, and the
-- navigation/editing keys. Spelled the way bind strings are, so the same name
-- goes into both the bind and send_shortcut.
M.KEYS = {
  "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
  "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
  "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
  "minus", "equal", "bracketleft", "bracketright", "backslash", "semicolon",
  "apostrophe", "grave", "comma", "period", "slash",
  "RETURN", "BACKSPACE", "DELETE", "HOME", "END", "PAGE_UP", "PAGE_DOWN",
  "LEFT", "RIGHT", "UP", "DOWN", "TAB", "SPACE", "ESCAPE",
}

-- One "\tkey: value" line, with the leading tab `hyprctl binds` prints.
local function fields(block)
  local t = {}
  for line in (block .. "\n"):gmatch("([^\n]*)\n") do
    local k, v = line:match("^%s*([%w_]+):%s*(.*)$")
    if k then
      t[k] = v
    end
  end
  return t
end

-- The key name out of the `key:` field. A bind written with a keycode prints the
-- whole bind string ("SUPER + code:10"), so take the last segment; if that is a
-- code, map it. Anything else (mouse binds, a code outside the map) comes back
-- as it is and simply never matches a planned key.
local function key_name(field)
  local last = field:match("([^+]+)$") or field
  last = last:match("^%s*(.-)%s*$") or last
  local code = last:match("^code:(%d+)$")
  if code then
    return CODE[tonumber(code)]
  end
  return last
end

-- The keys an existing bind with exactly this modmask takes, lowercased. Binds
-- in a submap are left out (they only match inside it, and the generated binds
-- live at the top level), and so are our own.
local function occupied(raw, modmask)
  local set = {}
  for block in (raw or ""):gmatch("(.-)\n\n") do
    local f = fields(block)
    if tonumber(f.modmask or "") == modmask then
      local desc = f.description or ""
      if desc:sub(1, #M.PREFIX) ~= M.PREFIX and f.catchall ~= "true" and (f.submap or "") == "" then
        local name = key_name(f.key or "")
        if name ~= nil and name ~= "" then
          set[name:lower()] = true
        end
      end
    end
  end
  return set
end

-- The free keys as { { key = "T", shift = false }, ... }, letters first. A
-- letter also gets its Shift variant (Ctrl+Shift+T, Ctrl+Shift+N, ...); for
-- punctuation the shifted keysym is a different key, so a Shift bind would
-- never match and none is planned.
function M.plan(raw)
  -- Nothing parsed means the bind table did not land or is not in the shape this
  -- expects. Planning on that would read as "nothing is bound" and generate a
  -- bind for every key, running alongside the real ones; refuse instead.
  if not (raw or ""):find("modmask:%s*%d") then
    return {}
  end
  local plain   = occupied(raw, SUPER)
  local shifted = occupied(raw, SUPER + SHIFT)
  local out     = {}
  for _, key in ipairs(M.KEYS) do
    if not plain[key:lower()] then
      out[#out + 1] = { key = key, shift = false }
    end
    if key:match("^%a$") and not shifted[key:lower()] then
      out[#out + 1] = { key = key, shift = true }
    end
  end
  return out
end

return M
