-- Pure parsing for the panel's settings file (and the two files it replaced).
-- No Hyprland and no I/O: reading and writing the file stays in x-mode.lua, so
-- this can be tested with plain lua (tests/unit/settings_test.lua).
local M = {}

-- Occupied Super-key ids are canonicalised the same way the bind plan spells
-- them (Q, TAB, SHIFT+TAB), so a hand-edited "q" still matches Super+Q.
local supermap = dofile(((debug.getinfo(1, "S").source or ""):match("^@(.*/)") or "./") .. "supermap.lua")

-- The apps object on its own. The class scan below takes every "key": { ... } it
-- finds, so it must not be pointed at the whole file: "options" would come back
-- as an app class.
function M.apps_section(raw)
  return raw:match('"apps"%s*:%s*(%b{})') or raw:match('"apps"%s*:%s*(%b[])') or ""
end

-- { "class": { "chrome": true, "alwaysTabbar": false, "compactTabs": false,
--   "ctrlAsSuper": false, "ctrlCShift": false, "ctrlClick": false,
--   "digitTabs": false, "ctrlAsSuperKeys": [] } }.
-- Missing chrome means on; the rest missing means off. compactTabs is also a
-- desktop option; the per-app flag ORs with it (chrome off still wins).
-- A legacy array of classes means chrome off.
-- A per-app flag in three states: true, false, or absent (which is not the same
-- as false -- it means "whatever the desktop says").
local function tri(body, name)
  if body:find('"' .. name .. '"%s*:%s*true') then
    return true
  end
  if body:find('"' .. name .. '"%s*:%s*false') then
    return false
  end
  return nil
end

local function parse_steal_keys(body, field)
  local keys = {}
  local arr = body:match('"' .. (field or "ctrlAsSuperKeys") .. '"%s*:%s*(%b[])')
  if arr == nil then
    return keys
  end
  for item in arr:gmatch('"([^"]+)"') do
    local id = supermap.canonical_id(item)
    if id ~= nil then
      keys[id] = true
    end
  end
  return keys
end

function M.parse_apps(raw)
  local cfg = {}
  for cls, body in raw:gmatch('"([^"]+)"%s*:%s*(%b{})') do
    local chrome = not body:find('"chrome"%s*:%s*false')
    local always = body:find('"alwaysTabbar"%s*:%s*true') ~= nil
    local keys = parse_steal_keys(body)
    local keys_off = parse_steal_keys(body, "ctrlAsSuperKeysOff")
    -- Cmd+W was a replacement of its own (the ctrlW flag) before it became a
    -- steal like Cmd+Q and Cmd+F: on hands the key to the app (Ctrl+W), off is
    -- the Always off list that keeps it with the desktop. A file the older panel
    -- wrote still says ctrlW, so it is folded onto the key it always meant -- the
    -- flag itself is gone, on both sides.
    local ctrl_w = tri(body, "ctrlW")
    if ctrl_w == true then
      keys["W"] = true
    elseif ctrl_w == false then
      keys_off["W"] = true
    end
    cfg[string.lower(cls)] = {
      chrome = chrome,
      always_tabbar = always,
      compact_tabs = body:find('"compactTabs"%s*:%s*true') ~= nil,
      -- Three-state, per flag: an explicit true or false is an override that wins
      -- over the desktop's, and absent follows the desktop. One value, so an app
      -- that wants the opposite of the desktop does not need a second field.
      ctrl_as_super = tri(body, "ctrlAsSuper"),
      ctrl_c_shift = tri(body, "ctrlCShift"),
      ctrl_click = tri(body, "ctrlClick"),
      digit_tabs = tri(body, "digitTabs"),
      ctrl_tab_switch = tri(body, "ctrlTabSwitch"),
      ctrl_as_super_keys = keys,
      ctrl_as_super_keys_off = keys_off,
    }
  end
  if next(cfg) == nil then
    for cls in raw:gmatch('"([^"]+)"') do
      cfg[string.lower(cls)] = {
        chrome = false,
        always_tabbar = false,
        compact_tabs = false,
        ctrl_as_super = nil,
        ctrl_c_shift = nil,
        ctrl_click = nil,
        digit_tabs = nil,
        ctrl_tab_switch = nil,
        ctrl_as_super_keys = {},
        ctrl_as_super_keys_off = {},
      }
    end
  end
  return cfg
end

-- The keyboard flags a class can override: the name parse_apps keys them under,
-- and the name the settings file and the panel use. One list, so the engine, the
-- panel's JavaScript and the tests cannot drift apart.
M.KEY_FLAGS = {
  { "ctrl_as_super", "ctrlAsSuper" },
  { "digit_tabs", "digitTabs" },
  { "ctrl_tab_switch", "ctrlTabSwitch" },
  { "ctrl_click", "ctrlClick" },
  { "ctrl_c_shift", "ctrlCShift" },
}

-- The flag for a class: its own setting first -- true is Always on, false is
-- Always off -- and the desktop's forced one behind it.
function M.key_flag(cfg, cls, global, flag)
  local e = (cfg or {})[cls]
  if e ~= nil then
    -- Read the value before comparing: `e[flag] or nil` would turn the explicit
    -- false of Always off into "no setting" again.
    local v = e[flag]
    if v ~= nil then
      return v == true
    end
  end
  return (global or {})[flag] == true
end

-- Whether anything has the flag on. The generated binds exist only then, so an
-- Always on in a single app's card is enough to put them in place.
function M.key_flag_any(cfg, global, flag)
  if (global or {})[flag] == true then
    return true
  end
  for _, e in pairs(cfg or {}) do
    if e[flag] == true then
      return true
    end
  end
  return false
