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

// The shell command that puts `text` in a file a watcher reads. It writes a
// sibling temp file and renames it over the target: an in-place `printf > file`
// truncates the target first, and a watcher that reacts to that event reads a
// half-written file. `followUp` is chained after the rename, so a command that
// has to read the file back (`hyprctl reload`) sees the whole thing.
function stateWriteCommand(path, text, followUp) {
    var p = String(path || "")
    var slash = p.lastIndexOf("/")
    var dir = slash < 0 ? "." : (slash === 0 ? "/" : p.slice(0, slash))
    var tmp = p + ".tmp"
    var cmd = "mkdir -p " + shellQuote(dir) +
        " && printf '%s\\n' " + shellQuote(text) +
        " > " + shellQuote(tmp) +
        " && mv -f " + shellQuote(tmp) + " " + shellQuote(p)
    var tail = String(followUp || "")
    return tail === "" ? cmd : cmd + " && " + tail
}

// A watched state file read back into the shell: the parsed value, or null when
// the read is not an answer. The writers truncate before they write -- the
// panel's own settings write, the pack's occupied.json, the plugin's
// omarchy-x-mode.state -- so a watcher can read a half-written file, and
// JSON.parse then throws. The old code read that as "every flag off" / "no
// occupied keys": the settings rows flashed their defaults and the keys card
// shrank for a moment on every toggle. A torn read now keeps what the component
// is showing until the writer's next event brings the real content; a real `[]`
// or `{}` still parses and is applied.
function readJsonAnswer(text) {
    try {
        return JSON.parse(String(text === undefined || text === null ? "" : text))
    } catch (e) {
        return null
    }
}

// The desktop on/off line as an answer: null for a torn read or an unknown word,
// so the caller leaves the switch alone. parseEnabled answers true for an empty
// string, which is right for a missing file and wrong for a tear in the middle
// of a write, where it would flip the whole desktop on for a frame.
function readEnabledLine(raw) {
    if (String(raw === undefined || raw === null ? "" : raw).trim() === "")
        return null
    return parseEnabled(raw)
}

// Occupied Super keys stolen for this app, as an array of supermap ids
// ("Q", "TAB", "SHIFT+TAB"). Empty when the field is missing.
function copyOccupiedKeys(keys) {
    var out = []
    if (!keys || !keys.length)
        return out
    for (var i = 0; i < keys.length; i++) {
        var k = String(keys[i] || "")
        if (k !== "")
            out.push(k)
    }
    return out
}

function emptyAppCfg() {
    return {
        chrome: false,
        alwaysTabbar: false,
        ctrlAsSuper: undefined,
        ctrlCShift: undefined,
        ctrlClick: undefined,
        digitTabs: undefined,
        ctrlTabSwitch: undefined,
        ctrlAsSuperKeys: [],
        ctrlAsSuperKeysOff: []
    }
}

// Cmd+W was a replacement of its own -- the ctrlW flag -- before it became a
// steal like Cmd+Q and Cmd+F, and a file the older panel wrote still says ctrlW.
// Folding it onto the key it always meant is what keeps the setting after this
// panel writes the file back: on is the steal list, off is the Always off list.
function foldLegacyCtrlW(e, keys, keysOff) {
    var w = triFlag(e.ctrlW)
    if (w === true) {
        if (keys.indexOf("W") < 0)
            keys.push("W")
    } else if (w === false) {
        if (keysOff.indexOf("W") < 0)
            keysOff.push("W")
    }
}

// The same fold for the desktop-wide map, whose Cmd+W was `keys.ctrlW`: the
// panel writes it as a steal of W now, and the flag does not go back into the
// file (the pack reads the steal list).
function migrateGlobalKeys(keys) {
    var k = keys && typeof keys === "object" ? keys : ({})
    var next = {}
    for (var name in k) {
        if (name !== "ctrlW" && k[name])
            next[name] = k[name]
    }
    var steal = copyOccupiedKeys(k.steal)
    if (k.ctrlW === true && steal.indexOf("W") < 0)
        steal.push("W")
    if (steal.length)
        next.steal = steal
    return next
}

