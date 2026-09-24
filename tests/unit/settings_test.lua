-- settings.lua is pure, so this runs with plain lua: no Hyprland, no compositor.
local repo = os.getenv("X_MODE_REPO") or "."
local settings = dofile(repo .. "/hypr/x-mode/settings.lua")

local failures = 0
local function check(name, got, want)
  if got ~= want then
    io.stderr:write(string.format("FAIL %s: got %s, want %s\n", name, tostring(got), tostring(want)))
    failures = failures + 1
  end
end
local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- options
local o = settings.parse_options('{"options":{"nativeScroll":true,"ctrlTabSwitch":false,"noGaps":true},"apps":{}}')
check("opt.native", o.native_scroll, true)
check("opt.ctrlTabSwitch", o.ctrl_tab_switch, false)
check("opt.noGaps", o.no_gaps, true)

local d = settings.parse_options('{"options":{},"apps":{}}')
check("opt.defaults", d.native_scroll, false)
check("opt.defaults2", d.no_gaps, false)

-- The apps scan must be pointed at the apps section, not the whole file, or
-- "options" comes back as an app class (the merged-settings bug).
local raw = '{"options":{"nativeScroll":false,"noGaps":true},"apps":{"chromium":{"chrome":false,"alwaysTabbar":true},"Zed":{"alwaysTabbar":true}}}'
local cfg = settings.parse_apps(settings.apps_section(raw))
check("apps.count", count(cfg), 2)
check("apps.options-not-a-class", cfg["options"], nil)
check("apps.chromium.chrome", cfg["chromium"].chrome, false)
check("apps.chromium.alwaysTabbar", cfg["chromium"].always_tabbar, true)
check("apps.zed.chrome", cfg["zed"].chrome, true)
check("apps.zed.alwaysTabbar", cfg["zed"].always_tabbar, true)

-- A legacy array of classes means chrome off.
local legacy = settings.parse_apps(settings.apps_section('{"options":{},"apps":["Foot","Kitty"]}'))
check("legacy.foot.chrome", legacy["foot"].chrome, false)
check("legacy.kitty.chrome", legacy["kitty"].chrome, false)

-- merge folds the two old files into one settings string.
local merged = settings.merge('{"nativeScroll":true}', '{"chromium":{"chrome":false}}')
check("merge.options", settings.parse_options(merged).native_scroll, true)
check("merge.apps", settings.parse_apps(settings.apps_section(merged))["chromium"].chrome, false)

if failures > 0 then
  os.exit(1)
end
print("settings ok")
