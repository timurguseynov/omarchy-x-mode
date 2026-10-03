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

    function test_parseApps_object() {
        var s = Logic.parseApps('{"Chromium":{"chrome":false,"alwaysTabbar":true,"ctrlW":true,"ctrlAsSuper":true,"ctrlCShift":true,"ctrlClick":true,"digitTabs":true},"Zed":{}}')
        compare(s["chromium"].chrome, false)
        compare(s["chromium"].alwaysTabbar, true)
        compare(s["chromium"].ctrlW, true)
        compare(s["chromium"].ctrlAsSuper, true)
        compare(s["chromium"].ctrlCShift, true)
        compare(s["chromium"].ctrlClick, true)
        compare(s["chromium"].digitTabs, true)
        compare(s["chromium"].ctrlAsSuperKeys.length, 0)
        compare(s["zed"].chrome, true)
        compare(s["zed"].alwaysTabbar, false)
        compare(s["zed"].ctrlW, false)
        compare(s["zed"].ctrlAsSuper, false)
        compare(s["zed"].ctrlCShift, false)
        compare(s["zed"].ctrlClick, false)
        compare(s["zed"].digitTabs, false)
        compare(s["zed"].ctrlAsSuperKeys.length, 0)
    }

    function test_parseApps_accepts_object() {
        var s = Logic.parseApps({ "Foot": { chrome: false } })
        compare(s["foot"].chrome, false)
        compare(s["foot"].ctrlW, false)
        compare(s["foot"].ctrlAsSuper, false)
        compare(s["foot"].ctrlCShift, false)
        compare(s["foot"].digitTabs, false)
    }

    function test_parseApps_legacy_array() {
        var s = Logic.parseApps('["Foot","Kitty"]')
        compare(s["foot"].chrome, false)
        compare(s["kitty"].chrome, false)
        compare(s["kitty"].ctrlW, false)
        compare(s["kitty"].ctrlAsSuper, false)
        compare(s["kitty"].ctrlCShift, false)
        compare(s["kitty"].digitTabs, false)
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
        compare(dflt.ctrlW, false)
        compare(dflt.ctrlAsSuper, false)
        compare(dflt.ctrlCShift, false)
        compare(dflt.ctrlClick, false)
        compare(dflt.digitTabs, false)
        compare(dflt.ctrlAsSuperKeys.length, 0)
        var off = Logic.panelCfgFor({ "zed": { chrome: false } }, "ZED")
        compare(off.chrome, false)
        compare(Logic.panelCfgFor({ "zed": { ctrlW: true } }, "zed").ctrlW, true)
        compare(Logic.mergePanelCfg({ "a": { chrome: false } }, "b", true, false, false, false, false).b, undefined, "default is dropped")
        var kept = Logic.mergePanelCfg({}, "b", false, false, false, false, false)
        compare(kept.b.chrome, false)
        var ctrl = Logic.mergePanelCfg({}, "chrome", true, false, true, false, false)
        compare(ctrl.chrome.ctrlW, true, "ctrlW alone keeps the entry")
        var supermap = Logic.mergePanelCfg({}, "chrome", true, false, false, true, false)
        compare(supermap.chrome.ctrlAsSuper, true, "ctrlAsSuper alone keeps the entry")
        var clip = Logic.mergePanelCfg({}, "zed", true, false, false, false, true)
        compare(clip.zed.ctrlCShift, true, "ctrlCShift alone keeps the entry")
        var click = Logic.mergePanelCfg({}, "zed", true, false, false, false, false, true)
        compare(click.zed.ctrlClick, true, "ctrlClick alone keeps the entry")
        var digits = Logic.mergePanelCfg({}, "foot", true, false, false, false, false, false, [], true)
        compare(digits.foot.digitTabs, true, "digitTabs alone keeps the entry")
        var both = Logic.mergePanelCfg({}, "foot", true, false, false, true, false, false, [], true)
        compare(both.foot.digitTabs, true, "the reserve switch survives alongside the Ctrl flag")
        compare(both.foot.ctrlAsSuper, true)
        compare(Logic.mergePanelCfg({}, "", true, false, false, false, false), null, "empty class")
    }

    function test_setPanelFlag() {
        var chrome = Logic.setPanelFlag({}, "Chromium", "ctrlAsSuper", true)
        compare(chrome.chromium.ctrlAsSuper, true)
        compare(chrome.chromium.chrome, true)
        var two = Logic.setPanelFlag(chrome, "chromium", "ctrlW", true)
        compare(two.chromium.ctrlAsSuper, true, "the other flag is kept")
        compare(two.chromium.ctrlW, true)
        var digits = Logic.setPanelFlag(two, "chromium", "digitTabs", true)
        compare(digits.chromium.digitTabs, true)
        compare(digits.chromium.ctrlW, true, "the reserve switch keeps the other flags")
        var back = Logic.setPanelFlag(digits, "chromium", "ctrlAsSuper", false)
        compare(back.chromium.ctrlAsSuper, false, "cleared")
        compare(back.chromium.ctrlW, true, "the entry stays while a flag is on")
        var noDigits = Logic.setPanelFlag(back, "chromium", "digitTabs", false)
        compare(noDigits.chromium.digitTabs, false, "the reserve switch is cleared too")
        var none = Logic.setPanelFlag(noDigits, "chromium", "ctrlW", false)
        compare(none.chromium, undefined, "the entry is dropped at the default")
        compare(Logic.setPanelFlag({}, "", "ctrlW", true), null, "empty class")
    }

    function test_occupiedKeys() {
        var parsed = Logic.parseApps('{"Chromium":{"ctrlAsSuperKeys":["Q","TAB"]}}')
        compare(parsed["chromium"].ctrlAsSuperKeys.length, 2)
        compare(parsed["chromium"].ctrlAsSuperKeys[0], "Q")
        compare(parsed["chromium"].ctrlAsSuperKeys[1], "TAB")
        var on = Logic.setOccupiedKey({}, "Chromium", "Q", true)
        compare(on.chromium.ctrlAsSuperKeys.length, 1)
        compare(on.chromium.ctrlAsSuperKeys[0], "Q")
        compare(Logic.hasOccupiedKey(on.chromium, "Q"), true)
        compare(Logic.hasOccupiedKey(on.chromium, "TAB"), false)
        var two = Logic.setOccupiedKey(on, "chromium", "TAB", true)
        compare(two.chromium.ctrlAsSuperKeys.length, 2, "a second key is kept")
        var flag = Logic.setPanelFlag(two, "chromium", "ctrlAsSuper", true)
        compare(flag.chromium.ctrlAsSuper, true)
        compare(flag.chromium.ctrlAsSuperKeys.length, 2, "steals survive another flag")
        var off = Logic.setOccupiedKey(flag, "chromium", "Q", false)
        compare(Logic.hasOccupiedKey(off.chromium, "Q"), false)
        compare(Logic.hasOccupiedKey(off.chromium, "TAB"), true)
        var none = Logic.setOccupiedKey(Logic.setPanelFlag(off, "chromium", "ctrlAsSuper", false), "chromium", "TAB", false)
        compare(none.chromium, undefined, "the entry is dropped at the default")
        compare(Logic.setOccupiedKey({}, "", "Q", true), null, "empty class")
        compare(Logic.stealToggleLabel("⌘+Q"), "⌘+Q as Ctrl+Q")
        compare(Logic.stealToggleLabel("⌘+⇧+Tab"), "⌘+⇧+Tab as Ctrl+⇧+Tab")
        compare(Logic.stealToggleLabel(""), "")
        compare(Logic.setOccupiedKey({}, "chromium", "", true), null, "empty key")
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