end

-- One occupied key for a class: its own lists first -- Always off is what the
-- panel writes when a card turns a key off, and it wins, so a key the desktop
-- steals stays with one app -- then the desktop's list.
function M.key_stolen(cfg, cls, global_steal, id)
  local e = (cfg or {})[cls]
  if e ~= nil then
    if e.ctrl_as_super_keys_off ~= nil and e.ctrl_as_super_keys_off[id] == true then
      return false
    end
    if e.ctrl_as_super_keys ~= nil and e.ctrl_as_super_keys[id] == true then
      return true
    end
  end
  return (global_steal or {})[id] == true
end


-- { native_scroll, no_gaps, workspaces_fkeys, lock_key }, plus the keyboard
-- replacements the main panel forces on for every app (key_flags, keyed the way the
-- parsed apps are) and the occupied keys it steals for every class (global_steal).
-- The JSON name of each replacement and the name the parsed apps use, so a forced
-- flag is read by the handlers under the same shape as a per-app one.
local KEY_FLAGS = {
  { "ctrlAsSuper", "ctrl_as_super" },
  { "digitTabs", "digit_tabs" },
  { "ctrlClick", "ctrl_click" },
  { "ctrlCShift", "ctrl_c_shift" },
}

function M.parse_options(raw)
  -- Scoped to the options block: an app class may be called "keys" too, and the
  -- flat finds above would happily read its entry.
  local opts = raw:match('"options"%s*:%s*(%b{})') or ""
  local keys = opts:match('"keys"%s*:%s*(%b{})') or ""
  local flags = {}
  for _, pair in ipairs(KEY_FLAGS) do
    if keys:find('"' .. pair[1] .. '"%s*:%s*true') then
      flags[pair[2]] = true
    end
  end
  -- Ctrl+1..0 switching tabs was a desktop option of its own before it became a row
  -- with the other replacements. A config written by the older panel still has it
  -- in the flat options, so it is read from there when the new place says nothing.
  if flags.ctrl_tab_switch == nil and raw:find('"ctrlTabSwitch"%s*:%s*true') then
    flags.ctrl_tab_switch = true
  end
  -- The same for Cmd+W, which was `keys.ctrlW`: it is the W steal the panel writes
  -- now, and the only thing it ever meant was "hand this key to the app".
  local global_steal = parse_steal_keys(keys, "steal")
  if keys:find('"ctrlW"%s*:%s*true') then
    global_steal["W"] = true
  end
  return {
    native_scroll = raw:find('"nativeScroll"%s*:%s*true') ~= nil,
    no_gaps = raw:find('"noGaps"%s*:%s*true') ~= nil,
    workspaces_fkeys = raw:find('"workspacesOnFkeys"%s*:%s*true') ~= nil,
    -- One Chrome-like titlebar row instead of titlebar + tabbar. Scoped to the
    -- options block so an app class cannot set it for the desktop.
    compact_tabs = opts:find('"compactTabs"%s*:%s*true') ~= nil,
    -- The one option whose default is on: Omarchy keeps its Calculator on
    -- Ctrl+Cmd+Q, macOS puts Lock Screen there, and the pack ships the Mac key.
    -- Absent means on; only an explicit false gives the key back.
    lock_key = opts:find('"lockScreenKey"%s*:%s*false') == nil,
    key_flags = flags,
    global_steal = global_steal,
  }
end

-- Fold the two old files into one settings string.
function M.merge(options_raw, apps_raw)
  return '{"options":' .. (options_raw or "{}") .. ',"apps":' .. (apps_raw or "{}") .. '}'
end

-- The window-rule effects the app config drives: chrome off (no titlebar at
-- all), always-tabbar, and compact tabs (one Chrome-like row). chrome off wins,
-- so a class with chrome off gets none of the others.
function M.desired_rules(cfg)
  local nobar, always, compact = {}, {}, {}
  for cls, e in pairs(cfg or {}) do
    if e.chrome == false then
      nobar[cls] = true
    else
      if e.always_tabbar then
        always[cls] = true
      end
      if e.compact_tabs then
        compact[cls] = true
      end
    end
  end
  return nobar, always, compact
end

-- The `class` match value for a window rule, from an app key. Hyprland matches
-- a rule's class as a case-sensitive RE2 full match, and the keys are lowercased
-- on the way in (the panel and parse_apps both lowercase), so a class with an
-- uppercase letter in it never matched -- Thunderbird's "org.mozilla.Thunderbird"
-- was the one that showed it. Build the pattern from the key: turn on RE2's
-- case-insensitive inline flag and escape every metacharacter (the class is a
-- regex, and dots are common in app ids).
function M.rule_pattern(cls)
  local RE2_MAGIC = "%^%$%.%|%?%*%+%(%)%[%]%{%}"
  local escaped   = string.gsub(cls or "", "([" .. RE2_MAGIC .. "])", "\\%1")
  return "(?i)" .. escaped
end

-- What to turn on and off for one effect: `desired` is the set the config wants
-- now, `applied` what was set last time. Returns two sorted class lists.
function M.rule_diff(desired, applied)
  desired, applied = desired or {}, applied or {}
  local enable, disable = {}, {}
  for cls in pairs(desired) do
    if not applied[cls] then
      enable[#enable + 1] = cls
    end
  end
  for cls in pairs(applied) do
    if not desired[cls] then
      disable[#disable + 1] = cls
    end
  end
  table.sort(enable)
  table.sort(disable)
  return enable, disable
end

return M
