import QtQuick
import QtTest
import "../../quickshell/x-mode/logic.js" as Logic

// Unit tests for the pure JS the shell plugin shares (logic.js). Runs with
// qmltestrunner and no Quickshell runtime, so no compositor is needed.
TestCase {
    name: "Logic"

    function test_parseEnabled() {
        compare(Logic.parseEnabled("on"), true)
        compare(Logic.parseEnabled("ON"), true)
        compare(Logic.parseEnabled(" 1 "), true)
        compare(Logic.parseEnabled("true"), true)
        compare(Logic.parseEnabled(""), true)
        compare(Logic.parseEnabled("off"), false)
        compare(Logic.parseEnabled("0"), false)
        compare(Logic.parseEnabled("False"), false)
        compare(Logic.parseEnabled("garbage"), null, "unknown leaves the state alone")
        compare(Logic.parseEnabled(null), true, "missing file reads as on")
    }

    function test_shellQuote() {
        compare(Logic.shellQuote("abc"), "'abc'")
        compare(Logic.shellQuote("a'b"), "'a'\\''b'")
        compare(Logic.shellQuote(""), "''")
    }

    // A watched state file is written by truncating it first, so a reader can
    // land in the middle of a write. Every such read goes through an "answer"
    // helper: the state, or nothing -- never a default that blanks what the
    // component is showing.
    function test_readJsonAnswer() {
        compare(Logic.readJsonAnswer(""), null, "a torn read is not an answer")
        compare(Logic.readJsonAnswer("   \n"), null, "whitespace is a torn read too")
        compare(Logic.readJsonAnswer('{"options":{"keys":'), null, "a half-written object is not an answer")
        compare(Logic.readJsonAnswer("null"), null, "the word null is not a state")
        compare(Logic.readJsonAnswer(null), null)
        verify(Array.isArray(Logic.readJsonAnswer("[]")), "a real empty list is an answer")
        compare(Logic.readJsonAnswer("[]").length, 0, "and clears the list")
        compare(Object.keys(Logic.readJsonAnswer('{}')).length, 0, "a real empty object is an answer")
        compare(Logic.readJsonAnswer('{"options":{"noGaps":true}}').options.noGaps, true)
    }

    function test_readEnabledLine() {
        compare(Logic.readEnabledLine(""), null, "a torn read is not a state")
        compare(Logic.readEnabledLine("  \n"), null)
        compare(Logic.readEnabledLine(null), null, "an absent read is not one either")
        compare(Logic.readEnabledLine("on"), true)
        compare(Logic.readEnabledLine("off"), false)
        compare(Logic.readEnabledLine("garbage"), null, "unknown still leaves the state alone")
    }

    function test_stateWriteCommand() {
        var cmd = Logic.stateWriteCommand("/home/u/.config/hypr/x-mode.json", '{"a":"b"}', "hyprctl reload >/dev/null")
        verify(cmd.indexOf("mkdir -p '/home/u/.config/hypr'") === 0, "the parent directory is made first")
        verify(cmd.indexOf("> '/home/u/.config/hypr/x-mode.json.tmp'") >= 0, "the text goes to a sibling temp file")
        verify(cmd.indexOf("mv -f '/home/u/.config/hypr/x-mode.json.tmp' '/home/u/.config/hypr/x-mode.json'") >= 0,
               "the target is replaced, never truncated in place")
        verify(cmd.indexOf("hyprctl reload") > cmd.indexOf("mv -f"), "the follow-up runs after the file is in place")
        var tricky = Logic.stateWriteCommand("/tmp/x.json", "it's $HOME `id`", "")
        verify(tricky.indexOf(Logic.shellQuote("it's $HOME `id`")) >= 0, "the text stays one argument")
        verify(tricky.slice(-4) !== " && ", "no follow-up, no trailing chain")
        verify(Logic.stateWriteCommand("x.json", "a", "").indexOf("mkdir -p '.'") === 0, "a bare name writes in the cwd")
    }

    function test_parseApps_object() {
        var s = Logic.parseApps('{"Chromium":{"chrome":false,"alwaysTabbar":true,"ctrlW":true,"ctrlAsSuper":true,"ctrlCShift":true,"ctrlClick":true,"digitTabs":true,"ctrlTabSwitch":false,"ctrlAsSuperKeysOff":["F"]},"Zed":{}}')
        compare(s["chromium"].chrome, false)
        compare(s["chromium"].alwaysTabbar, true)
        compare(s["chromium"].ctrlW, true)
        compare(s["chromium"].ctrlAsSuper, true)
        compare(s["chromium"].ctrlCShift, true)
        compare(s["chromium"].ctrlClick, true)
        compare(s["chromium"].digitTabs, true)
        compare(s["chromium"].ctrlTabSwitch, false, "an explicit false is Always off")
        compare(s["chromium"].ctrlAsSuperKeys.length, 0)
        compare(s["chromium"].ctrlAsSuperKeysOff.length, 1)
        compare(s["zed"].chrome, true)
        compare(s["zed"].alwaysTabbar, false)
        // Absent is not false: it is "follow the desktop".
        compare(s["zed"].ctrlW, undefined)
        compare(s["zed"].ctrlAsSuper, undefined)
        compare(s["zed"].ctrlCShift, undefined)
        compare(s["zed"].ctrlClick, undefined)
        compare(s["zed"].digitTabs, undefined)
        compare(s["zed"].ctrlTabSwitch, undefined)
        compare(s["zed"].ctrlAsSuperKeys.length, 0)
    }

    function test_parseApps_accepts_object() {
        var s = Logic.parseApps({ "Foot": { chrome: false } })
        compare(s["foot"].chrome, false)
        compare(s["foot"].ctrlW, undefined)
        compare(s["foot"].ctrlAsSuper, undefined)
        compare(s["foot"].ctrlCShift, undefined)
        compare(s["foot"].digitTabs, undefined)
    }

    function test_parseApps_legacy_array() {
        var s = Logic.parseApps('["Foot","Kitty"]')
        compare(s["foot"].chrome, false)
        compare(s["kitty"].chrome, false)
        compare(s["kitty"].ctrlW, undefined)
        compare(s["kitty"].ctrlAsSuper, undefined)
        compare(s["kitty"].ctrlCShift, undefined)
        compare(s["kitty"].digitTabs, undefined)
    }

    function test_parseApps_invalid() {
        compare(Object.keys(Logic.parseApps("not json")).length, 0)
    }

    function test_cleanName() {
        compare(Logic.cleanName("org.gnome.Nautilus"), "gnome.nautilus")
        compare(Logic.cleanName("dev.zed.Zed"), "zed.zed")
        compare(Logic.cleanName("com.example.App.desktop"), "example.app")
        compare(Logic.cleanName(""), "")
    }

    function test_lastSegment() {
        compare(Logic.lastSegment("dev.zed.Zed"), "Zed")
        compare(Logic.lastSegment("org.gnome.Nautilus"), "Nautilus")
        compare(Logic.lastSegment("foot"), "foot")
    }

    function test_iconLetter() {
        compare(Logic.iconLetter("xdg-desktop-portal-gtk"), "X")
        compare(Logic.iconLetter("dev.zed.Zed"), "Z")
        compare(Logic.iconLetter("foot"), "F")
        compare(Logic.iconLetter("org.omarchy.agent"), "A")
        compare(Logic.iconLetter(""), "")
        compare(Logic.iconLetter("---"), "")
    }

    function test_webappHostFromExec() {
        compare(Logic.webappHostFromExec("omarchy-launch-webapp https://app.zoom.us/wc/123"), "app.zoom.us")
        compare(Logic.webappHostFromExec("chromium --app=https://www.example.com/x"), "example.com")
        compare(Logic.webappHostFromExec("firefox https://example.com"), "", "not a web app")
        compare(Logic.webappHostFromExec(""), "")
    }

    function test_parseSwitcherCmd_show() {
        var m = Logic.parseSwitcherCmd("show Zed zed|addr:1 foot|addr:2", true)
        compare(m.shown, true)
        compare(m.activeClass, "Zed")
        compare(m.classes.length, 2)
        compare(m.classes[0].cls, "zed")
        compare(m.classes[0].addr, "addr:1")
        compare(m.classes[1].cls, "foot")
    }

    function test_parseSwitcherCmd_hide_and_disabled() {
        compare(Logic.parseSwitcherCmd("hide", true).shown, false)
        compare(Logic.parseSwitcherCmd("show Zed zed|a", false).shown, false, "off means hidden")
        compare(Logic.parseSwitcherCmd("show", true).shown, false, "needs a class")
    }

    function test_parseSnapCmd_show() {
        var m = Logic.parseSnapCmd("show 12 64 900 1000", true)
        compare(m.shown, true)
        compare(m.x, 12)
        compare(m.y, 64)
        compare(m.w, 900)
        compare(m.h, 1000)
    }

    function test_parseSnapCmd_rejects_bad() {
        compare(Logic.parseSnapCmd("show 12 64 0 1000", true).shown, false, "zero width")
        compare(Logic.parseSnapCmd("show 12 64 900", true).shown, false, "too few fields")
        compare(Logic.parseSnapCmd("hide", true).shown, false)
        compare(Logic.parseSnapCmd("show 12 64 900 1000", false).shown, false, "off means hidden")
    }

    function test_iconScanCommand_covers_symbolic_categories() {
        var cmd = Logic.iconScanCommand()
        verify(cmd.indexOf("categories") !== -1, "portal dialogs ship category icons (applications-system-symbolic)")
        verify(cmd.indexOf("apps") !== -1, "app icons still scanned")
        verify(cmd.indexOf("pixmaps") !== -1, "pixmaps still scanned")
    }

    function test_togglePinInList() {
        compare(Logic.togglePinInList(["a", "b"], "b"), ["a"])
        compare(Logic.togglePinInList(["a"], "c"), ["a", "c"])
        compare(Logic.togglePinInList([], "a"), ["a"])
    }

    function test_movePinInList() {
        compare(Logic.movePinInList(["a", "b", "c"], 0, 2), ["b", "c", "a"])
        compare(Logic.movePinInList(["a", "b", "c"], 2, 0), ["c", "a", "b"])
        compare(Logic.movePinInList(["a", "b"], 0, 0), null, "no-op is invalid")
        compare(Logic.movePinInList(["a"], -1, 0), null, "out of range")
        compare(Logic.movePinInList(["a"], 0, 5), null, "out of range")
    }

    function test_pinSlotIndex() {
        compare(Logic.pinSlotIndex(13, 0, 0, 32, 26, 3), 0, "slot center")
        compare(Logic.pinSlotIndex(45, 0, 1, 32, 26, 3), 1, "next slot center")
        compare(Logic.pinSlotIndex(40, 0, 0, 32, 26, 3), 0, "hysteresis holds while hover is the origin")
        compare(Logic.pinSlotIndex(-50, 0, 0, 32, 26, 3), 0, "clamped top")
        compare(Logic.pinSlotIndex(500, 0, 0, 32, 26, 3), 2, "clamped bottom")
        compare(Logic.pinSlotIndex(15, 0, 0, 32, 26, 3), 0, "hysteresis holds the origin slot")
        compare(Logic.pinSlotIndex(0, 0, 0, 0, 26, 3), 0, "zero stride")
    }

    function mkMenuApp() {
        return {
            cls: "foot", pinned: false, addrs: ["0x1"],
            wins: [
                { addr: "0x2", title: "second", ws: "2", focus: 1 },
                { addr: "0x1", title: "first", ws: "1", focus: 0 }
            ]
        }
    }

    function test_buildMenuActions_orders_windows() {
        var r = Logic.buildMenuActions(mkMenuApp(), [mkMenuApp()], "Foot", false)
        compare(r.app.cls, "foot")
        var ids = []
        for (var i = 0; i < r.actions.length; i++)
            ids.push(r.actions[i].id)
        compare(ids, ["new", "sep", "win:0x1", "win:0x2", "sep", "pin", "close"])
        compare(r.actions[0].label, "New Foot")
    }

    function test_buildMenuActions_single_and_pinned() {
        var single = Logic.buildMenuActions(mkMenuApp(), [mkMenuApp()], "Foot", true)
        verify(single.actions[0].id !== "new", "no new window for single-instance")
        var pinned = mkMenuApp()
        pinned.pinned = true
        var r = Logic.buildMenuActions(pinned, [pinned], "Foot", false)
        var ids = []
        for (var j = 0; j < r.actions.length; j++)
            ids.push(r.actions[j].id)
        verify(ids.indexOf("unpin") !== -1, "pinned app offers unpin")
    }

    function mkPanelRunning() {
        return [
            { cls: "org.gnome.Nautilus", title: "Downloads" },
            { cls: "foot", title: "term" }
        ]
    }

    function test_filterPanelApps() {
        var names = { "org.gnome.Nautilus": "Files" }
        function nm(cls) { return names[cls] || cls }
        compare(Logic.filterPanelApps(mkPanelRunning(), "", nm).length, 2, "empty query matches all")
        compare(Logic.filterPanelApps(mkPanelRunning(), "nau", nm)[0].cls, "org.gnome.Nautilus", "class matches")
        compare(Logic.filterPanelApps(mkPanelRunning(), "files", nm)[0].cls, "org.gnome.Nautilus", "display name matches")
        compare(Logic.filterPanelApps(mkPanelRunning(), "DOWN", nm)[0].cls, "org.gnome.Nautilus", "title matches, case-insensitive")
        compare(Logic.filterPanelApps(mkPanelRunning(), "zzz", nm).length, 0)
    }

    function test_findPanelApp() {
        var r = Logic.findPanelApp(mkPanelRunning(), "FOOT")
        compare(r.title, "term", "class matches case-insensitively")
        compare(Logic.findPanelApp(mkPanelRunning(), ""), null)
        var missing = Logic.findPanelApp(mkPanelRunning(), "zed")
        compare(missing.cls, "zed")
        compare(missing.title, "")
    }

    function test_panelCfg() {
        var dflt = Logic.panelCfgFor({}, "Zed")
        compare(dflt.chrome, true)
        compare(dflt.alwaysTabbar, false)
        compare(dflt.ctrlW, undefined)
        compare(dflt.ctrlAsSuper, undefined)
        compare(dflt.ctrlCShift, undefined)
        compare(dflt.ctrlClick, undefined)
        compare(dflt.digitTabs, undefined)
        compare(dflt.ctrlAsSuperKeys.length, 0)
        compare(dflt.ctrlAsSuperKeysOff.length, 0)
        var off = Logic.panelCfgFor({ "zed": { chrome: false } }, "ZED")
        compare(off.chrome, false)
        compare(Logic.panelCfgFor({ "zed": { ctrlW: true } }, "zed").ctrlW, true)
        compare(Logic.panelCfgFor({ "zed": { ctrlW: false } }, "zed").ctrlW, false, "Always off survives the read")
        // The merge takes the config object, so an unset flag stays unset.
        compare(Logic.mergePanelCfg({ "a": { chrome: false } }, "b", { chrome: true }).b, undefined, "default is dropped")
        var kept = Logic.mergePanelCfg({}, "b", { chrome: false })
        compare(kept.b.chrome, false)
        var ctrl = Logic.mergePanelCfg({}, "chrome", { chrome: true, ctrlW: true })
        compare(ctrl.chrome.ctrlW, true, "a pinned flag keeps the entry")
        compare(ctrl.chrome.chrome, true)
        var off2 = Logic.mergePanelCfg({}, "zed", { chrome: true, ctrlAsSuper: false })
        compare(off2.zed.ctrlAsSuper, false, "Always off is written out")
        var inherit = Logic.mergePanelCfg({}, "zed", { chrome: true, ctrlAsSuper: undefined })
        compare(inherit.zed, undefined, "inheriting everything is not an entry")
        var keys = Logic.mergePanelCfg({}, "foot", { chrome: true, ctrlW: true, ctrlAsSuperKeys: ["Q"] })
        compare(keys.foot.ctrlAsSuperKeys.length, 1)
        compare(keys.foot.ctrlW, true, "flags and keys keep each other")
        compare(Logic.mergePanelCfg({}, "", { chrome: true }), null, "empty class")
    }

    function test_setPanelFlag() {
        var chrome = Logic.setPanelFlag({}, "Chromium", "chrome", false)
        compare(chrome.chromium.chrome, false)
        var tabbar = Logic.setPanelFlag(chrome, "chromium", "alwaysTabbar", true)
        compare(tabbar.chromium.alwaysTabbar, true, "the other flag is kept")
        compare(tabbar.chromium.chrome, false)
        var back = Logic.setPanelFlag(tabbar, "chromium", "alwaysTabbar", false)
        compare(back.chromium.alwaysTabbar, false, "cleared")
        compare(back.chromium.chrome, false, "the entry stays while chrome is off")
        var none = Logic.setPanelFlag(back, "chromium", "chrome", true)
        compare(none.chromium, undefined, "the entry is dropped at the default")
        compare(Logic.setPanelFlag({}, "", "chrome", true), null, "empty class")
    }

    function test_setKeyFlag() {
        var on = Logic.setKeyFlag({}, "Zed", "ctrlAsSuper", "on")
        compare(on.zed.ctrlAsSuper, true)
        var both = Logic.setKeyFlag(on, "zed", "digitTabs", "off")
        compare(both.zed.digitTabs, false, "a pin against the desktop is kept")
        compare(both.zed.ctrlAsSuper, true, "the other pin is kept")
        var cycle = Logic.setKeyFlag(both, "zed", "ctrlAsSuper", "inherit")
        compare(cycle.zed.ctrlAsSuper, undefined, "inherit clears the app's own answer")
        compare(cycle.zed.digitTabs, false)
        var none = Logic.setKeyFlag(cycle, "zed", "digitTabs", "inherit")
        compare(none.zed, undefined, "nothing left means no entry")
        compare(Logic.setKeyFlag({}, "", "ctrlW", "on"), null, "empty class")
        compare(Logic.setKeyFlag({}, "zed", "nonsense", "on"), null, "unknown flag")
    }

    function test_keyFlagState() {
        // Following the desktop, nothing pinned: the row reads the desktop's answer.
        var follow = Logic.keyFlagState({}, { ctrlW: true }, "ctrlW")
        compare(follow.state, "inherit")
        compare(follow.checked, true, "an inherited on looks on")
        compare(follow.global, true)
        compare(follow.pinned, false)
        var followOff = Logic.keyFlagState({}, {}, "ctrlW")
        compare(followOff.checked, false)
        // Pinned against the desktop: Always off wins, Always on wins the other way.
        var pinnedOff = Logic.keyFlagState({ ctrlW: false }, { ctrlW: true }, "ctrlW")
        compare(pinnedOff.state, "off")
        compare(pinnedOff.checked, false, "Always off beats a global on")
        compare(pinnedOff.pinned, true)
        var pinnedOn = Logic.keyFlagState({ ctrlW: true }, {}, "ctrlW")
        compare(pinnedOn.state, "on")
        compare(pinnedOn.checked, true, "Always on beats a global off")
        compare(pinnedOn.pinned, true)
        var other = Logic.keyFlagState({}, { ctrlAsSuper: true }, "ctrlW")
        compare(other.checked, false, "another flag being forced is not this one")
    }

    function test_keyFlagCycle() {
        // inherit -> Always on -> Always off -> inherit.
        compare(Logic.nextKeyFlagState("inherit"), "on")
        compare(Logic.nextKeyFlagState("on"), "off")
        compare(Logic.nextKeyFlagState("off"), "inherit")
        compare(Logic.keyFlagDescription("on", false), "Always on")
        compare(Logic.keyFlagDescription("off", true), "Always off")
        compare(Logic.keyFlagDescription("inherit", true), "Follows the desktop: on")
        compare(Logic.keyFlagDescription("inherit", false), "Follows the desktop: off")
    }

    function test_keyStealState() {
        var cfg = { ctrlAsSuperKeys: ["Q"], ctrlAsSuperKeysOff: [] }
        var on = Logic.keyStealState(cfg, {}, "Q")
        compare(on.state, "on")
        compare(on.checked, true)
        var off = Logic.keyStealState({ ctrlAsSuperKeysOff: ["Q"] }, { steal: ["Q"] }, "Q")
        compare(off.state, "off", "an Always off list beats the desktop's steal")
        compare(off.checked, false)
        var follow = Logic.keyStealState({ ctrlAsSuperKeys: [], ctrlAsSuperKeysOff: [] }, { steal: ["Q"] }, "Q")
        compare(follow.state, "inherit")
        compare(follow.checked, true, "an inherited steal looks stolen")
        compare(follow.pinned, false)
        compare(Logic.keyStealState({}, { steal: ["TAB"] }, "Q").checked, false)
    }

    function test_setOccupiedKey() {
        var on = Logic.setOccupiedKey({}, "Zed", "Q", "on")
        compare(on.zed.ctrlAsSuperKeys.length, 1)
        var off = Logic.setOccupiedKey(on, "zed", "Q", "off")
        compare(off.zed.ctrlAsSuperKeys, undefined, "Always off replaces Always on rather than adding")
        compare(off.zed.ctrlAsSuperKeysOff.length, 1)
        var back = Logic.setOccupiedKey(off, "zed", "Q", "inherit")
        compare(back.zed, undefined, "inherit clears both lists")
        compare(Logic.setOccupiedKey({}, "zed", "", "on"), null, "empty id")
    }

    // The rows say a three-state ("inherit"/"on"/"off") and a plain switch says
    // true/false -- and the QML signal that carries it declared its parameter a
    // bool, which turns "on" into true before the JS ever sees it. A state that
    // misses every comparison used to *clear* the pin instead of setting it (the
    // switch blinked, the file was rewritten without the flag, and the panel read
    // it back as off). Both spellings have to mean the same thing.
    function test_keyFlagStatesSpellingsAgree() {
        var t = Logic.setKeyFlag({}, "zed", "ctrlTabSwitch", true)
        compare(t.zed.ctrlTabSwitch, true, "a bool true pins the flag on")
        var f = Logic.setKeyFlag(t, "zed", "ctrlTabSwitch", false)
        compare(f.zed.ctrlTabSwitch, false, "a bool false pins it off")
        var i = Logic.setKeyFlag(f, "zed", "ctrlTabSwitch", "inherit")
        compare(i.zed === undefined, true, "inherit clears the pin")
        var s = Logic.setKeyFlag({}, "zed", "ctrlTabSwitch", "on")
        compare(s.zed.ctrlTabSwitch, true, "the string spelling still pins it on")
    }

    function test_setOccupiedKeySpellings() {
        var on = Logic.setOccupiedKey({}, "zed", "Q", true)
        compare(on.zed.ctrlAsSuperKeys.indexOf("Q"), 0, "a bool true steals the key")
        var off = Logic.setOccupiedKey(on, "zed", "Q", false)
        compare(off.zed.ctrlAsSuperKeysOff.indexOf("Q"), 0, "a bool false refuses it")
        var s = Logic.setOccupiedKey({}, "zed", "Q", "on")
        compare(s.zed.ctrlAsSuperKeys.indexOf("Q"), 0, "the string spelling still steals it")
    }

    function test_themeAccents() {
        var a = Logic.parseThemeAccents('background = "#111111"\ngreen = "#2ecc71"\nred = "#e74c3c"\n')
        compare(a.green, "#2ecc71")
        compare(a.red, "#e74c3c")
        var missing = Logic.parseThemeAccents('background = "#111111"\n')
        compare(missing.green, undefined, "a theme without the names leaves the caller a fallback")
        compare(Logic.parseThemeAccents("junk").red, undefined)
        compare(Logic.parseThemeAccents('green = "#abc"\n').green, "#abc", "short hex too")
    }

    function test_globalKeys() {
        // The global scope renders as the same shape the card uses.
        var cfg = Logic.globalScopeCfg({ ctrlAsSuper: true, steal: ["Q", "TAB"] })
        compare(cfg.ctrlAsSuper, true)
        compare(cfg.ctrlW, false)
        compare(cfg.ctrlAsSuperKeys.length, 2)

        var one = Logic.setGlobalFlag({}, "ctrlW", true)
        compare(one.ctrlW, true)
        compare(one.ctrlAsSuper, undefined)
        var both = Logic.setGlobalFlag(one, "digitTabs", true)
        compare(both.ctrlW, true, "the other flag is kept")
        compare(both.digitTabs, true)
        var cleared = Logic.setGlobalFlag(both, "ctrlW", false)
        compare(cleared.ctrlW, undefined, "off removes the key rather than storing false")
        compare(cleared.digitTabs, true)
        compare(Logic.setGlobalFlag({ ctrlW: true }, "nonsense", true), null, "unknown flag")

        var stolen = Logic.setGlobalSteal({ ctrlW: true }, "Q", true)
        compare(stolen.steal.length, 1)
        compare(stolen.steal[0], "Q")
        compare(stolen.ctrlW, true, "stealing keeps the flags")
        var two = Logic.setGlobalSteal(stolen, "TAB", true)
        compare(two.steal.length, 2)
        var back = Logic.setGlobalSteal(two, "Q", false)
        compare(back.steal.length, 1)
        compare(back.steal[0], "TAB")
        compare(Logic.setGlobalSteal(back, "TAB", false).steal, undefined, "an empty list is dropped")

        compare(Logic.globalKeysSummary({}), "Nothing set for every app")
        compare(Logic.globalKeysSummary({ ctrlW: true }), "1 replacement for every app")
        compare(Logic.globalKeysSummary({ ctrlW: true, ctrlAsSuper: true }), "2 replacements for every app")
        compare(Logic.globalKeysSummary({ steal: ["Q"] }), "1 key for every app")
        compare(Logic.globalKeysSummary({ ctrlW: true, steal: ["Q", "TAB"] }), "1 replacement, 2 keys for every app")
        compare(Logic.hasGlobalSteal({ steal: ["Q"] }, "Q"), true)
        compare(Logic.hasGlobalSteal({ steal: ["Q"] }, "TAB"), false)
        compare(Logic.hasGlobalSteal({}, "Q"), false)

        compare(Logic.appKeysSummary({}, {}), "Off: Super keys reach the app as they are")
        compare(Logic.appKeysSummary({ ctrlW: true }, {}), "1 replacement, pinned here")
        compare(Logic.appKeysSummary({ ctrlW: true, ctrlAsSuperKeys: ["Q"] }, {}), "1 replacement, 1 key, pinned here")
        compare(Logic.appKeysSummary({}, { ctrlW: true }), "1 replacement", "inherited from the desktop, so not pinned")
        compare(Logic.appKeysSummary({ ctrlW: false }, { ctrlW: true }), "Off here: pinned against the desktop")
    }

    function test_occupiedKeys() {
        var parsed = Logic.parseApps('{"Chromium":{"ctrlAsSuperKeys":["Q","TAB"]}}')
        compare(parsed["chromium"].ctrlAsSuperKeys.length, 2)
        compare(parsed["chromium"].ctrlAsSuperKeys[0], "Q")
        compare(parsed["chromium"].ctrlAsSuperKeys[1], "TAB")
        var on = Logic.setOccupiedKey({}, "Chromium", "Q", "on")
        compare(on.chromium.ctrlAsSuperKeys.length, 1)
        compare(on.chromium.ctrlAsSuperKeys[0], "Q")
        compare(Logic.hasOccupiedKey(on.chromium, "Q"), true)
        compare(Logic.hasOccupiedKey(on.chromium, "TAB"), false)
        var two = Logic.setOccupiedKey(on, "chromium", "TAB", "on")
        compare(two.chromium.ctrlAsSuperKeys.length, 2, "a second key is kept")
        var flag = Logic.setKeyFlag(two, "chromium", "ctrlAsSuper", "on")
        compare(flag.chromium.ctrlAsSuper, true)
        compare(flag.chromium.ctrlAsSuperKeys.length, 2, "steals survive another flag")
        var off = Logic.setOccupiedKey(flag, "chromium", "Q", "off")
        compare(Logic.hasOccupiedKey(off.chromium, "Q"), false)
        compare(Logic.hasOccupiedKey(off.chromium, "TAB"), true)
        compare(Logic.hasOccupiedKeyOff(off.chromium, "Q"), true, "Always off is its own list")
        var cleared = Logic.setOccupiedKey(off, "chromium", "Q", "inherit")
        var none = Logic.setOccupiedKey(Logic.setKeyFlag(cleared, "chromium", "ctrlAsSuper", "inherit"), "chromium", "TAB", "inherit")
        compare(none.chromium, undefined, "the entry is dropped once every list is empty")
        compare(Logic.setOccupiedKey({}, "", "Q", "on"), null, "empty class")
        compare(Logic.stealToggleLabel("⌘+Q"), "⌘+Q as Ctrl+Q")
        compare(Logic.stealToggleLabel("⌘+⇧+Tab"), "⌘+⇧+Tab as Ctrl+⇧+Tab")
        compare(Logic.stealToggleLabel(""), "")
        compare(Logic.setOccupiedKey({}, "chromium", "", "on"), null, "empty key")
        var occ = [{ id: "Q", key: "Q", shift: false, label: "Super+Q", description: "Close app" }]
        compare(Logic.sameOccupiedList(occ, [{ id: "Q", key: "Q", shift: false, label: "Super+Q", description: "Close app" }]), true, "same list")
        compare(Logic.sameOccupiedList(occ, [{ id: "Q", key: "Q", shift: false, label: "Super+Q", description: "Quit" }]), false, "description changed")
        compare(Logic.sameOccupiedList(occ, []), false, "length")
        compare(Logic.sameOccupiedList(null, []), true, "empty")
    }

    function test_buildPanelRunning() {
        var clients = [
            { "class": "Foot", mapped: true, title: "old", focusHistoryID: 3 },
            { "class": "foot", mapped: true, title: "new", focusHistoryID: 1 },
            { "class": "zed", mapped: false, title: "x", focusHistoryID: 0 },
            { "class": "", mapped: true, title: "e", focusHistoryID: 0 }
        ]
        var list = Logic.buildPanelRunning(clients, { "sublime_text": { chrome: false } })
        compare(list.length, 2, "unmapped and empty class skipped, cfg-only kept")
        compare(list[0].cls, "foot")
        compare(list[0].title, "new", "best focus wins the title")
        compare(list[1].cls, "sublime_text")
    }

    function test_rectsIntersect() {
        compare(Logic.rectsIntersect({ x: 0, y: 0, w: 100, h: 100 }, { x: 50, y: 50, width: 100, height: 100 }), true)
        compare(Logic.rectsIntersect({ x: 0, y: 0, w: 100, h: 100 }, { x: 100, y: 0, width: 100, height: 100 }), false, "touching edges do not overlap")
        compare(Logic.rectsIntersect({ x: 0, y: 0, w: 100, h: 100 }, { x: 200, y: 200, w: 10, h: 10 }), false)
    }

    function test_samePins() {
        compare(Logic.samePins(["a", "b"], ["a", "b"]), true)
        compare(Logic.samePins(["a"], ["a", "b"]), false, "different length")
        compare(Logic.samePins(["a", "b"], ["b", "a"]), false, "order matters")
        compare(Logic.samePins([], []), true)
        compare(Logic.samePins(null, ["a"]), false)
    }

    function mkClients() {
        return [
            { address: "0x1", "class": "foot", mapped: true, title: "t1", workspace: { id: 1 }, focusHistoryID: 1 },
            { address: "0x2", "class": "foot", mapped: true, title: "t2", workspace: { id: 2 }, focusHistoryID: 0 },
            { address: "0x3", "class": "zed", mapped: true, title: "z", workspace: { id: 1 }, focusHistoryID: 5 },
            { address: "0x4", "class": "hiddenapp", mapped: true, hidden: true, title: "h", workspace: { id: 1 }, focusHistoryID: 2 },
            { address: "0x5", "class": "unmapped", mapped: false, title: "u", workspace: { id: 1 }, focusHistoryID: 3 },
            { address: "0x6", "class": "", mapped: true, title: "e", workspace: { id: 1 }, focusHistoryID: 4 }
        ]
    }

    function test_buildDockApps_groups_and_orders() {
        var apps = Logic.buildDockApps(mkClients(), ["zed", "foot", "missing"])
        compare(apps.length, 3)
        compare(apps[0].cls, "zed")
        compare(apps[0].pinned, true)
        compare(apps[0].running, true)
        compare(apps[1].cls, "foot")
        compare(apps[1].pinned, true)
        compare(apps[1].bestAddr, "0x2", "lowest focusHistoryID wins")
        compare(apps[1].addrs.length, 2)
        compare(apps[1].ws["1"].addr, "0x1")
        compare(apps[1].ws["2"].addr, "0x2")
        compare(apps[2].cls, "missing")
        compare(apps[2].pinned, true)
        compare(apps[2].running, false)
    }

    function test_buildDockApps_unpinned_sorted_and_skips() {
        var apps = Logic.buildDockApps(mkClients(), [])
        compare(apps.length, 2, "hidden, unmapped and empty class are skipped")
        compare(apps[0].cls, "foot")
        compare(apps[1].cls, "zed")
        compare(apps[0].wins.length, 2)
    }

    function test_buildDockApps_pin_moves_running() {
        var clients = [
            { address: "0x1", "class": "foot", mapped: true, title: "t", workspace: { id: 1 }, focusHistoryID: 0 },
            { address: "0x2", "class": "kitty", mapped: true, title: "k", workspace: { id: 1 }, focusHistoryID: 1 }
        ]
        var before = Logic.buildDockApps(clients, [])
        compare(before[0].cls, "foot")
        compare(before[0].pinned, false)
        compare(before[1].cls, "kitty")
        var after = Logic.buildDockApps(clients, Logic.togglePinInList([], "kitty"))
        compare(after[0].cls, "kitty")
        compare(after[0].pinned, true)
        compare(after[0].running, true)
        compare(after[1].cls, "foot")
        compare(after[1].pinned, false)
    }

    function test_dockAppsSig_covers_titles() {
        var a = Logic.buildDockApps(mkClients(), [])
        var b = Logic.buildDockApps(mkClients(), [])
        compare(Logic.dockAppsSig(a), Logic.dockAppsSig(b))
        var moved = mkClients()
        moved[0].title = "elsewhere"
        var c = Logic.buildDockApps(moved, [])
        verify(Logic.dockAppsSig(c) !== Logic.dockAppsSig(a), "a title change moves the sig")
    }
}
