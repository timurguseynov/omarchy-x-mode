-- Pure parsing for the panel's settings file (and the two files it replaced).
-- No Hyprland and no I/O: reading and writing the file stays in x-mode.lua, so
-- this can be tested with plain lua (tests/unit/settings_test.lua).
local M = {}

-- The apps object on its own. The class scan below takes every "key": { ... } it
-- finds, so it must not be pointed at the whole file: "options" would come back
-- as an app class.
function M.apps_section(raw)
  return raw:match('"apps"%s*:%s*(%b{})') or raw:match('"apps"%s*:%s*(%b[])') or ""
end

-- { "class": { "chrome": true, "alwaysTabbar": false, "ctrlW": false } }.
-- Missing chrome means on; missing ctrlW means off (Super+W closes the window).
-- A legacy array of classes means chrome off.
function M.parse_apps(raw)
  local cfg = {}
  for cls, body in raw:gmatch('"([^"]+)"%s*:%s*(%b{})') do
    local chrome = not body:find('"chrome"%s*:%s*false')
    local always = body:find('"alwaysTabbar"%s*:%s*true') ~= nil
    local ctrl_w = body:find('"ctrlW"%s*:%s*true') ~= nil
    cfg[string.lower(cls)] = { chrome = chrome, always_tabbar = always, ctrl_w = ctrl_w }
  end
  if next(cfg) == nil then
    for cls in raw:gmatch('"([^"]+)"') do
      cfg[string.lower(cls)] = { chrome = false, always_tabbar = false, ctrl_w = false }
    end
  end
  return cfg
end

-- The classes whose Super+W the desktop hands to the app as Ctrl+W (close the
-- tab, not the window) instead of closing. Lowercased keys, like parse_apps.
function M.ctrl_w_set(cfg)
  local set = {}
  for cls, e in pairs(cfg or {}) do
    if e.ctrl_w then
      set[cls] = true
    end
  end
  return set
end

-- { native_scroll, ctrl_tab_switch, no_gaps }, each defaulting to false.
function M.parse_options(raw)
  return {
    native_scroll = raw:find('"nativeScroll"%s*:%s*true') ~= nil,
    ctrl_tab_switch = raw:find('"ctrlTabSwitch"%s*:%s*true') ~= nil,
    no_gaps = raw:find('"noGaps"%s*:%s*true') ~= nil,
  }
end

-- Fold the two old files into one settings string.
function M.merge(options_raw, apps_raw)
  return '{"options":' .. (options_raw or "{}") .. ',"apps":' .. (apps_raw or "{}") .. '}'
end

-- The two window-rule effects the app config drives: chrome off (no titlebar at
-- all) and always-tabbar. chrome off wins, so a class with both only gets the
-- first.
function M.desired_rules(cfg)
  local nobar, always = {}, {}
  for cls, e in pairs(cfg or {}) do
    if e.chrome == false then
      nobar[cls] = true
    elseif e.always_tabbar then
      always[cls] = true
    end
  end
  return nobar, always
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
