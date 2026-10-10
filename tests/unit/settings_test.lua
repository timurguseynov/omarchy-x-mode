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
check("opt.ctrlTabSwitch", o.key_flags.ctrl_tab_switch, nil)
check("opt.noGaps", o.no_gaps, true)

local d = settings.parse_options('{"options":{},"apps":{}}')
check("opt.defaults", d.native_scroll, false)
check("opt.defaults2", d.no_gaps, false)
check("opt.defaults3", d.workspaces_fkeys, false)
check("opt.defaults.compactTabs", d.compact_tabs, false)

local ct = settings.parse_options('{"options":{"compactTabs":true},"apps":{}}')
check("opt.compactTabs", ct.compact_tabs, true)
-- An app cannot set the desktop option: compactTabs lives under options.
local ctapp = settings.parse_options('{"options":{},"apps":{"foot":{"compactTabs":true}}}')
check("opt.compactTabs.not-an-app", ctapp.compact_tabs, false)

local f = settings.parse_options('{"options":{"workspacesOnFkeys":true},"apps":{}}')
check("opt.workspacesOnFkeys", f.workspaces_fkeys, true)

-- The keyboard shortcuts the main panel forces on for every app. Absent means
-- per app, so every flag has to read as unset when there is no keys block.
local kopt = settings.parse_options('{"options":{"keys":{"ctrlAsSuper":true,"steal":["q","SHIFT+tab","mouse:272"]}},"apps":{}}')
check("opt.keys.ctrlAsSuper", kopt.key_flags.ctrl_as_super, true)
check("opt.keys.digitTabs.absent", kopt.key_flags.digit_tabs, nil)
check("opt.keys.steal.q", kopt.global_steal["Q"], true)
check("opt.keys.steal.shift-tab", kopt.global_steal["SHIFT+TAB"], true)
check("opt.keys.steal.junk", kopt.global_steal["mouse:272"], nil)

-- Cmd+W was a replacement of its own (the ctrlW flag) before it became a steal
-- like Cmd+Q and Cmd+F. A file written by the older panel has it as a flag, and
-- it has to keep working as the W steal it always meant.
local wold = settings.parse_options('{"options":{"keys":{"ctrlW":true}},"apps":{}}')
check("opt.keys.ctrlW.folded", wold.global_steal["W"], true)
check("opt.keys.ctrlW.gone", wold.key_flags.ctrl_w, nil)
check("opt.keys.ctrlW.alone", next(wold.key_flags) == nil, true)

local nokeys = settings.parse_options('{"options":{"noGaps":true},"apps":{}}')
check("opt.keys.none", next(nokeys.key_flags) == nil, true)
check("opt.keys.none.steal", next(nokeys.global_steal) == nil, true)

-- The lock key is the one option whose default is on: Omarchy's Calculator sits
-- on Ctrl+Cmd+Q and the pack ships the Mac lock there unless the file says no.
check("opt.lockKey.default", nokeys.lock_key, true)
check("opt.lockKey.on", settings.parse_options('{"options":{"lockScreenKey":true},"apps":{}}').lock_key, true)
check("opt.lockKey.off", settings.parse_options('{"options":{"lockScreenKey":false},"apps":{}}').lock_key, false)

-- An app class called "keys" must not be read as the options block: the global
-- map has to come from under "options".
local named = settings.parse_options('{"options":{"noGaps":true},"apps":{"keys":{"ctrlAsSuper":true}}}')
check("opt.keys.not-an-app", next(named.key_flags) == nil, true)

-- The apps scan must be pointed at the apps section, not the whole file, or
-- "options" comes back as an app class (the merged-settings bug).
local raw = '{"options":{"nativeScroll":false,"noGaps":true},"apps":{"chromium":{"chrome":false,"alwaysTabbar":true},"Zed":{"alwaysTabbar":true}}}'
local cfg = settings.parse_apps(settings.apps_section(raw))
check("apps.count", count(cfg), 2)
check("apps.options-not-a-class", cfg["options"], nil)
check("apps.chromium.chrome", cfg["chromium"].chrome, false)
check("apps.chromium.alwaysTabbar", cfg["chromium"].always_tabbar, true)
check("apps.chromium.compactTabs", cfg["chromium"].compact_tabs, false)
check("apps.zed.chrome", cfg["zed"].chrome, true)
check("apps.zed.alwaysTabbar", cfg["zed"].always_tabbar, true)

