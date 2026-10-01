-- The "Super works as Ctrl" map: every Super+key the desktop does not already
-- bind is re-sent to the focused app as Ctrl+key. Occupied keys stay with the
-- desktop until stolen per app (occupied_list / stealable); those wraps live
-- in x-mode.lua, like Super+W.
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

-- Occupied keys stolen for an app are wrapped, not generated. The wrap's
-- description starts with this so a replan still sees the key as occupied and
-- can recover the original label after the first wrap turned the bind into Lua.
M.STEAL_PREFIX = "x-mode-super-steal"

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
  for block in ((raw or "") .. "\n\n"):gmatch("(.-)\n\n") do
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

function M.key_id(key, shift)
  key = tostring(key or "")
  if shift then
    return "SHIFT+" .. key
  end
  return key
end

-- The KEYS spelling for a stored id, or nil when the name is not a mappable
-- key (a mouse bind, a code outside the map). "q" and "shift+tab" both match.
local KEY_CANON = {}
for _, name in ipairs(M.KEYS) do
  KEY_CANON[name:lower()] = name
end

function M.canonical_id(s)
  local raw = tostring(s or "")
  local key = raw:match("^[Ss][Hh][Ii][Ff][Tt]%+(.*)$")
  local shift = key ~= nil
  if not shift then
    key = raw
  end
  local canon = KEY_CANON[key:lower()]
  if canon == nil then
    return nil
  end
  return M.key_id(canon, shift)
end

-- Glyphs and short names for the panel: Super+comma is Super+,, Super+LEFT is
-- Super+←. Bind strings keep the Hyprland spelling (comma, LEFT); only the
-- label shown to the user is pretty.
local PRETTY = {
  comma = ",", period = ".", slash = "/", minus = "-", equal = "=",
  semicolon = ";", apostrophe = "'", grave = "`", backslash = "\\",
  bracketleft = "[", bracketright = "]",
  ESCAPE = "Esc", RETURN = "Enter", PAGE_UP = "PgUp", PAGE_DOWN = "PgDn",
  DELETE = "Del", BACKSPACE = "⌫",
  LEFT = "←", RIGHT = "→", UP = "↑", DOWN = "↓",
}

local function pretty_key(key)
  key = tostring(key or "")
  if PRETTY[key] then
    return PRETTY[key]
  end
  if key:match("^%a$") then
    return key
  end
  if key:match("^[A-Z_]+$") then
    return key:sub(1, 1) .. key:sub(2):lower():gsub("_", "-")
  end
  return key
end

function M.label(key, shift)
  local pretty = pretty_key(tostring(key or ""))
  if shift then
    return "⌘+⇧+" .. pretty
  end
  return "⌘+" .. pretty
end

local function json_str(s)
  return '"' .. tostring(s or ""):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
end

