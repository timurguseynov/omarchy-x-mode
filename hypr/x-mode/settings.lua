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

-- { "class": { "chrome": true, "alwaysTabbar": false } }. Missing chrome means
-- on; a legacy array of classes means chrome off.
function M.parse_apps(raw)
  local cfg = {}
  for cls, body in raw:gmatch('"([^"]+)"%s*:%s*(%b{})') do
    local chrome = not body:find('"chrome"%s*:%s*false')
    local always = body:find('"alwaysTabbar"%s*:%s*true') ~= nil
    cfg[string.lower(cls)] = { chrome = chrome, always_tabbar = always }
  end
  if next(cfg) == nil then
    for cls in raw:gmatch('"([^"]+)"') do
      cfg[string.lower(cls)] = { chrome = false, always_tabbar = false }
    end
  end
  return cfg
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

return M