-- The per-app flags in three states: true is Always on, false is Always off, and
-- absent is neither -- it follows the desktop's.
local wraw = '{"options":{},"apps":{"Chromium":{"ctrlClick":true,"ctrlAsSuper":true,"ctrlCShift":true,"digitTabs":true,"ctrlTabSwitch":false},"Zed":{}}}'
local wcfg = settings.parse_apps(settings.apps_section(wraw))
check("apps.chromium.ctrlClick", wcfg["chromium"].ctrl_click, true)
check("apps.chromium.ctrlAsSuper", wcfg["chromium"].ctrl_as_super, true)
check("apps.chromium.ctrlCShift", wcfg["chromium"].ctrl_c_shift, true)
check("apps.chromium.digitTabs", wcfg["chromium"].digit_tabs, true)
check("apps.chromium.ctrlTabSwitch.off", wcfg["chromium"].ctrl_tab_switch, false)
check("apps.chromium.steal.empty", wcfg["chromium"].ctrl_as_super_keys["Q"], nil)
check("apps.zed.ctrlClick", wcfg["zed"].ctrl_click, nil)
check("apps.zed.ctrlAsSuper", wcfg["zed"].ctrl_as_super, nil)
check("apps.zed.ctrlCShift", wcfg["zed"].ctrl_c_shift, nil)
check("apps.zed.digitTabs", wcfg["zed"].digit_tabs, nil)
check("apps.zed.ctrlTabSwitch", wcfg["zed"].ctrl_tab_switch, nil)

-- The same for the flag Cmd+W used to have: an older file's ctrlW is folded onto
-- the W steal (on) or the W Always off (off), and no ctrl_w field is left.
local cwraw = '{"options":{},"apps":{"Chromium":{"ctrlW":true},"Zed":{"ctrlW":false},"Foot":{}}}'
local cwcfg = settings.parse_apps(settings.apps_section(cwraw))
check("apps.ctrlW.on", cwcfg["chromium"].ctrl_as_super_keys["W"], true)
check("apps.ctrlW.on.off-list", cwcfg["chromium"].ctrl_as_super_keys_off["W"], nil)
check("apps.ctrlW.off", cwcfg["zed"].ctrl_as_super_keys_off["W"], true)
check("apps.ctrlW.off.on-list", cwcfg["zed"].ctrl_as_super_keys["W"], nil)
check("apps.ctrlW.absent", cwcfg["foot"].ctrl_as_super_keys["W"], nil)
check("apps.ctrlW.field", cwcfg["chromium"].ctrl_w, nil)

-- Occupied Super keys stolen for this app, canonicalised to supermap ids, and the
-- list that says Always off for a key the desktop steals.
local sraw = '{"options":{},"apps":{"Chromium":{"ctrlAsSuperKeys":["q","SHIFT+tab","B"],"ctrlAsSuperKeysOff":["F"]}}}'
local scfg = settings.parse_apps(settings.apps_section(sraw))
check("steal.q", scfg["chromium"].ctrl_as_super_keys["Q"], true)
check("steal.shift-tab", scfg["chromium"].ctrl_as_super_keys["SHIFT+TAB"], true)
check("steal.b", scfg["chromium"].ctrl_as_super_keys["B"], true)
check("steal.junk", scfg["chromium"].ctrl_as_super_keys["mouse:272"], nil)
check("steal.off.f", scfg["chromium"].ctrl_as_super_keys_off["F"], true)
check("steal.off.empty", scfg["chromium"].ctrl_as_super_keys_off["Q"], nil)

-- The effective flag for a class: its own setting or, when it has none, the
-- desktop's. This is what the handlers ask, and what a card's Always off is for.
local gcfg = settings.parse_apps(settings.apps_section('{"options":{},"apps":{"Zed":{"ctrlAsSuper":false},"Chrome":{}}}'))
local gkeys = { ctrl_as_super = true, ctrl_click = false }
check("key.own-off-wins", settings.key_flag(gcfg, "zed", gkeys, "ctrl_as_super"), false)
check("key.inherits-global", settings.key_flag(gcfg, "chrome", gkeys, "ctrl_as_super"), true)
check("key.inherits-off", settings.key_flag(gcfg, "chrome", gkeys, "ctrl_click"), false)
check("key.unknown-class", settings.key_flag(gcfg, "nope", gkeys, "ctrl_as_super"), true)
check("key.nil-cfg", settings.key_flag(nil, "zed", gkeys, "ctrl_as_super"), true)
check("key.own-on", settings.key_flag(gcfg, "zed", {}, "ctrl_as_super"), false)
check("key.missing-key", settings.key_flag(gcfg, "chrome", nil, "ctrl_click"), false)

-- Whether anything has the flag on at all: the generated binds exist only then, so
-- a single card's Always on is enough.
check("any.global", settings.key_flag_any(gcfg, gkeys, "ctrl_as_super"), true)
check("any.none", settings.key_flag_any(gcfg, gkeys, "digit_tabs"), false)
local oncfg = settings.parse_apps(settings.apps_section('{"options":{},"apps":{"Zed":{"digitTabs":true}}}'))
check("any.one-card", settings.key_flag_any(oncfg, {}, "digit_tabs"), true)
local offcfg = settings.parse_apps(settings.apps_section('{"options":{},"apps":{"Zed":{"digitTabs":false}}}'))
check("any.off-is-not-on", settings.key_flag_any(offcfg, {}, "digit_tabs"), false)

