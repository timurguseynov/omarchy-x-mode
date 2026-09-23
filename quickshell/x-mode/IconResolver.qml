import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Shared app resolution for the dock and the panel: window class -> desktop
// entry -> icon, plus the bits the dock's context menu needs from the same
// entry (display name, the "New Window" action, single-instance).
//
// Kept as a plain component (not a singleton) so both Dock.qml and Panel.qml
// can instantiate it without a qmldir; each instance owns its own scan.
Item {
  id: root
  visible: false
  width: 0
  height: 0

  property var iconIndex: ({})
  property var pendingIconIndex: ({})
  // window class / app id -> icon name from the desktop entry's Icon=.
  property var desktopIconMap: ({})
  // window class / app id -> { id, name, cmd } for the same entries. `cmd` is
  // the "New Window" action's command when the entry declares one, else null.
  property var desktopAppMap: ({})
  // [ { host, icon, id, name, cmd } ] for Chromium web apps, longest host first.
  property var desktopHostIcons: []
  // Desktop-entry ids (and their StartupWMClass) that declare a single main
  // window, so launching one only focuses the running instance.
  property var singleInstanceApps: ({})
  property var pendingSingleInstance: ({})
  // chromium extension id (32 chars a..p) -> icon file path.
  property var extensionIcons: ({})
  property var pendingExtensionIcons: ({})

  function iconScanCommand() {
    return [
      'dirs="$HOME/.icons $HOME/.local/share/icons $HOME/.local/share/flatpak/exports/share/icons /var/lib/flatpak/exports/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      'for ext in svg png; do',
      '  for base in $dirs; do',
      '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.$ext" 2>/dev/null;',
      '  done;',
      '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
      'done'
    ].join(' ')
  }

  // One id/StartupWMClass per desktop entry that declares it opens a single
  // main window: launching such an app activates the existing instance instead
  // of creating a new window, so there is no tab to open.
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

  function cleanName(cls) {
    return String(cls || "").toLowerCase().trim()
      .replace(/^org\./, "").replace(/^com\./, "").replace(/^io\./, "")
      .replace(/^dev\./, "").replace(/^net\./, "").replace(/^me\./, "")
      .replace(/\.desktop$/, "")
  }

  // Last reverse-DNS segment: "dev.zed.Zed" -> "zed", "org.gnome.Nautilus" ->
  // "Nautilus". Used as the loosest icon-name candidate.
  function lastSegment(name) {
    var parts = String(name || "").split(".")
    return parts.length > 1 ? parts[parts.length - 1] : String(name || "")
  }

  // Resolve an icon *name* (desktop entry Icon= value) to a loadable URL, going
  // through the on-disk index first: Qt's themed lookup misses icons installed
  // after the shell started (its theme cache never rescans).
  function resolveIconName(name) {
    var n = String(name || "").trim()
    if (n === "")
      return ""
    if (n.charAt(0) === "/")
      return Util.fileUrl(n)
    var p = root.iconIndex[n]
    if (p)
      return Util.fileUrl(p)
    var themed = Quickshell.iconPath(n, true)
    if (themed && themed.length > 0)
      return themed
    return ""
  }

  function addDesktopIconKey(map, key, icon) {
    var k = String(key || "").toLowerCase().trim()
    if (k.slice(-8) === ".desktop")
      k = k.slice(0, -8)
    if (k === "")
      return
    if (map[k] === undefined)
      map[k] = icon
    var seg = k.split(".").pop()
    if (seg !== "" && seg !== k && map[seg] === undefined)
      map[seg] = icon
  }

  // Host of a web app's start URL, from the Exec of its desktop entry. Only
  // entries that actually launch a web app (omarchy-launch-webapp or --app=) are
  // considered, so a regular app with a URL argument cannot match.
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

  function hostIconFor(cls) {
    var c = String(cls || "").toLowerCase()
    if (c === "")
      return ""
    var hosts = root.desktopHostIcons
    // Longest host first: "app.zoom.us" must win over a shorter suffix.
    for (var i = 0; i < hosts.length; i++) {
      if (c.indexOf(hosts[i].host) !== -1)
        return root.resolveIconName(hosts[i].icon)
    }
    return ""
  }

  // Find the largest icon declared in every Chromium extension manifest under
  // the browser profiles and key it by the 32-char extension id ("a".."p").
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

  function extensionIconFor(cls) {
    var m = String(cls || "").toLowerCase().match(/^chrome-([a-p]{32})(-|$)/)
    if (!m)
      return ""
    var p = root.extensionIcons[m[1]]
    if (!p)
      return ""
    return Util.fileUrl(p)
  }

  // Command of the desktop entry's "New Window" action, when it has one (e.g.
  // Sublime Text's `subl --launch-or-new-window`). Launching the bare entry
  // would just focus the running instance for such apps.
  function newWindowActionCommand(e) {
    var acts = (e && e.actions) || []
    for (var j = 0; j < acts.length; j++) {
      var a = acts[j]
      if (!a)
        continue
      var id = String(a.id || "").toLowerCase().replace(/[\s_]+/g, "-")
      var name = String(a.name || "").toLowerCase()
      if (id.indexOf("new") === -1)
        continue
      if (id.indexOf("window") === -1 && name.indexOf("window") === -1)
        continue
      // Skip private / incognito variants — we want a plain new window.
      if (id.indexOf("private") !== -1 || id.indexOf("incognito") !== -1)
        continue
      if (name.indexOf("private") !== -1 || name.indexOf("incognito") !== -1)
        continue
      return a.command
    }
    return null
  }

  function rebuildDesktopIcons() {
    var map = {}
    var apps = {}
    var hosts = []
    var values = []
    try {
      values = DesktopEntries.applications.values || []
    } catch (e) {
      values = []
    }
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      var icon = String((e && e.icon) || "")
      var name = String((e && e.name) || "")
      var entry = { id: String((e && e.id) || ""), name: name, cmd: root.newWindowActionCommand(e) }
      if (entry.id !== "") {
        root.addDesktopIconKey(apps, entry.id, entry)
        root.addDesktopIconKey(apps, e.startupClass, entry)
      }
      if (icon === "")
        continue
      root.addDesktopIconKey(map, e.id, icon)
      root.addDesktopIconKey(map, e.startupClass, icon)
      var host = root.webappHostFromExec(e.execString)
      if (host !== "")
        hosts.push({ host: host, icon: icon, id: entry.id, name: name, cmd: entry.cmd })
    }
    hosts.sort(function(a, b) { return b.host.length - a.host.length })
    root.desktopIconMap = map
    root.desktopAppMap = apps
    root.desktopHostIcons = hosts
  }

  // Desktop entry matching a window class: the key map first, then the URL host
  // for Chromium web apps (whose class embeds it). Returns { id, name, cmd }.
  function appEntryFor(cls) {
    var c = String(cls || "").toLowerCase().trim()
    if (c.slice(-8) === ".desktop")
      c = c.slice(0, -8)
    if (c === "")
      return null
    var e = root.desktopAppMap[c]
    if (e === undefined) {
      var seg = c.split(".").pop()
      if (seg !== c)
        e = root.desktopAppMap[seg]
    }
    if (e !== undefined)
      return e
    var hs = root.desktopHostIcons
    for (var i = 0; i < hs.length; i++) {
      if (c.indexOf(hs[i].host) !== -1)
        return hs[i]
    }
    return null
  }

  // Human-readable app name, from the desktop entry keys used for icons; falls
  // back to the last dotted class segment.
  function appDisplayName(cls) {
    var e = root.appEntryFor(cls)
    if (e && e.name)
      return e.name
    var raw = String(cls || "").trim()
    var c = raw.toLowerCase()
    if (c.slice(-8) === ".desktop") {
      c = c.slice(0, -8)
      raw = raw.slice(0, -8)
    }
    return root.lastSegment(raw) || c
  }

  // True when the app's desktop entry declares it single-instance, so a launch
  // would only focus the running window (nothing new to open as a tab).
  function isSingleInstance(cls) {
    var c = String(cls || "").toLowerCase().trim()
    if (c.slice(-8) === ".desktop")
      c = c.slice(0, -8)
    if (c === "")
      return false
    if (root.singleInstanceApps[c])
      return true
    var seg = c.split(".").pop()
    return seg !== c && !!root.singleInstanceApps[seg]
  }

  function desktopIconFor(cls) {
    var c = String(cls || "").toLowerCase().trim()
    if (c.slice(-8) === ".desktop")
      c = c.slice(0, -8)
    if (c === "")
      return ""
    var name = root.desktopIconMap[c]
    if (name === undefined) {
      var seg = c.split(".").pop()
      if (seg !== c)
        name = root.desktopIconMap[seg]
    }
    if (name === undefined) {
      var h = root.hostIconFor(c)
      if (h !== "")
        return h
      return root.extensionIconFor(c)
    }
    return root.resolveIconName(name)
  }

  function iconFor(cls) {
    var raw = String(cls || "")
    var cleaned = root.cleanName(raw)
    // Direct candidates first (a class that already is the icon name), then the
    // desktop entry's Icon= value, then the loose last segment.
    var candidates = [raw, cleaned, root.lastSegment(cleaned)]
    for (var i = 0; i < candidates.length; i++) {
      var p = root.resolveIconName(candidates[i])
      if (p !== "")
        return p
    }
    var de = root.desktopIconFor(raw)
    if (de !== "")
      return de
    var fb = Quickshell.iconPath("application-x-executable", true)
    return fb && fb.length > 0 ? fb : ""
  }

  Process {
    id: iconScan
    command: ["bash", "-c", root.iconScanCommand()]
    stdout: SplitParser {
      onRead: function(line) {
        var path = String(line || "").trim()
        if (path === "")
          return
        var base = path.substring(path.lastIndexOf("/") + 1)
        var dot = base.lastIndexOf(".")
        var name = dot > 0 ? base.substring(0, dot) : base
        if (root.pendingIconIndex[name] === undefined)
          root.pendingIconIndex[name] = path
      }
    }
    onStarted: root.pendingIconIndex = ({})
    onExited: root.iconIndex = root.pendingIconIndex
  }

  Process {
    id: singleInstanceScan
    command: ["bash", "-c", root.singleInstanceScanCommand()]
    stdout: SplitParser {
      onRead: function(line) {
        var t = String(line || "").split("\t")
        var id = String(t[0] || "").toLowerCase().trim()
        if (id.slice(-8) === ".desktop")
          id = id.slice(0, -8)
        var wm = String(t.length > 1 ? t[1] : "").toLowerCase().trim()
        if (wm.slice(-8) === ".desktop")
          wm = wm.slice(0, -8)
        if (id !== "")
          root.pendingSingleInstance[id] = true
        if (wm !== "")
          root.pendingSingleInstance[wm] = true
      }
    }
    onStarted: root.pendingSingleInstance = ({})
    onExited: root.singleInstanceApps = root.pendingSingleInstance
  }

  Process {
    id: extensionScan
    command: ["bash", "-c", root.extensionScanCommand()]
    stdout: SplitParser {
      onRead: function(line) {
        var t = String(line || "").split("\t")
        if (t.length < 2)
          return
        var id = t[0].trim()
        var path = t.slice(1).join("\t").trim()
        if (id !== "" && path !== "" && root.pendingExtensionIcons[id] === undefined)
          root.pendingExtensionIcons[id] = path
      }
    }
    onStarted: root.pendingExtensionIcons = ({})
    onExited: root.extensionIcons = root.pendingExtensionIcons
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      root.rebuildDesktopIcons()
      // A new app installs an icon next to its .desktop entry; rescan the
      // on-disk icon index so it appears without a shell restart. Debounced
      // because a package install touches many entries at once.
      iconRescan.restart()
      if (!singleInstanceScan.running)
        singleInstanceScan.running = true
    }
  }

  Timer {
    id: iconRescan
    interval: 750
    repeat: false
    onTriggered: if (!iconScan.running) iconScan.running = true
  }

  // Catch icon-only changes (an app updating its icon) and newly installed
  // browser extensions, which do not touch a .desktop entry.
  Timer {
    interval: 300000
    running: true
    repeat: true
    onTriggered: {
      if (!iconScan.running)
        iconScan.running = true
      if (!extensionScan.running)
        extensionScan.running = true
      if (!singleInstanceScan.running)
        singleInstanceScan.running = true
    }
  }

  Component.onCompleted: {
    iconScan.running = true
    extensionScan.running = true
    singleInstanceScan.running = true
    root.rebuildDesktopIcons()
  }
}