// The panel's apps map: { "class": { chrome, alwaysTabbar, ctrlAsSuper,
// ctrlCShift, ctrlClick, digitTabs, ctrlAsSuperKeys } }. Accepts the parsed object
// (from settings.json) or a raw JSON string (the old apps.json). A legacy array of
// classes means chrome off.
function parseApps(raw) {
    var set = {}
    try {
        var d = typeof raw === "string" ? JSON.parse(raw) : raw
        if (Array.isArray(d)) {
            for (var i = 0; i < d.length; i++)
                set[String(d[i]).toLowerCase()] = emptyAppCfg()
        } else if (d && typeof d === "object") {
            for (var k in d) {
                var e = d[k]
                if (e && typeof e === "object") {
                    var keys = copyOccupiedKeys(e.ctrlAsSuperKeys)
                    var keysOff = copyOccupiedKeys(e.ctrlAsSuperKeysOff)
                    foldLegacyCtrlW(e, keys, keysOff)
                    set[String(k).toLowerCase()] = {
                        chrome: e.chrome !== false,
                        alwaysTabbar: !!e.alwaysTabbar,
                        // Three states each: true is Always on, false is Always off,
                        // and absent follows the desktop. The panel writes only the
                        // pinned ones, so a file that predates this reads as the
                        // desktop's answer where it says nothing.
                        ctrlAsSuper: triFlag(e.ctrlAsSuper),
                        ctrlCShift: triFlag(e.ctrlCShift),
                        ctrlClick: triFlag(e.ctrlClick),
                        digitTabs: triFlag(e.digitTabs),
                        ctrlTabSwitch: triFlag(e.ctrlTabSwitch),
                        ctrlAsSuperKeys: keys,
                        ctrlAsSuperKeysOff: keysOff
                    }
                } else
                    set[String(k).toLowerCase()] = emptyAppCfg()
            }
        }
    } catch (err) {}
    return set
}

// true, false, or undefined for "no setting of its own".
function triFlag(v) {
    if (v === true)
        return true
    if (v === false)
        return false
    return undefined
}

// The three-state a row carries: "inherit", "on" or "off" from the panel's rows,
// or true/false from a plain switch -- or from a signal whose parameter was
// mistyped as a bool, since QML coerces "on" to true on the way through one. One
// normaliser, because a state that misses every comparison is not a no-op: it
// *clears* the pin, which is how a row that should pin a flag turned it off
// instead (the switch blinked, the file was rewritten without the flag, and the
// panel read it back as off).
function triState(v) {
    if (v === true || v === "on")
        return "on"
    if (v === false || v === "off")
        return "off"
    return "inherit"
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
        return { chrome: true, alwaysTabbar: false, ctrlAsSuper: undefined, ctrlCShift: undefined, ctrlClick: undefined, digitTabs: undefined, ctrlTabSwitch: undefined, ctrlAsSuperKeys: [], ctrlAsSuperKeysOff: [] }
    var keys = copyOccupiedKeys(e.ctrlAsSuperKeys)
    var keysOff = copyOccupiedKeys(e.ctrlAsSuperKeysOff)
    foldLegacyCtrlW(e, keys, keysOff)
    return {
        chrome: e.chrome !== false,
        alwaysTabbar: !!e.alwaysTabbar,
        ctrlAsSuper: triFlag(e.ctrlAsSuper),
        ctrlCShift: triFlag(e.ctrlCShift),
        ctrlClick: triFlag(e.ctrlClick),
        digitTabs: triFlag(e.digitTabs),
        ctrlTabSwitch: triFlag(e.ctrlTabSwitch),
        ctrlAsSuperKeys: keys,
        ctrlAsSuperKeysOff: keysOff
    }
}