-- One occupied key for a class: the app's lists first (Always off wins), then the
-- desktop's list.
local stealcfg = settings.parse_apps(settings.apps_section('{"options":{},"apps":{"Zed":{"ctrlAsSuperKeys":["T"],"ctrlAsSuperKeysOff":["Q"]}}}'))
local gsteal = { Q = true, TAB = true }
check("stolen.global", settings.key_stolen(stealcfg, "chrome", gsteal, "Q"), true)
check("stolen.own-off", settings.key_stolen(stealcfg, "zed", gsteal, "Q"), false)
check("stolen.own-on", settings.key_stolen(stealcfg, "zed", {}, "T"), true)
check("stolen.inherits", settings.key_stolen(stealcfg, "zed", gsteal, "TAB"), true)
check("stolen.none", settings.key_stolen(stealcfg, "zed", gsteal, "B"), false)
check("stolen.nil-cfg", settings.key_stolen(nil, "zed", gsteal, "Q"), true)

-- The reserve flag is read the same way, and is unset unless the card asked.
check("flagset.digitTabs", settings.key_flag(wcfg, "chromium", {}, "digit_tabs"), true)
check("flagset.digitTabs.zed", settings.key_flag(wcfg, "zed", {}, "digit_tabs"), false)

-- Ctrl+1..0 switching tabs used to be a desktop option of its own; a config the
-- older panel wrote keeps working, read from the flat option.
local oldtab = settings.parse_options('{"options":{"ctrlTabSwitch":true},"apps":{}}')
check("opt.ctrlTabSwitch.old", oldtab.key_flags.ctrl_tab_switch, true)
check("opt.ctrlTabSwitch.default", settings.parse_options('{"options":{},"apps":{}}').key_flags.ctrl_tab_switch, nil)
local newtab = settings.parse_options('{"options":{"keys":{"ctrlTabSwitch":true}},"apps":{}}')
check("opt.ctrlTabSwitch.new", newtab.key_flags.ctrl_tab_switch, true)

-- A legacy array of classes means chrome off.
local legacy = settings.parse_apps(settings.apps_section('{"options":{},"apps":["Foot","Kitty"]}'))
check("legacy.foot.chrome", legacy["foot"].chrome, false)
check("legacy.kitty.chrome", legacy["kitty"].chrome, false)
check("legacy.foot.ctrlW.gone", legacy["foot"].ctrl_w, nil)
check("legacy.foot.ctrlAsSuper", legacy["foot"].ctrl_as_super, nil)
check("legacy.foot.ctrlCShift", legacy["foot"].ctrl_c_shift, nil)
check("legacy.foot.ctrlClick", legacy["foot"].ctrl_click, nil)
check("legacy.foot.digitTabs", legacy["foot"].digit_tabs, nil)
check("legacy.foot.ctrlTabSwitch", legacy["foot"].ctrl_tab_switch, nil)

-- merge folds the two old files into one settings string.
local merged = settings.merge('{"nativeScroll":true}', '{"chromium":{"chrome":false}}')
check("merge.options", settings.parse_options(merged).native_scroll, true)
check("merge.apps", settings.parse_apps(settings.apps_section(merged))["chromium"].chrome, false)

-- The rule effects the app config drives. chrome off wins over always-tabbar
-- and compact tabs.
local nobar, always, compact = settings.desired_rules({
  chromium = { chrome = false, always_tabbar = true, compact_tabs = true },
  zed = { chrome = true, always_tabbar = true, compact_tabs = true },
  foot = { chrome = true, always_tabbar = false, compact_tabs = true },
  kitty = { chrome = true, always_tabbar = false, compact_tabs = false },
})
check("rules.nobar.chromium", nobar["chromium"], true)
check("rules.always.chromium", always["chromium"], nil)
check("rules.compact.chromium", compact["chromium"], nil)
check("rules.always.zed", always["zed"], true)
check("rules.compact.zed", compact["zed"], true)
check("rules.nobar.zed", nobar["zed"], nil)
check("rules.compact.foot", compact["foot"], true)
check("rules.always.foot", always["foot"], nil)
check("rules.kitty", nobar["kitty"] == nil and always["kitty"] == nil and compact["kitty"] == nil, true)

local ctonly = settings.parse_apps(settings.apps_section('{"options":{},"apps":{"Foot":{"compactTabs":true}}}'))
check("apps.foot.compactTabs", ctonly["foot"].compact_tabs, true)
check("apps.foot.alwaysTabbar.default", ctonly["foot"].always_tabbar, false)

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
