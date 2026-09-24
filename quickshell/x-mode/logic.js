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