// Per-app config update: a copy with the entry set, or dropped when every field is
// back at its default (chrome on, nothing else). Null for an empty class. Takes the
// config object, so an unset flag stays unset -- writing every flag out as true or
// false is what would turn "follows the desktop" into a pin.
function mergePanelCfg(appsCfg, cls, cfg) {
    var key = String(cls || "").toLowerCase()
    if (key === "")
        return null
    var next = {}
    var base = appsCfg || {}
    for (var k in base)
        next[k] = base[k]
    var keys = copyOccupiedKeys(cfg.ctrlAsSuperKeys)
    var keysOff = copyOccupiedKeys(cfg.ctrlAsSuperKeysOff)
    var pinned = false
    for (var i = 0; i < KEY_FLAG_NAMES.length; i++) {
        if (cfg[KEY_FLAG_NAMES[i]] !== undefined)
            pinned = true
    }
    if (cfg.chrome !== false && !cfg.alwaysTabbar && !pinned && keys.length === 0 && keysOff.length === 0) {
        delete next[key]
        return next
    }
    var row = { chrome: cfg.chrome !== false, alwaysTabbar: !!cfg.alwaysTabbar }
    for (var j = 0; j < KEY_FLAG_NAMES.length; j++) {
        var name = KEY_FLAG_NAMES[j]
        if (cfg[name] !== undefined)
            row[name] = cfg[name] === true
    }
    if (keys.length)
        row.ctrlAsSuperKeys = keys
    if (keysOff.length)
        row.ctrlAsSuperKeysOff = keysOff
    next[key] = row
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
    return mergePanelCfg(appsCfg, key, cfg)
}

// One keyboard flag set to a state: "inherit" clears the app's own answer (it goes
// back to following the desktop), "on" and "off" pin it. Null for a bad name.
function setKeyFlag(appsCfg, cls, flag, state) {
    var key = String(cls || "").toLowerCase()
    if (key === "" || KEY_FLAG_NAMES.indexOf(String(flag)) < 0)
        return null
    var cfg = panelCfgFor(appsCfg, key)
    var s = triState(state)
    cfg[flag] = s === "on" ? true : s === "off" ? false : undefined
    return mergePanelCfg(appsCfg, key, cfg)
}

// Occupied-key rows in the panel. Same ids/labels means the Repeater can keep
// its delegates (and the flickable its scroll) when the file is rewritten.
// Panel label for an occupied Super key: "⌘+Q as Ctrl+Q". The description
// under it is the desktop action that toggle replaces, not this string.
function stealToggleLabel(label) {
    var s = String(label || "")
    if (s.indexOf("⌘+") === 0)
        return s + " as Ctrl+" + s.substring(2)
    return s
}

function sameOccupiedList(a, b) {
    a = a || []
    b = b || []
    if (a.length !== b.length)
        return false
    for (var i = 0; i < a.length; i++) {
        var x = a[i] || {}
        var y = b[i] || {}
        if (String(x.id || "") !== String(y.id || "") ||
            String(x.key || "") !== String(y.key || "") ||
            !!x.shift !== !!y.shift ||
            String(x.label || "") !== String(y.label || "") ||
            String(x.description || "") !== String(y.description || ""))
            return false
    }
    return true
}

function hasOccupiedKey(cfg, id) {
    var keys = (cfg && cfg.ctrlAsSuperKeys) || []
    for (var i = 0; i < keys.length; i++) {
        if (keys[i] === id)
            return true
    }
    return false
}

function hasOccupiedKeyOff(cfg, id) {
    var keys = (cfg && cfg.ctrlAsSuperKeysOff) || []
    for (var i = 0; i < keys.length; i++) {
        if (keys[i] === id)
            return true
    }
    return false
}

// One occupied key for this app in one of its three states: inherit (both lists
// say nothing), on (the steal list), off (the Always off list -- which wins in the
// engine too, and the panel never writes both). The id is the supermap spelling
// ("Q", "SHIFT+TAB"); an empty class or id returns null.
function setOccupiedKey(appsCfg, cls, id, state) {
    id = String(id || "")
    if (id === "")
        return null
    var cfg = panelCfgFor(appsCfg, cls)
    var next = {}
    for (var k in cfg)
        next[k] = cfg[k]
    next.ctrlAsSuperKeys = withoutId(cfg.ctrlAsSuperKeys, id)
    next.ctrlAsSuperKeysOff = withoutId(cfg.ctrlAsSuperKeysOff, id)
    var s = triState(state)
    if (s === "on")
        next.ctrlAsSuperKeys.push(id)
    if (s === "off")
        next.ctrlAsSuperKeysOff.push(id)
    return mergePanelCfg(appsCfg, cls, next)
}

