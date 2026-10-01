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
check("opt.defaults3", d.workspaces_fkeys, false)

local f = settings.parse_options('{"options":{"workspacesOnFkeys":true},"apps":{}}')
check("opt.workspacesOnFkeys", f.workspaces_fkeys, true)

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

-- The per-app flags, off by default.
local wraw = '{"options":{},"apps":{"Chromium":{"ctrlW":true,"ctrlAsSuper":true,"ctrlCShift":true,"ctrlClick":true},"Zed":{}}}'
local wcfg = settings.parse_apps(settings.apps_section(wraw))
check("apps.chromium.ctrlW", wcfg["chromium"].ctrl_w, true)
check("apps.chromium.ctrlAsSuper", wcfg["chromium"].ctrl_as_super, true)
check("apps.chromium.ctrlCShift", wcfg["chromium"].ctrl_c_shift, true)
check("apps.chromium.ctrlClick", wcfg["chromium"].ctrl_click, true)
check("apps.chromium.steal.empty", wcfg["chromium"].ctrl_as_super_keys["Q"], nil)
check("apps.zed.ctrlW", wcfg["zed"].ctrl_w, false)
check("apps.zed.ctrlAsSuper", wcfg["zed"].ctrl_as_super, false)
check("apps.zed.ctrlCShift", wcfg["zed"].ctrl_c_shift, false)
check("apps.zed.ctrlClick", wcfg["zed"].ctrl_click, false)

-- Occupied Super keys stolen for this app, canonicalised to supermap ids.
local sraw = '{"options":{},"apps":{"Chromium":{"ctrlAsSuperKeys":["q","SHIFT+tab","B"]}}}'
local scfg = settings.parse_apps(settings.apps_section(sraw))
check("steal.q", scfg["chromium"].ctrl_as_super_keys["Q"], true)
check("steal.shift-tab", scfg["chromium"].ctrl_as_super_keys["SHIFT+TAB"], true)
check("steal.b", scfg["chromium"].ctrl_as_super_keys["B"], true)
check("steal.junk", scfg["chromium"].ctrl_as_super_keys["mouse:272"], nil)

-- The sets the handlers ask: lowercased classes with the flag on.
local wset = settings.ctrl_w_set({
  chromium = { chrome = true, ctrl_w = true },
  zed = { chrome = true, ctrl_w = false },
  foot = { chrome = false },
})
check("ctrlw.chromium", wset["chromium"], true)
check("ctrlw.zed", wset["zed"], nil)
check("ctrlw.foot", wset["foot"], nil)

-- flag_set drives the other app flags, and is tolerant of a missing table.
local asuper = settings.flag_set(wcfg, "ctrl_as_super")
check("flagset.ctrlAsSuper", asuper["chromium"], true)
check("flagset.ctrlAsSuper.zed", asuper["zed"], nil)
check("flagset.nil", next(settings.flag_set(nil, "ctrl_w")) == nil, true)

-- A legacy array of classes means chrome off.
local legacy = settings.parse_apps(settings.apps_section('{"options":{},"apps":["Foot","Kitty"]}'))
check("legacy.foot.chrome", legacy["foot"].chrome, false)
check("legacy.kitty.chrome", legacy["kitty"].chrome, false)
check("legacy.foot.ctrlW", legacy["foot"].ctrl_w, false)
check("legacy.foot.ctrlAsSuper", legacy["foot"].ctrl_as_super, false)
check("legacy.foot.ctrlCShift", legacy["foot"].ctrl_c_shift, false)
check("legacy.foot.ctrlClick", legacy["foot"].ctrl_click, false)

-- merge folds the two old files into one settings string.
local merged = settings.merge('{"nativeScroll":true}', '{"chromium":{"chrome":false}}')
check("merge.options", settings.parse_options(merged).native_scroll, true)
check("merge.apps", settings.parse_apps(settings.apps_section(merged))["chromium"].chrome, false)

-- The rule effects the app config drives. chrome off wins over always-tabbar.
local nobar, always = settings.desired_rules({
  chromium = { chrome = false, always_tabbar = true },
  zed = { chrome = true, always_tabbar = true },
  foot = { chrome = true, always_tabbar = false },
})
check("rules.nobar.chromium", nobar["chromium"], true)
check("rules.always.chromium", always["chromium"], nil)
check("rules.always.zed", always["zed"], true)
check("rules.nobar.zed", nobar["zed"], nil)
check("rules.foot", nobar["foot"] == nil and always["foot"] == nil, true)

-- A rule's class match: case-insensitive (the stored keys are lowercased) and
-- with the class's regex metacharacters escaped, so an app id with dots or a
-- capital letter still matches the window it came from.
check("pattern.foot", settings.rule_pattern("foot"), "(?i)foot")
check("pattern.thunderbird", settings.rule_pattern("org.mozilla.thunderbird"), "(?i)org\\.mozilla\\.thunderbird")
check("pattern.metachars", settings.rule_pattern("a+b(c)"), "(?i)a\\+b\\(c\\)")

-- The diff: enable what is new, disable what is gone, nothing for unchanged.
local add, drop = settings.rule_diff({ a = true, b = true }, { b = true, c = true })
check("diff.add", table.concat(add, ","), "a")
check("diff.drop", table.concat(drop, ","), "c")
local add2, drop2 = settings.rule_diff({ b = true }, { b = true })
check("diff.unchanged.add", #add2, 0)
check("diff.unchanged.drop", #drop2, 0)

if failures > 0 then
  os.exit(1)
end
print("settings ok")
