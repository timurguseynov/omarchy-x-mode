import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons

// Vertical app dock on the right edge. Shows pinned + running apps (one icon
// per app class) and focuses the app's group on click.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // Overlays (own files, same plugin). The switcher reuses the dock's icon
  // resolution so its row shows real app icons (it has no index of its own).
  SnapPreview {}
  Switcher { dock: root }

  property var clients: []
  property var pinned: []
  property var apps: []
  property string appsSig: ""
  // Apps we just launched (via the dock) that have not appeared yet, so repeated
  // clicks do not spawn several instances.
  property var launching: ({})
  property var iconIndex: ({})
  property var pendingIconIndex: ({})
  // Maps a window class / app id to the icon name from its .desktop entry
  // (e.g. "dev.zed.Zed" -> "zed", "com.discordapp.Discord" -> its own icon).
  // Needed because the window class often only matches the desktop file id, not
  // the themed icon name.
  property var desktopIconMap: ({})
  // Launch metadata keyed the same way as the icon map (desktop-entry id and
  // startup class, plus the last dotted segment): { id, name, cmd }. `cmd` is a
  // "New Window" desktop action's command when the entry declares one, else null.
  property var desktopAppMap: ({})
  // Chromium web apps (omarchy-launch-webapp / --app=URL) report a class like
  // "chrome-<host>__...-Default", which matches neither the desktop file id nor
  // its Icon= name. This maps the URL host to the entry's icon so those windows
  // get their launcher icon.
  property var desktopHostIcons: []
  // Classes whose desktop entry declares a single-instance app (so launching
  // it would only focus the running window, not open a new tab). Used to hide
  // the "New …" menu item for those.
  property var singleInstanceApps: ({})
  property var pendingSingleInstance: ({})
  // Chromium extension windows (MetaMask, Bitwarden, ...) report a class like
  // "chrome-<extension-id>-Default". There is no desktop entry for those, so
  // map the extension id to the largest icon declared by the extension's
  // manifest in the browser profile.
  property var extensionIcons: ({})
  property var pendingExtensionIcons: ({})
  property bool menuOpen: false
  property var menuApp: null
  // Screen Y of the icon the menu was opened from, so the popup lines up with
  // the button instead of sitting in the middle of the dock.
  property real menuY: 0
  // Screen Y of the dock panel's top edge (its layer-shell top margin), needed
  // to turn an icon's window-local Y into a screen Y for the menu.
  property real dockPanelTop: 0
  property bool xModeOn: true
  // Pinned-icon drag reorder (Mac dock style). Track by class so Repeater
  // reshuffles do not flash the icon back to its old slot on drop.
  property string dragCls: ""
  property int dragFromIndex: -1
  property int dragHoverIndex: -1
  property real dragGhostY: 0
  property real dragHotY: 0
  readonly property bool dragActive: dragCls !== ""

  readonly property var pinnedApps: apps.filter(function(a) { return a.pinned })
  readonly property var runningApps: apps.filter(function(a) { return !a.pinned })
  readonly property bool menuPinned: menuApp ? !!menuApp.pinned : false
  // Depends on appsSig as well as menuOpen: menuApp is a snapshot taken when
  // the menu opened, so a window whose title changes afterwards (a file
  // manager navigating to another folder) would keep showing the old title
  // until the menu was closed. appsSig changes whenever rebuildApps() runs.
  readonly property var menuActionsModel: (menuOpen && appsSig) ? menuActions() : []
  readonly property bool emptyDock: pinnedApps.length === 0 && runningApps.length === 0

  readonly property string pinnedPath: Quickshell.env("HOME") + "/.config/omarchy/x-mode-dock.json"
  readonly property int iconSize: 26
  readonly property int pad: 7
  readonly property int iconSpacing: 6
  // Visible card. Style.gapsOut is already half of Hyprland's general:gaps_out
  // (see Style.qml), so it is the screen margin the snap zones also use.
  readonly property int cardWidth: iconSize + pad * 2
  readonly property int dockGap: Style.gapsOut || 0
  // Empty dock still paints a one-icon card so it does not collapse to a pill.
  readonly property int minIconsHeight: iconSize
  // Dock corner radius, following the window rounding (decoration:rounding via
  // Style.cornerRadius). A theme with square corners (0) keeps the dock square.
  readonly property int dockRadius: Math.round(Style.cornerRadius || 0)

  readonly property var focusedClient: {
    for (var i = 0; i < clients.length; i++) {
      if (clients[i].focusHistoryID === 0)
        return clients[i]
    }
    return null
  }
  readonly property string activeClass: focusedClient ? String(focusedClient.class || "") : ""
  readonly property int viewedWorkspace: {
    var fw = Hyprland.focusedWorkspace
    if (fw && typeof fw.id === "number")
      return fw.id
    var ws = focusedClient && focusedClient.workspace
    if (ws && typeof ws.id === "number")
      return ws.id
    return -1
  }

  function rebuildApps() {
    var byClass = {}
    for (var i = 0; i < clients.length; i++) {
      var c = clients[i]
      if (!c.mapped || c.hidden)
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
    for (var p = 0; p < pinned.length; p++) {
      var pc = pinned[p]
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
      // The app appeared: it is no longer "launching".
      if (root.launching[k] !== undefined)
        delete root.launching[k]
    }
    rest.sort()
    for (var j = 0; j < rest.length; j++) {
      var rk = rest[j]
      out.push({ cls: rk, pinned: false, running: true, bestAddr: byClass[rk].bestAddr, addrs: byClass[rk].addrs, ws: byClass[rk].ws, wins: byClass[rk].wins })
    }
    var sig = ""
    for (var m = 0; m < out.length; m++) {
      sig += out[m].cls + "|" + out[m].pinned + "|" + out[m].running + "|" + out[m].bestAddr
      // Titles too: a file manager navigating to another folder changes
      // nothing else about the app, and the context menu reads these rows.
      var wins = out[m].wins
      for (var n = 0; n < wins.length; n++)
        sig += "|" + wins[n].addr + "=" + wins[n].title
      sig += ";"
    }
    if (sig !== root.appsSig) {
      root.appsSig = sig
      root.apps = out
    }
  }

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

  function focusAddr(addr) {
    if (!addr)
      return
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.alter_zorder({ mode = \"top\", window = 'address:" + addr + "' })"])
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = 'address:" + addr + "' })"])
  }

  function focusGroup(app) {
    // Already focused on the workspace we are looking at: do not retarget a
    // group member (that switches tabs).
    if (app.cls === root.activeClass && root.focusedClient) {
      var fws = root.focusedClient.workspace
      var fid = fws && fws.id
      if (fid !== undefined && String(fid) === String(root.viewedWorkspace))
        return
    }
    var addr = app.bestAddr
    if (app.ws && root.viewedWorkspace >= 0 && app.ws[String(root.viewedWorkspace)]) {
      var here = app.ws[String(root.viewedWorkspace)]
      addr = here && typeof here === "object" ? here.addr : here
    }
    focusAddr(addr)
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

  // Human-readable app name for the "New …" menu item, from the desktop entry
  // keys used for icons; falls back to the last dotted class segment.
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

  // Desktop-entry file name for a window class. gtk-launch only resolves the
  // literal file name, so the ".desktop" suffix must always be appended, even
  // when the class itself already ends in it: the class `org.telegram.desktop`
  // belongs to the file `org.telegram.desktop.desktop`. Passing the bare class
  // (or treating a trailing ".desktop" as the file name) makes gtk-launch look
  // for a file that does not exist and fail with "no such application".
  function desktopIdFor(cls) {
    return String(cls || "") + ".desktop"
  }

  function activate(app) {
    // A left-click on the dock (now reachable while the menu is open, since
    // the overlay no longer covers it) dismisses any open menu.
    root.closeMenu()
    if (app.running) {
      focusGroup(app)
      return
    }
    root.launchApp(app)
  }

  // Launch a new instance of an app. Shared by the dock icon and the "New …"
  // context-menu item; x-mode.lua groups same-app windows into one tab group.
  function launchApp(app) {
    if (!app)
      return
    // Ignore repeated launches while the app is still starting up.
    if (root.launching[app.cls])
      return
    root.launching[app.cls] = true
    launchClearTimer.restart()
    // Same launch path as the Omarchy launcher: run inside a systemd scope via
    // uwsm-app, so the app does not become a child of the shell (it would die on
    // a shell restart) and does not inherit wayland-wm@.service.
    var e = root.appEntryFor(app.cls)
    var cmd = (e && e.cmd) ? e.cmd : null
    if (cmd && cmd.length > 0) {
      // Entry has a dedicated "New Window" action (e.g. Sublime Text).
      var parts = ["uwsm-app", "--"]
      for (var i = 0; i < cmd.length; i++)
        parts.push(String(cmd[i]))
      Quickshell.execDetached(parts)
    } else if (e && e.id) {
      // gtk-launch the matched entry: correct for web apps (runs
      // omarchy-launch-webapp) and for classes that differ from the file name.
      // Quickshell's entry id is the file basename without ".desktop"
      // (org.telegram.desktop for org.telegram.desktop.desktop), so the suffix
      // still has to be appended or gtk-launch reports "no such application".
      Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", root.desktopIdFor(e.id)])
    } else {
      Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", root.desktopIdFor(app.cls)])
    }
  }

  function togglePin(cls) {
    var list = pinned.slice()
    var i = list.indexOf(cls)
    if (i >= 0)
      list.splice(i, 1)
    else
      list.push(cls)
    pinned = list
    pinnedFile.setText(JSON.stringify(list, null, 2) + "\n")
  }

  function movePinTo(from, to) {
    if (from < 0 || to < 0 || from >= pinned.length || to >= pinned.length || from === to)
      return false
    var list = pinned.slice()
    var item = list.splice(from, 1)[0]
    list.splice(to, 0, item)
    pinned = list
    pinnedFile.setText(JSON.stringify(list, null, 2) + "\n")
    // Rebuild immediately so the dock order matches before we clear the ghost.
    rebuildApps()
    return true
  }

  function clearDrag() {
    dragCls = ""
    dragFromIndex = -1
    dragHoverIndex = -1
    dragGhostY = 0
    dragHotY = 0
  }

  function pinSlotAt(y, fromIndex) {
    var stride = iconSize + iconSpacing
    var n = pinned.length
    if (stride <= 0 || n <= 0)
      return 0
    // Center-based target with a little hysteresis so the slot does not flap
    // when the cursor sits on a boundary (that was the jitter).
    var idx = Math.round((y - iconSize / 2) / stride)
    if (idx < 0)
      idx = 0
    if (idx > n - 1)
      idx = n - 1
    if (fromIndex >= 0 && fromIndex === dragHoverIndex) {
      var center = idx * stride + iconSize / 2
      if (Math.abs(y - center) < stride * 0.2)
        return dragHoverIndex
    }
    return idx
  }

  function closeApp(app) {
    if (!app || !app.addrs)
      return
    for (var i = 0; i < app.addrs.length; i++)
      Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.close({ window = 'address:" + app.addrs[i] + "' })"])
  }

  function openMenu(app, screenY) {
    menuApp = app
    if (typeof screenY === "number")
      menuY = screenY
    menuOpen = true
  }

  function closeMenu() {
    menuOpen = false
    menuApp = null
  }

  function menuActions() {
    var a = []
    // menuApp is the app object captured at open time. The client list is
    // re-read on windowtitle, so swap in the current entry for the same class
    // before building the rows — otherwise the titles stay frozen.
    if (menuApp) {
      for (var k = 0; k < apps.length; k++) {
        if (apps[k].cls === menuApp.cls) {
          menuApp = apps[k]
          break
        }
      }
    }
    if (menuApp && !root.isSingleInstance(menuApp.cls)) {
      a.push({ id: "new", label: "New " + root.appDisplayName(menuApp.cls), enabled: true })
      if (menuApp.wins && menuApp.wins.length > 0)
        a.push({ id: "sep", label: "", enabled: false })
    }
    var wins = (menuApp && menuApp.wins) ? menuApp.wins.slice() : []
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
    if (menuPinned)
      a.push({ id: "unpin", label: "Unpin", enabled: true })
    else
      a.push({ id: "pin", label: "Pin", enabled: true })
    a.push({ id: "close", label: "Quit", enabled: menuApp && menuApp.addrs && menuApp.addrs.length > 0 })
    return a
  }

  function runMenuAction(id) {
    var app = menuApp
    if (typeof id === "string" && id.indexOf("win:") === 0) {
      focusAddr(id.slice(4))
    } else if (typeof id === "string" && id.indexOf("ws:") === 0) {
      var wid = id.slice(3)
      var entry = app && app.ws ? app.ws[wid] : null
      var addr = entry && typeof entry === "object" ? entry.addr : entry
      focusAddr(addr)
    } else if (id === "new")
      launchApp(app)
    else if (id === "pin" || id === "unpin")
      togglePin(app.cls)
    else if (id === "close")
      closeApp(app)
    closeMenu()
  }

  Process {
    id: clientsProc
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          if (Array.isArray(d)) {
            root.clients = d
            root.rebuildApps()
          }
        } catch (e) {}
      }
    }
  }

  FileView {
    id: pinnedFile
    path: root.pinnedPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var d = JSON.parse(text())
        root.pinned = Array.isArray(d) ? d : []
      } catch (e) {
        root.pinned = []
      }
      root.rebuildApps()
    }
    onLoadFailed: {
      root.pinned = []
      root.rebuildApps()
    }
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

  // Refresh the client list on Hyprland events instead of polling every 500ms:
  // a burst of events (e.g. a drag) triggers one query 120ms after it settles,
  // plus a slow safety poll for changes that do not emit an event. Idle costs
  // nothing (no `hyprctl` process is spawned while nothing changes).
  Timer {
    id: clientsRefresh
    interval: 120
    repeat: false
    onTriggered: if (!clientsProc.running) clientsProc.running = true
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      clientsRefresh.restart()
    }
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    onTriggered: if (!clientsProc.running) clientsProc.running = true
  }

  // Clear "launching" flags that never appeared (e.g. the launch failed) so the
  // app can be launched again.
  Timer {
    id: launchClearTimer
    interval: 5000
    repeat: false
    onTriggered: root.launching = ({})
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
    clientsProc.running = true
    iconScan.running = true
    extensionScan.running = true
    singleInstanceScan.running = true
    root.rebuildDesktopIcons()
  }

  function applyXModeLine(raw) {
    var s = String(raw || "").trim().toLowerCase()
    if (s === "off" || s === "0" || s === "false")
      root.xModeOn = false
    else if (s === "on" || s === "1" || s === "true" || s === "")
      root.xModeOn = true
  }

  FileView {
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-x-mode.state"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyXModeLine(text())
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event)
        return
      if (event.name === "xmode")
        root.applyXModeLine(event.data)
      // Style.gapsOut (the dock's screen margin) is only re-read on shell
      // startup and on a theme switch, so editing general:gaps_out left the
      // dock at the old distance until the shell restarted. Hyprland emits
      // configreloaded once per reload; scheduleRefresh debounces and runs
      // hyprctl getoption a single time, so this costs nothing while idle.
      else if (event.name === "configreloaded")
        Style.scheduleRefresh()
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      Item {
        required property var modelData

        // The dock overlays windows; it does not reserve screen space, so the
        // top bar keeps its full width. Snap zones are inset by the dock width
        // in the Hyprland config (x-mode.lua) instead.

        // The visible dock. The layer surface is sized exactly to the dock and
        // vertically centered, so pointer input lines up with the icons (no
        // mask needed).
        PanelWindow {
          id: panel
          screen: modelData
          visible: root.xModeOn
          anchors {
            top: true
            right: true
          }
          implicitWidth: root.cardWidth
          implicitHeight: Math.max(col.implicitHeight, root.minIconsHeight) + root.pad * 2
          margins {
            top: Math.max(0, Math.round((modelData.height - implicitHeight) / 2))
            right: root.dockGap
          }
          color: "transparent"
          WlrLayershell.namespace: "x-mode-dock"
          WlrLayershell.layer: WlrLayer.Top
          WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
          exclusionMode: ExclusionMode.Ignore

          Rectangle {
            id: dockBg
            // The layer is exactly the card; its right margin is the screen gap.
            anchors.fill: parent
            radius: root.dockRadius
            color: Util.alpha(Color.background, 0.85)
            border.color: Util.alpha(Color.foreground, 0.15)
            border.width: 1

            // `panel` is only in scope here (a direct child), not in the nested
            // icon delegate Component, so publish its top edge for menuScreenY.
            Binding {
              target: root
              property: "dockPanelTop"
              value: panel.margins.top
            }

            Component {
              id: appIconDelegate

              Item {
                id: item
                required property var modelData
                required property int index
                property bool pinnedItem: !!item.modelData.pinned
                property bool isDragSource: item.pinnedItem && root.dragCls === String(item.modelData.cls)
                // Screen Y of this icon, for aligning the context menu.
                function menuScreenY() {
                  return root.dockPanelTop + item.mapToItem(null, 0, 0).y
                }
                width: root.iconSize
                height: root.iconSize
                // Neighbors slide aside while a pinned icon is dragged.
                // No Behavior: an in-flight NumberAnimation freezes its value at
                // the drop, so the reordered icon could settle on a stale offset.
                transform: Translate {
                  y: {
                    if (!item.pinnedItem || !root.dragActive || item.isDragSource)
                      return 0
                    var from = root.dragFromIndex
                    var to = root.dragHoverIndex
                    if (from < 0 || to < 0 || from === to)
                      return 0
                    var stride = root.iconSize + root.iconSpacing
                    if (from < to && item.index > from && item.index <= to)
                      return -stride
                    if (from > to && item.index >= to && item.index < from)
                      return stride
                    return 0
                  }
                }

                Text {
                  anchors.centerIn: parent
                  // Hide the source icon while the ghost is shown.
                  visible: !item.isDragSource && iconImg.status !== Image.Ready
                  text: String(item.modelData.cls).charAt(0).toUpperCase()
                  color: Color.foreground
                  font.pixelSize: Math.round(root.iconSize * 0.6)
                }

                Image {
                  id: iconImg
                  anchors.fill: parent
                  source: root.iconFor(item.modelData.cls)
                  sourceSize.width: root.iconSize
                  sourceSize.height: root.iconSize
                  fillMode: Image.PreserveAspectFit
                  asynchronous: false
                  visible: !item.isDragSource && status === Image.Ready
                }

                Rectangle {
                  visible: !item.isDragSource && item.modelData.running
                  width: 5
                  height: 5
                  radius: 2.5
                  color: Color.accent
                  anchors.right: parent.right
                  anchors.rightMargin: -4
                  anchors.verticalCenter: parent.verticalCenter
                }

                MouseArea {
                  id: iconMouse
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  preventStealing: item.pinnedItem
                  property real pressLocalY: 0
                  property bool dragArmed: false

                  onPressed: function(mouse) {
                    if (mouse.button !== Qt.LeftButton || !item.pinnedItem)
                      return
                    pressLocalY = mouse.y
                    dragArmed = false
                  }
                  onPositionChanged: function(mouse) {
                    if (!(mouse.buttons & Qt.LeftButton) || !item.pinnedItem)
                      return
                    var dy = mouse.y - pressLocalY
                    if (!dragArmed && Math.abs(dy) < 4)
                      return
                    // Pointer Y in the pinned column (col-local).
                    var colY = item.y + mouse.y
                    if (!dragArmed) {
                      dragArmed = true
                      root.dragCls = String(item.modelData.cls)
                      root.dragFromIndex = item.index
                      root.dragHoverIndex = item.index
                      root.dragHotY = pressLocalY
                      root.dragGhostY = colY - root.dragHotY
                      root.closeMenu()
                    } else {
                      root.dragGhostY = colY - root.dragHotY
                      root.dragHoverIndex = root.pinSlotAt(colY, root.dragFromIndex)
                    }
                  }
                  onReleased: function(mouse) {
                    if (dragArmed && root.dragActive) {
                      var from = root.dragFromIndex
                      var to = root.dragHoverIndex
                      dragArmed = false
                      // Clear the drag state FIRST (hide ghost, reveal source,
                      // zero neighbour Translates), THEN reorder.
                      // movePinTo rebuilds `apps`, so the Repeater destroys and
                      // recreates delegates synchronously -- including the very
                      // delegate running this handler. Doing clearDrag after the
                      // reorder let the rebuild swallow it, leaving dragCls set:
                      // the ghost stayed at the release point and the recreated
                      // source icon stayed hidden (looked like the icon stuck
                      // where it was dropped instead of snapping to its slot).
                      root.clearDrag()
                      root.movePinTo(from, to)
                      return
                    }
                    dragArmed = false
                    if (mouse.button === Qt.RightButton)
                      root.openMenu(item.modelData, item.menuScreenY())
                    else if (mouse.button === Qt.LeftButton)
                      root.activate(item.modelData)
                  }
                  onCanceled: {
                    root.clearDrag()
                    dragArmed = false
                  }
                  onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton && !dragArmed)
                      root.openMenu(item.modelData, item.menuScreenY())
                  }
                }
              }
            }

            Column {
              id: col
              anchors.centerIn: parent
              spacing: root.iconSpacing

              // Keep a one-icon footprint when nothing is pinned/running yet.
              Item {
                visible: root.emptyDock
                width: root.iconSize
                height: root.minIconsHeight
              }

              Item {
                id: pinnedBox
                width: root.iconSize
                height: pinnedCol.implicitHeight
                visible: root.pinnedApps.length > 0 || root.dragActive

                Column {
                  id: pinnedCol
                  anchors.top: parent.top
                  spacing: root.iconSpacing

                  Repeater {
                    model: root.pinnedApps
                    delegate: appIconDelegate
                  }
                }

                // Floating ghost follows the cursor; source icon is hidden.
                Item {
                  id: dragGhost
                  visible: root.dragActive
                  width: root.iconSize
                  height: root.iconSize
                  x: 0
                  y: root.dragGhostY
                  z: 100
                  opacity: 0.95

                  Image {
                    id: ghostImg
                    anchors.fill: parent
                    source: root.dragActive ? root.iconFor(root.dragCls) : ""
                    sourceSize.width: root.iconSize
                    sourceSize.height: root.iconSize
                    fillMode: Image.PreserveAspectFit
                    asynchronous: false
                    visible: status === Image.Ready
                  }

                  Text {
                    anchors.centerIn: parent
                    visible: ghostImg.status !== Image.Ready
                    text: String(root.dragCls || "").charAt(0).toUpperCase()
                    color: Color.foreground
                    font.pixelSize: Math.round(root.iconSize * 0.6)
                  }
                }
              }

              Item {
                visible: root.pinnedApps.length > 0 && root.runningApps.length > 0
                width: root.iconSize
                height: 1

                Rectangle {
                  width: 18
                  height: 1
                  anchors.centerIn: parent
                  color: Util.alpha(Color.foreground, 0.25)
                }
              }

              Repeater {
                model: root.runningApps
                delegate: appIconDelegate
              }
            }
          }
        }

        // Right-click context menu. Only instantiated while open, so the
        // full-screen overlay never captures input when closed.
        Loader {
          active: root.menuOpen

          sourceComponent: Component {
            PanelWindow {
              id: menuPanel
              screen: modelData
              anchors {
            top: true
            bottom: true
            left: true
            right: true
          }
          color: "transparent"
          WlrLayershell.namespace: "x-mode-dock-menu"
          WlrLayershell.layer: WlrLayer.Overlay
          WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
          exclusionMode: ExclusionMode.Ignore
          // Take pointer input everywhere except the dock strip, so a
          // right-click on another icon reaches the dock and swaps the menu in
          // one click (instead of the overlay swallowing it to close first).
          mask: Region {
            width: modelData.width
            height: modelData.height

            Region {
              intersection: Intersection.Subtract
              x: modelData.width - root.cardWidth - root.dockGap
              y: 0
              width: root.cardWidth + root.dockGap
              height: modelData.height
            }
          }

          MouseArea {
            anchors.fill: parent
            onClicked: root.closeMenu()
          }

          Rectangle {
            id: menuCard
            width: 240
            height: menuCol.implicitHeight + 12
            x: modelData.width - root.dockGap - root.cardWidth - width - (Style.gapsOut * 2)
            // Align the popup with the icon it was opened from (the card's
            // pad puts the first row at the icon's top).
            y: Math.max(8, Math.min(modelData.height - height - 8, root.menuY - root.pad))
            radius: root.dockRadius
            color: Util.alpha(Color.background, 0.97)
            border.color: Util.alpha(Color.foreground, 0.2)
            border.width: 1

            Column {
              id: menuCol
              anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 6
              }
              spacing: 2

              Repeater {
                model: root.menuActionsModel

                delegate: Rectangle {
                  id: menuRow
                  required property var modelData
                  width: menuCol.width
                  height: (modelData.id === "sep" || modelData.id === "sep2") ? 7 : 26
                  color: (modelData.id !== "sep" && modelData.id !== "sep2" && rowMouse.containsMouse && modelData.enabled)
                    ? Util.alpha(Color.foreground, 0.12) : "transparent"

                  Rectangle {
                    visible: modelData.id === "sep" || modelData.id === "sep2"
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 1
                    color: Util.alpha(Color.foreground, 0.2)
                  }

                  // Title on the left, elided so it always fits; workspace
                  // number right-aligned with the same 8px margin.
                  Text {
                    id: menuRowLabel
                    visible: modelData.id !== "sep" && modelData.id !== "sep2"
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.right: menuRowWs.visible ? menuRowWs.left : parent.right
                    anchors.rightMargin: 8
                    text: modelData.label
                    elide: Text.ElideRight
                    color: modelData.enabled ? Color.foreground : Util.alpha(Color.foreground, 0.4)
                    font.pixelSize: 12
                  }

                  Text {
                    id: menuRowWs
                    visible: menuRowLabel.visible && !!modelData.wsLabel
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    text: modelData.wsLabel || ""
                    color: Util.alpha(Color.foreground, 0.55)
                    font.pixelSize: 12
                  }

                  MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: modelData.enabled && modelData.id !== "sep" && modelData.id !== "sep2"
                    onClicked: root.runMenuAction(modelData.id)
                  }
                }
              }
            }
          }
        }
          }
        }
      }
    }
  }
}