function withoutId(list, id) {
    var out = []
    var keys = list || []
    for (var i = 0; i < keys.length; i++) {
        if (keys[i] !== id)
            out.push(keys[i])
    }
    return out
}

// --- keyboard replacements: one screen, two scopes ---------------------------
//
// Every keyboard replacement can be forced on for every app from the main panel
// (options.keys), and the same rows then serve an app's card in three states:
// "inherit" follows the desktop, "on" and "off" pin this app against it. That is
// what lets a desktop-wide setting keep one app that disagrees -- Ctrl+1..6 handed
// to an editor while the desktop keeps them for the pack's tabs.

var KEY_FLAG_NAMES = ["ctrlAsSuper", "digitTabs", "ctrlTabSwitch", "ctrlClick", "ctrlCShift"]

// The row for one flag in an app's card: the state, whether the switch reads as on
// (the effective answer, so an inherited on looks on), and where that answer comes
// from.
function keyFlagState(cfg, forced, flag) {
    var own = cfg ? cfg[flag] : undefined
    var global = !!(forced && forced[flag])
    var pinnedOn = own === true
    var pinnedOff = own === false
    return {
        state: pinnedOn ? "on" : pinnedOff ? "off" : "inherit",
        checked: pinnedOn || (!pinnedOff && global),
        global: global,
        pinned: pinnedOn || pinnedOff
    }
}

// The click order: inherit, Always on, Always off, back to inherit. One function,
// so a row and its test cannot disagree about it.
function nextKeyFlagState(state) {
    if (state === "inherit")
        return "on"
    if (state === "on")
        return "off"
    return "inherit"
}

// What the row says under its switch.
function keyFlagDescription(state, global) {
    if (state === "on")
        return "Always on"
    if (state === "off")
        return "Always off"
    return global ? "Follows the desktop: on" : "Follows the desktop: off"
}

// What one row of an app's card says. A click puts the state's own words under
// the switch for a moment ("Always on"), and then the row goes back to what the
// replacement is for -- "Close window", "Links, multi-select" -- because that is
// what a card is read for. The tint on the row's left edge carries the state the
// whole time, so the meaning does not have to give way to the click's answer.
// `meaning` is the row's own description, empty when it has none.
function appRowDescription(state, global, notice, meaning) {
    if (notice)
        return keyFlagDescription(state, global)
    return String(meaning === undefined || meaning === null ? "" : meaning)
}

// One occupied key the same way: the app's Always off list, then its steal list,
// then the desktop's.
function keyStealState(cfg, forced, id) {
    var off = hasOccupiedKeyOff(cfg, id)
    var on = hasOccupiedKey(cfg, id)
    var global = false
    var list = (forced && forced.steal) || []
    for (var i = 0; i < list.length; i++) {
        if (String(list[i]) === String(id))
            global = true
    }
    return {
        state: off ? "off" : on ? "on" : "inherit",
        checked: off ? false : (on || global),
        global: global,
        pinned: off || on
    }
}

// The theme's own green and red for the two pinned states: Omarchy's QML palette
// has foreground, background, accent, urgent and muted and no green, so the colours
// come out of the theme file the shell reads. A name that is missing stays missing,
// and the caller falls back to accent and urgent.
function parseThemeAccents(toml) {
    var out = {}
    var text = String(toml || "")
    var wanted = ["green", "red"]
    for (var i = 0; i < wanted.length; i++) {
        var m = text.match(new RegExp("^\\s*" + wanted[i] + "\\s*=\\s*[\"'](#[0-9a-fA-F]{3,8})[\"']", "m"))
        if (m)
            out[wanted[i]] = m[1]
    }
    return out
}

