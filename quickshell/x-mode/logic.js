.pragma library

// Pure JS shared by the shell plugin. Kept out of the QML components so it can
// be unit tested with plain qmltestrunner, without a Quickshell runtime or a
// compositor (tests/qml). Nothing here touches QtQuick, Quickshell or `root`.

// "on" / "1" / "true" / "" -> true, "off" / "0" / "false" -> false, anything
// else -> null so the caller leaves its state alone.
function parseEnabled(raw) {
    var s = String(raw || "").trim().toLowerCase()
    if (s === "off" || s === "0" || s === "false")
        return false
    if (s === "on" || s === "1" || s === "true" || s === "")
        return true
    return null
}

function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
}

// The panel's apps map: { "class": { chrome, alwaysTabbar } }. Accepts the
// parsed object (from settings.json) or a raw JSON string (the old apps.json).
// A legacy array of classes means chrome off.
function parseApps(raw) {
    var set = {}
    try {
        var d = typeof raw === "string" ? JSON.parse(raw) : raw
        if (Array.isArray(d)) {
            for (var i = 0; i < d.length; i++)
                set[String(d[i]).toLowerCase()] = { chrome: false, alwaysTabbar: false }
        } else if (d && typeof d === "object") {
            for (var k in d) {
                var e = d[k]
                if (e && typeof e === "object")
                    set[String(k).toLowerCase()] = { chrome: e.chrome !== false, alwaysTabbar: !!e.alwaysTabbar }
                else
                    set[String(k).toLowerCase()] = { chrome: false, alwaysTabbar: false }
            }
        }
    } catch (err) {}
    return set
}

// Normalise a window class into a desktop-entry-ish name: drop a leading
// reverse-DNS vendor and a trailing ".desktop".
function cleanName(cls) {
    return String(cls || "").toLowerCase().trim()
        .replace(/^org\./, "").replace(/^com\./, "").replace(/^io\./, "")
        .replace(/^dev\./, "").replace(/^net\./, "").replace(/^me\./, "")
        .replace(/\.desktop$/, "")
}

// Last reverse-DNS segment: "dev.zed.Zed" -> "Zed", "org.gnome.Nautilus" ->
// "Nautilus".
function lastSegment(name) {
    var parts = String(name || "").split(".")
    return parts.length > 1 ? parts[parts.length - 1] : String(name || "")
}

// Host of a web app's start URL, from the Exec of its desktop entry. Only
// entries that actually launch a web app (omarchy-launch-webapp or --app=) count,
// so a regular app with a URL argument cannot match.
function webappHostFromExec(execString) {
    var s = String(execString || "")
    if (s.indexOf("--app=") === -1 && s.indexOf("omarchy-launch-webapp") === -1)
        return ""
    var m = s.match(/https?:\/\/[^\s"']+/)
    if (!m)
        return ""
    var host = m[0].replace(/^https?:\/\//, "").split("/")[0].split(":")[0].toLowerCase()
    if (host.indexOf("www.") === 0)
        host = host.slice(4)
    return host
}

// The switcher's command file, written by x-mode.lua:
//   show <activeClass> <class|address> ...    (while cycling)
//   hide
// Returns { shown, activeClass, classes: [{ cls, addr }] }.
function parseSwitcherCmd(raw, enabled) {
    if (!enabled)
        return { shown: false, activeClass: "", classes: [] }
    var parts = String(raw || "").trim().split(/\s+/)
    if (parts.length >= 2 && parts[0] === "show") {
        var list = []
        for (var i = 2; i < parts.length; i++) {
            var t = parts[i].split("|")
            list.push({ cls: t[0], addr: t[1] || "" })
        }
        return { shown: true, activeClass: parts[1], classes: list }
    }
    return { shown: false, activeClass: "", classes: [] }
}

// The snap preview command file: show <x> <y> <w> <h> | hide.
// Returns { shown, x, y, w, h } (x/y/w/h only when shown).
function parseSnapCmd(raw, enabled) {
    if (!enabled)
        return { shown: false }
    var parts = String(raw || "").trim().split(/\s+/)
    if (parts.length >= 5 && parts[0] === "show") {
        var x = Number(parts[1]), y = Number(parts[2]), w = Number(parts[3]), h = Number(parts[4])
        if (isFinite(x) && isFinite(y) && isFinite(w) && isFinite(h) && w > 0 && h > 0)
            return { shown: true, x: x, y: y, w: w, h: h }
    }
    return { shown: false }
}

// Axis-aligned rectangle overlap. Reads w/h or width/height, so callers can
// pass QML item boxes straight through.
function rectsIntersect(a, b) {
    var aw = a.w !== undefined ? a.w : a.width
    var ah = a.h !== undefined ? a.h : a.height
    var bw = b.w !== undefined ? b.w : b.width
    var bh = b.h !== undefined ? b.h : b.height
    return a.x < b.x + bw && a.x + aw > b.x && a.y < b.y + bh && a.y + ah > b.y
}
