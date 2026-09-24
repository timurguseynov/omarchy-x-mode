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
}