-- Strip the steal-wrap prefix so the panel shows the original description.
local function steal_description(desc)
  desc = desc or ""
  if desc:sub(1, #M.STEAL_PREFIX) ~= M.STEAL_PREFIX then
    return desc
  end
  local rest = desc:sub(#M.STEAL_PREFIX + 2)
  local orig = rest:match("^%S+%s+(.*)$")
  if orig == nil or orig == "" then
    return ""
  end
  return orig
end

function M.steal_desc(id, orig)
  orig = orig or ""
  if orig == "" then
    return M.STEAL_PREFIX .. " " .. id
  end
  return M.STEAL_PREFIX .. " " .. id .. " " .. orig
end

local function is_digit(key)
  return tostring(key):match("^[0-9]$") ~= nil
end

-- Occupied Super / Super+Shift keys in KEYS order. Digits are the workspace
-- keys (main panel). W has its own Super+W toggle. Generated super-ctrl binds
-- are skipped; steal wraps stay, so a replan does not treat them as free.
function M.occupied_list(raw)
  if not (raw or ""):find("modmask:%s*%d") then
    return {}
  end
  local by_id = {}
  for block in ((raw or "") .. "\n\n"):gmatch("(.-)\n\n") do
    local f = fields(block)
    local mask = tonumber(f.modmask or "") or 0
    local shift = nil
    if mask == SUPER then
      shift = false
    elseif mask == SUPER + SHIFT then
      shift = true
    end
    local desc = f.description or ""
    local name = key_name(f.key or "")
    local canon = name and KEY_CANON[name:lower()] or nil
    if shift ~= nil
        and desc:sub(1, #M.PREFIX) ~= M.PREFIX
        and f.catchall ~= "true"
        and (f.submap or "") == ""
        and canon ~= nil
        and not is_digit(canon)
        and not (canon:lower() == "w" and not shift) then
      local id = M.key_id(canon, shift)
      local wrapped = desc:sub(1, #M.STEAL_PREFIX) == M.STEAL_PREFIX
      local e = by_id[id]
      if e == nil then
        e = {
          id = id,
          key = canon,
          shift = shift,
          label = M.label(canon, shift),
          description = steal_description(desc),
          dispatcher = f.dispatcher or "",
          arg = f.arg or "",
          wrapped = wrapped,
          binds = {},
        }
        by_id[id] = e
      elseif wrapped then
        e.wrapped = true
      end
      e.binds[#e.binds + 1] = {
        dispatcher = f.dispatcher or "",
        arg = f.arg or "",
        description = steal_description(desc),
      }
    end
  end
  local out = {}
  for _, key in ipairs(M.KEYS) do
    local plain = by_id[M.key_id(key, false)]
    if plain then
      out[#out + 1] = plain
    end
    local shifted = by_id[M.key_id(key, true)]
    if shifted then
      out[#out + 1] = shifted
    end
  end
  return out
end

-- Occupied keys the panel can actually steal. A foreign __lua callback cannot
-- be replayed after unbind, so those are dropped unless `lua_ok` names a key
-- the pack wraps itself (Q, Tab), the bind is already our steal wrap, or
-- `exec_ids` has a command we can fire in its place (Omarchy's string binds).
function M.stealable(raw, lua_ok, exec_ids)
  lua_ok = lua_ok or {}
  exec_ids = exec_ids or {}
  local out = {}
  for _, e in ipairs(M.occupied_list(raw)) do
    local disp = e.dispatcher or ""
    local own = lua_ok[e.key] or lua_ok[e.key:upper()] or lua_ok[e.key:lower()]
    if disp ~= "__lua" or own or e.wrapped or exec_ids[e.id] then
      out[#out + 1] = e
    end
  end
  return out
end

-- Commands behind Omarchy's o.bind / o.bind_toggle Super keys, so a steal wrap
-- can replay them after unbind (hyprctl only prints __lua and a registry id).
-- String dispatchers and `{ omarchy = "name" }` tables; function dispatchers
-- (clipboard Super+C/V/X) are left out.
local function omarchy_keys_to_id(keys)
  keys = tostring(keys or "")
  if keys:find("CTRL", 1, true) or keys:find("ALT", 1, true) then
    return nil
  end
  local shift = keys:find("SHIFT", 1, true) ~= nil
  local key = keys:match("([%w_]+)%s*$")
  if key == nil or key == "SUPER" or key == "SHIFT" then
    return nil
  end
  return M.canonical_id(shift and ("SHIFT+" .. key) or key)
end

function M.parse_omarchy_binds(raw)
  local out = {}
  raw = raw or ""
  for keys, _, cmd in raw:gmatch('o%.bind%(%s*"([^"]+)"%s*,%s*"([^"]*)"%s*,%s*"([^"]+)"') do
    local id = omarchy_keys_to_id(keys)
    if id then
      out[id] = cmd
    end
  end
  for keys, _, body in raw:gmatch('o%.bind%(%s*"([^"]+)"%s*,%s*"([^"]*)"%s*,%s*(%b{})') do
    local id = omarchy_keys_to_id(keys)
    local name = body:match('omarchy%s*=%s*"([^"]+)"')
    if id and name then
      out[id] = "omarchy-launch-" .. name
    end
  end
  for keys, _, name in raw:gmatch('o%.bind_toggle%(%s*"([^"]+)"%s*,%s*"([^"]*)"%s*,%s*"([^"]+)"') do
    local id = omarchy_keys_to_id(keys)
    if id then
      out[id] = "omarchy-toggle-" .. name
    end
  end
  return out
end

function M.occupied_json(entries)
  local parts = {}
  for i, e in ipairs(entries or {}) do
    parts[i] = string.format(
      '{"id":%s,"key":%s,"shift":%s,"label":%s,"description":%s}',
      json_str(e.id), json_str(e.key), e.shift and "true" or "false",
      json_str(e.label), json_str(e.description or "")
    )
  end
  return "[" .. table.concat(parts, ",") .. "]"
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