// The global scope as a config object for the one screen that shows it. The flags
// are the desktop's own on/off answers (there is nothing to inherit from there), and
// the steal list is the ids it takes.
function globalScopeCfg(keys) {
    var k = keys || {}
    var cfg = { chrome: true, alwaysTabbar: false, ctrlAsSuperKeys: copyOccupiedKeys(k.steal), ctrlAsSuperKeysOff: [] }
    for (var i = 0; i < KEY_FLAG_NAMES.length; i++)
        cfg[KEY_FLAG_NAMES[i]] = !!k[KEY_FLAG_NAMES[i]]
    return cfg
}

// Whether the desktop steals one key for every app.
function hasGlobalSteal(keys, id) {
    var list = (keys && keys.steal) || []
    for (var i = 0; i < list.length; i++) {
        if (String(list[i]) === String(id))
            return true
    }
    return false
}

// The map with one flag written: false removes it, so the file holds only what is
// actually forced on. Null for an unknown flag name.
function setGlobalFlag(keys, flag, on) {
    if (KEY_FLAG_NAMES.indexOf(String(flag)) < 0)
        return null
    var k = keys || {}
    var next = {}
    for (var i = 0; i < KEY_FLAG_NAMES.length; i++) {
        var name = KEY_FLAG_NAMES[i]
        if (name !== flag && k[name])
            next[name] = true
    }
    if (on)
        next[flag] = true
    var steal = copyOccupiedKeys(k.steal)
    if (steal.length)
        next.steal = steal
    return next
}

// One occupied key forced on for every app.
function setGlobalSteal(keys, id, on) {
    id = String(id || "")
    if (id === "")
        return keys
    var k = keys || {}
    var next = {}
    for (var i = 0; i < KEY_FLAG_NAMES.length; i++) {
        if (k[KEY_FLAG_NAMES[i]])
            next[KEY_FLAG_NAMES[i]] = true
    }
    var list = copyOccupiedKeys(k.steal)
    var steal = []
    var seen = false
    for (var j = 0; j < list.length; j++) {
        if (String(list[j]) === id) {
            seen = true
            if (on)
                steal.push(list[j])
        } else {
            steal.push(list[j])
        }
    }
    if (on && !seen)
        steal.push(id)
    if (steal.length)
        next.steal = steal
    return next
}

// The "for every app" entry row: what is in force, or that nothing is.
function globalKeysSummary(keys) {
    var k = keys || {}
    var n = 0
    for (var i = 0; i < KEY_FLAG_NAMES.length; i++) {
        if (k[KEY_FLAG_NAMES[i]])
            n++
    }
    var keysN = copyOccupiedKeys(k.steal).length
    if (n === 0 && keysN === 0)
        return "Nothing set for every app"
    var parts = []
    if (n)
        parts.push(n === 1 ? "1 replacement" : n + " replacements")
    if (keysN)
        parts.push(keysN === 1 ? "1 key" : keysN + " keys")
    return parts.join(", ") + " for every app"
}

// The card's entry row: how many replacements are in force for this app, and how
// many of them are pinned rather than following the desktop.
function appKeysSummary(cfg, forced) {
    var c = cfg || {}
    var f = forced || {}
    var on = 0
    var pinned = 0
    for (var i = 0; i < KEY_FLAG_NAMES.length; i++) {
        var st = keyFlagState(c, f, KEY_FLAG_NAMES[i])
        if (st.checked)
            on++
        if (st.pinned)
            pinned++
    }
    var keysN = (c.ctrlAsSuperKeys || []).length
    var keysOffN = (c.ctrlAsSuperKeysOff || []).length
    var parts = []
    if (on)
        parts.push(on === 1 ? "1 replacement" : on + " replacements")
    if (keysN)
        parts.push(keysN === 1 ? "1 key" : keysN + " keys")
    if (pinned || keysOffN)
        parts.push("pinned here")
    if (parts.length === 0)
        return "Off: Super keys reach the app as they are"
    if (on === 0 && keysN === 0 && (pinned || keysOffN))
        return "Off here: pinned against the desktop"
    return parts.join(", ")
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
