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
}
