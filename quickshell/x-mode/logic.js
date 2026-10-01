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

// The panel's apps map: { "class": { chrome, alwaysTabbar, ctrlW, ctrlAsSuper
// } }. Accepts the parsed object (from settings.json) or a raw JSON string (the
// old apps.json). A legacy array of classes means chrome off.
function parseApps(raw) {
    var set = {}
    try {
        var d = typeof raw === "string" ? JSON.parse(raw) : raw
        if (Array.isArray(d)) {
            for (var i = 0; i < d.length; i++)
                set[String(d[i]).toLowerCase()] = { chrome: false, alwaysTabbar: false, ctrlW: false, ctrlAsSuper: false }
        } else if (d && typeof d === "object") {
            for (var k in d) {
                var e = d[k]
                if (e && typeof e === "object")
                    set[String(k).toLowerCase()] = { chrome: e.chrome !== false, alwaysTabbar: !!e.alwaysTabbar, ctrlW: !!e.ctrlW, ctrlAsSuper: !!e.ctrlAsSuper }
                else
                    set[String(k).toLowerCase()] = { chrome: false, alwaysTabbar: false, ctrlW: false, ctrlAsSuper: false }
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

// On-disk icon index scan: feeds IconResolver's name -> path map. Covers
// apps/ and devices/ (app icons) as well as categories/ (symbolic icons like
// the portal dialog's applications-system-symbolic), plus the top level of
// /usr/share/pixmaps. Pure string building, so it is unit tested here and
// IconResolver only runs it.
function iconScanCommand() {
    return [
        'dirs="$HOME/.icons $HOME/.local/share/icons $HOME/.local/share/flatpak/exports/share/icons /var/lib/flatpak/exports/share/icons";',
        'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
        'for ext in svg png; do',
        '  for base in $dirs; do',
        '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" -o -path "*/categories/*" \\) -name "*.$ext" 2>/dev/null;',
        '  done;',
        '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
        'done'
    ].join(' ')
}

// One id/StartupWMClass per desktop entry that declares it opens a single
// main window. Pure string building, like iconScanCommand.
function singleInstanceScanCommand() {
    return [
        'for d in "$HOME/.local/share/applications" /usr/local/share/applications /usr/share/applications /var/lib/flatpak/exports/share/applications "$HOME/.local/share/flatpak/exports/share/applications" /var/lib/snapd/desktop/applications; do',
        '  [[ -d $d ]] || continue;',
        '  for f in "$d"/*.desktop; do',
        '    [[ -f $f ]] || continue;',
        '    grep -qiE "^(SingleMainWindow|X-GNOME-SingleWindow|X-KDE-SingleMainWindow)=true" "$f" || continue;',
        '    id=$(basename "$f" .desktop);',
        '    wm=$(grep -i "^StartupWMClass=" "$f" | head -1 | cut -d= -f2-);',
        '    printf "%s\\t%s\\n" "$id" "$wm";',
        '  done;',
        'done'
    ].join(' ')
}

// Find the largest icon declared in every Chromium extension manifest under
// the browser profiles. Pure string building, like iconScanCommand.
function extensionScanCommand() {
    return [
        "for base in $(find \"$HOME/.config\" -maxdepth 4 -type d -name Extensions 2>/dev/null); do",
        "  for mf in $(find \"$base\" -mindepth 3 -maxdepth 3 -name manifest.json 2>/dev/null); do",
        "    id=$(basename \"$(dirname \"$(dirname \"$mf\")\")\")",
        "    [[ $id =~ ^[a-p]{32}$ ]] || continue",
        "    vdir=$(dirname \"$mf\")",
        "    icon=$(jq -r '.icons // {} | to_entries | max_by(.key | tonumber) | .value // empty' \"$mf\" 2>/dev/null)",
        "    [ -n \"$icon\" ] || continue",
        "    case $icon in /*) p=$icon ;; *) p=$vdir/$icon ;; esac",
        "    [ -f \"$p\" ] && printf '%s\\t%s\\n' \"$id\" \"$p\"",
        "  done",
        "done"
    ].join("\n")
}

// Pin-list toggle: a copy with cls removed or appended. The caller assigns
// it and persists it.
function togglePinInList(list, cls) {
    var out = (list || []).slice()
    var i = out.indexOf(cls)
    if (i >= 0)
        out.splice(i, 1)
    else
        out.push(cls)
    return out
}

// Pin reorder: a copy with the entry moved, or null when the move is invalid
// (out of range or a no-op). The caller assigns, persists and rebuilds.
function movePinInList(list, from, to) {
    var out = (list || []).slice()
    if (from < 0 || to < 0 || from >= out.length || to >= out.length || from === to)
        return null
    var item = out.splice(from, 1)[0]
    out.splice(to, 0, item)
    return out
}

// Drag target slot in the pinned column: center-based index with hysteresis
// so the slot does not flap on a boundary. fromIndex is the dragged slot,
// hoverIndex the current one; the hold only applies while they match.
function pinSlotIndex(y, fromIndex, hoverIndex, stride, iconSize, n) {
    if (stride <= 0 || n <= 0)
        return 0
    var idx = Math.round((y - iconSize / 2) / stride)
    if (idx < 0)
        idx = 0
    if (idx > n - 1)
        idx = n - 1
    if (fromIndex >= 0 && fromIndex === hoverIndex) {
        var center = idx * stride + iconSize / 2
        if (Math.abs(y - center) < stride * 0.2)
            return hoverIndex
    }
    return idx
}

// Dock context-menu rows for an app. menuApp is the snapshot taken at open
// time; the current entry for the same class is swapped in first, since the
// client list is re-read on windowtitle. displayName and singleInstance come
// from the desktop entry. Returns { app, actions } (app may be null, as the
// caller passes it).
function buildMenuActions(menuApp, apps, displayName, singleInstance) {
    var app = menuApp || null
    if (app) {
        var list = apps || []
        for (var k = 0; k < list.length; k++) {
            if (list[k].cls === app.cls) {
                app = list[k]
                break
            }
        }
    }
    var a = []
    if (app && !singleInstance) {
        a.push({ id: "new", label: "New " + displayName, enabled: true })
        if (app.wins && app.wins.length > 0)
            a.push({ id: "sep", label: "", enabled: false })
    }
    var wins = (app && app.wins) ? app.wins.slice() : []
    wins.sort(function(x, y) {
        var dx = Number(x.ws) - Number(y.ws)
        if (dx !== 0)
            return dx
        return (x.focus || 0) - (y.focus || 0)
    })
    if (wins.length > 0) {
        for (var i = 0; i < wins.length; i++) {
            var win = wins[i]
            var title = String(win.title || "").trim()
            a.push({
                id: "win:" + win.addr,
                label: title || "Window",
                wsLabel: win.ws ? String(win.ws) : "",
                enabled: true,
                addr: win.addr
            })
        }
        a.push({ id: "sep", label: "", enabled: false })
    }
    if (app && app.pinned)
        a.push({ id: "unpin", label: "Unpin", enabled: true })
    else
        a.push({ id: "pin", label: "Pin", enabled: true })
    a.push({ id: "close", label: "Quit", enabled: !!(app && app.addrs && app.addrs.length > 0) })
    return { app: app, actions: a }
}

// Settings-panel app list filter: class, display name or window title contain
// the query (case-insensitive). appName maps a class to its display name.
function filterPanelApps(running, query, appName) {
    var q = String(query || "").trim().toLowerCase()
    var out = []
    var list = running || []
    for (var i = 0; i < list.length; i++) {
        var a = list[i]
        if (q === "" || String(a.cls).toLowerCase().indexOf(q) >= 0
                || String(appName(a.cls)).toLowerCase().indexOf(q) >= 0
                || String(a.title || "").toLowerCase().indexOf(q) >= 0)
            out.push(a)
    }
    return out
}

// Open app detail: the running entry whose class matches (case-insensitive),
// or a blank row for a configured-but-not-running class. Null when closed.
function findPanelApp(running, openCls) {
    var key = String(openCls || "").toLowerCase()
    if (key === "")
        return null
    var list = running || []
    for (var i = 0; i < list.length; i++) {
        if (String(list[i].cls).toLowerCase() === key)
            return list[i]
    }
    return { cls: key, title: "" }
}

// Per-app chrome config with defaults (titlebar on, tabbar auto, flags off).
function panelCfgFor(appsCfg, cls) {
    var key = String(cls || "").toLowerCase()
    var e = (appsCfg || {})[key]
    if (!e)
        return { chrome: true, alwaysTabbar: false, ctrlW: false, ctrlAsSuper: false }
    return {
        chrome: e.chrome !== false,
        alwaysTabbar: !!e.alwaysTabbar,
        ctrlW: !!e.ctrlW,
        ctrlAsSuper: !!e.ctrlAsSuper
    }
}

// Per-app config update: a copy with the entry set, or dropped when every field
// is back at its default (chrome on, nothing else). Null for an empty class.
function mergePanelCfg(appsCfg, cls, chrome, alwaysTabbar, ctrlW, ctrlAsSuper) {
    var key = String(cls || "").toLowerCase()
    if (key === "")
        return null
    var next = {}
    var cfg = appsCfg || {}
    for (var k in cfg)
        next[k] = cfg[k]
    if (chrome && !alwaysTabbar && !ctrlW && !ctrlAsSuper)
        delete next[key]
    else
        next[key] = { chrome: chrome, alwaysTabbar: !!alwaysTabbar, ctrlW: !!ctrlW, ctrlAsSuper: !!ctrlAsSuper }
    return next
}

// One field changed, the rest read from the current entry. The panel's rows use
// this instead of carrying every field through a mergePanelCfg call.
function setPanelFlag(appsCfg, cls, flag, value) {
    var key = String(cls || "").toLowerCase()
    if (key === "")
        return null
    var cfg = panelCfgFor(appsCfg, key)
    cfg[flag] = !!value
    return mergePanelCfg(appsCfg, key, cfg.chrome, cfg.alwaysTabbar, cfg.ctrlW, cfg.ctrlAsSuper)
}

// Settings-panel running list: one row per app class with the best-focus
// window's title, plus configured-but-not-running classes, sorted by class.
// Pure: the caller assigns it to `running`.
function buildPanelRunning(clients, appsCfg) {
    var by = {}
    var list = clients || []
    for (var i = 0; i < list.length; i++) {
        var c = list[i]
        if (!c || !c.mapped)
            continue
        var cls = String(c.class || c.initialClass || "")
        if (cls === "")
            continue
        var key = cls.toLowerCase()
        var title = String(c.title || "")
        if (!by[key])
            by[key] = { cls: cls, title: title, focus: 999999 }
        var f = c.focusHistoryID
        if (typeof f === "number" && f < by[key].focus) {
            by[key].focus = f
            by[key].title = title
            by[key].cls = cls
        }
    }
    var cfg = appsCfg || {}
    for (var k in cfg) {
        if (!by[k])
            by[k] = { cls: k, title: "", focus: 999998 }
    }
    var out = []
    for (var k2 in by)
        out.push(by[k2])
    out.sort(function(a, b) { return String(a.cls).localeCompare(String(b.cls)) })
    return out
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
