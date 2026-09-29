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

// Letter drawn in place of an icon that did not load. First letter of the last
// class segment, so "xdg-desktop-portal-gtk" reads "X" and "dev.zed.Zed" reads
// "Z" rather than a vendor initial. Empty when the class has no letter.
function iconLetter(cls) {
    var seg = lastSegment(String(cls || "").trim())
    for (var i = 0; i < seg.length; i++) {
        var c = seg.charAt(i)
        if ((c >= "A" && c <= "Z") || (c >= "a" && c <= "z") || (c >= "0" && c <= "9"))
            return c.toUpperCase()
    }
    return ""
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

// Pin-list equality: a new array resizes the dock card, so the caller skips
// the assign when the list is the same.
function samePins(a, b) {
    if (!a || !b || a.length !== b.length)
        return false
    for (var i = 0; i < a.length; i++) {
        if (a[i] !== b[i])
            return false
    }
    return true
}

// Dock model: group Hyprland clients by class, pinned first in pin order,
// then the running rest sorted. Skips unmapped, hidden and empty-class
// clients. Each entry is { cls, pinned, running, bestAddr, addrs, ws, wins }
// where bestAddr is the window with the lowest focusHistoryID, ws maps
// workspace id -> { addr, title, focus } and wins lists { addr, title, ws,
// focus }. Pure: no QtQuick, no Hyprland, no side effects (the caller clears
// its own "launching" flags and decides whether the sig changed).
function buildDockApps(clients, pinned) {
    var byClass = {}
    var list = clients || []
    for (var i = 0; i < list.length; i++) {
        var c = list[i]
        if (!c || !c.mapped || c.hidden)
            continue
        var cls = String(c.class || "")
        if (cls === "")
            continue
        var e = byClass[cls]
        if (e === undefined) {
            e = { cls: cls, addrs: [], focus: 999999, bestAddr: c.address, ws: {}, wins: [] }
            byClass[cls] = e
        }
        e.addrs.push(c.address)
        var wid = c.workspace ? c.workspace.id : undefined
        var f = c.focusHistoryID
        if (typeof f !== "number")
            f = 999999
        e.wins.push({
            addr: c.address,
            title: String(c.title || "").trim(),
            ws: wid !== undefined && wid !== null ? String(wid) : "",
            focus: f
        })
        if (wid !== undefined && wid !== null) {
            var key = String(wid)
            var prev = e.ws[key]
            if (!prev || f < prev.focus)
                e.ws[key] = { addr: c.address, title: String(c.title || "").trim(), focus: f }
        }
        if (f < e.focus) {
            e.focus = f
            e.bestAddr = c.address
        }
    }
    var out = []
    var seen = {}
    var pins = pinned || []
    for (var p = 0; p < pins.length; p++) {
        var pc = pins[p]
        if (seen[pc])
            continue
        seen[pc] = true
        var r = byClass[pc]
        out.push({ cls: pc, pinned: true, running: r !== undefined, bestAddr: r ? r.bestAddr : "", addrs: r ? r.addrs : [], ws: r ? r.ws : {}, wins: r ? r.wins : [] })
    }
    var rest = []
    for (var k in byClass) {
        if (!seen[k])
            rest.push(k)
    }
    rest.sort()
    for (var j = 0; j < rest.length; j++) {
        var rk = rest[j]
        out.push({ cls: rk, pinned: false, running: true, bestAddr: byClass[rk].bestAddr, addrs: byClass[rk].addrs, ws: byClass[rk].ws, wins: byClass[rk].wins })
    }
    return out
}

// Dock change signature: class, pin/running state, best window and every
// window title. A file manager navigating to another folder changes nothing
// else, and the context menu reads these rows.
function dockAppsSig(apps) {
    var sig = ""
    var out = apps || []
    for (var m = 0; m < out.length; m++) {
        sig += out[m].cls + "|" + out[m].pinned + "|" + out[m].running + "|" + out[m].bestAddr
        var wins = out[m].wins
        for (var n = 0; n < wins.length; n++)
            sig += "|" + wins[n].addr + "=" + wins[n].title
        sig += ";"
    }
    return sig
}
