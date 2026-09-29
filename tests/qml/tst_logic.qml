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
        var s = Logic.parseApps('{"Chromium":{"chrome":false,"alwaysTabbar":true},"Zed":{}}')
        compare(s["chromium"].chrome, false)
        compare(s["chromium"].alwaysTabbar, true)
        compare(s["zed"].chrome, true)
        compare(s["zed"].alwaysTabbar, false)
    }

    function test_parseApps_accepts_object() {
        var s = Logic.parseApps({ "Foot": { chrome: false } })
        compare(s["foot"].chrome, false)
    }

    function test_parseApps_legacy_array() {
        var s = Logic.parseApps('["Foot","Kitty"]')
        compare(s["foot"].chrome, false)
        compare(s["kitty"].chrome, false)
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
