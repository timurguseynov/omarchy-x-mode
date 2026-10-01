-- The "Super works as Ctrl" map: every Super+key the desktop does not already
-- bind is re-sent to the focused app as Ctrl+key.
--
-- Pure list work: x-mode.lua asks hyprctl for the bind table, hands the JSON
-- here, and binds what comes back (tests/unit/supermap_test.lua). The occupied
-- set has to be the real one rather than a list kept here, because Hyprland
-- dispatches every matching bind: a generated Super+key layered on an existing
-- one runs both, so an Omarchy action would fire under the app's Ctrl shortcut.
-- Reading `hyprctl -j binds` keeps that set right on its own as Omarchy grows.
--
-- A bind made with a raw keycode (`code:20`) carries no key name to match
-- against a keysym, so it is ignored here. The pack's own keycode binds all
-- carry Alt (a different modmask, no collision), and the plain-Super ones are
-- unbound, so nothing is missed today.
local M = {}

-- Modmask bits (eKeyboardModifiers): SUPER is 1 << 6, SHIFT is 1 << 0.
local SUPER = 64
local SHIFT = 1

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

-- The keys an existing bind with exactly this modmask takes, lowercased. Binds
-- in a submap are left out: they only match inside it, and the generated binds
-- live at the top level. Our own binds are left out too.
local function occupied(raw, modmask)
  local set = {}
  for obj in (raw or ""):gmatch("%b{}") do
    local desc = obj:match('"description"%s*:%s*"([^"]*)"') or ""
    if desc:sub(1, #M.PREFIX) ~= M.PREFIX then
      local mask      = tonumber(obj:match('"modmask"%s*:%s*(%d+)'))
      local key       = obj:match('"key"%s*:%s*"([^"]*)"')
      local submap    = obj:match('"submap"%s*:%s*"([^"]*)"') or ""
      local catch_all = obj:match('"catch_all"%s*:%s*true')
      if mask == modmask and key ~= nil and key ~= "" and submap == "" and catch_all == nil then
        set[key:lower()] = true
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
  -- No array at all means the bind table did not land (hyprctl raced or failed).
  -- Planning on that would read as "nothing is bound" and generate a bind for
  -- every key, running alongside the real ones; refuse instead.
  if not (raw or ""):find("%[") then
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
