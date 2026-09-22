import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Shared app-icon resolution, the same algorithm the dock uses:
// window class -> desktop entry Icon= (or web-app URL host, or chromium
// extension manifest) -> on-disk icon index -> Qt themed lookup.
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
  // [ { host, icon } ] for Chromium web apps, longest host first.
  property var desktopHostIcons: []
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

  function rebuildDesktopIcons() {
    var map = {}
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
      if (icon === "")
        continue
      root.addDesktopIconKey(map, e.id, icon)
      root.addDesktopIconKey(map, e.startupClass, icon)
      var host = root.webappHostFromExec(e.execString)
      if (host !== "")
        hosts.push({ host: host, icon: icon })
    }
    hosts.sort(function(a, b) { return b.host.length - a.host.length })
    root.desktopIconMap = map
    root.desktopHostIcons = hosts
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
    }
  }

  Component.onCompleted: {
    iconScan.running = true
    extensionScan.running = true
    root.rebuildDesktopIcons()
  }
}