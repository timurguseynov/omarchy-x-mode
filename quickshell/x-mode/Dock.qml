import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import "logic.js" as Logic

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
  // Events land here first. `clients` is what the column reads, and assigning
  // it resizes the layer. That commit waits on a frame callback; if it happens
  // inside the event handler the nest blocks writing the rest of the burst and
  // the callback never arrives, so the card stays one icon tall.
  property var clientBuf: []
  property var pinned: []
  property var apps: []
  property string appsSig: ""
  // Apps we just launched (via the dock) that have not appeared yet, so repeated
  // clicks do not spawn several instances.
  property var launching: ({})
  // Icons, display names, the "New Window" command and the single-instance
  // flag all come from one shared resolver (Panel.qml uses the same one).
  IconResolver { id: icons }
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
  // (see Style.qml), so it is the screen margin the snap zones also use. Not
  // readonly: the inset test overrides it, and x-mode.lua reads the result off
  // the layer rather than keeping its own copy of this sum.
  property int cardWidth: iconSize + pad * 2
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

  // Thin wrapper: the model itself (grouping, order, sig) is pure in
  // logic.js so it is unit tested without a compositor. Only the side
  // effects stay here: clearing "launching" and publishing apps/sig.
  function rebuildApps() {
    var out = Logic.buildDockApps(clients, pinned)
    for (var i = 0; i < out.length; i++) {
      // The app appeared: it is no longer "launching".
      if (out[i].running && root.launching[out[i].cls] !== undefined)
        delete root.launching[out[i].cls]
    }
    var sig = Logic.dockAppsSig(out)
    if (sig !== root.appsSig) {
      root.appsSig = sig
      root.apps = out
    }
  }

  function samePins(a, b) {
    return Logic.samePins(a, b)
  }

  function focusAddr(addr) {
    if (!addr)
      return
    // On the dock's own Hyprland socket, not a fresh hyprctl. Spawning one
    // loses the race to whatever else is already talking to the nest, and the
    // click then does nothing until that queue drains.
    // hl.dsp.focus, not hyprbars.raise: raise is a plain plugin call, and
    // hl.dispatch only accepts a dispatcher, so the raise string comes back
    // as an error after the call. focus is the dispatcher that also moves
    // to the window's workspace. The pack raises a floating window from
    // window.active, which this focus emits.
    Hyprland.dispatch("hl.dsp.focus({ window = 'address:" + addr + "' })")
  }

  function focusGroup(app) {
    // Already focused on the workspace we are looking at. Raising this same
    // window keeps the current tab: choosing another member of the group is
    // what switched tabs. A bare return dropped the click when the cached
    // workspace was stale, so a window that had actually moved never got raised.
    if (app.cls === root.activeClass && root.focusedClient) {
      var fws = root.focusedClient.workspace
      var fid = fws && fws.id
      if (fid !== undefined && String(fid) === String(root.viewedWorkspace)) {
        focusAddr(root.focusedClient.address)
        return
      }
    }
    var addr = app.bestAddr
    if (app.ws && root.viewedWorkspace >= 0 && app.ws[String(root.viewedWorkspace)]) {
      var here = app.ws[String(root.viewedWorkspace)]
      addr = here && typeof here === "object" ? here.addr : here
    }
    focusAddr(addr)
  }

  function appEntryFor(cls) { return icons.appEntryFor(cls) }
  function appDisplayName(cls) { return icons.appDisplayName(cls) }
  function isSingleInstance(cls) { return icons.isSingleInstance(cls) }

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
      Hyprland.dispatch("hl.dsp.window.close({ window = 'address:" + app.addrs[i] + "' })")
  }

  function openMenu(app, screenY) {
    // The overlay is a new layer. Creating it inside the click handler waits
    // on a frame callback before the handler returns, and the nest then cannot
    // deliver that frame. Open it on the next turn, after the click is done.
    menuOpenDefer.app = app
    menuOpenDefer.screenY = screenY
    menuOpenDefer.start()
  }

  Timer {
    id: menuOpenDefer
    interval: 0
    repeat: false
    property var app: null
    property real screenY: 0
    onTriggered: {
      root.menuApp = app
      if (typeof screenY === "number")
        root.menuY = screenY
      root.menuOpen = true
    }
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
    // The menu layer goes away on the next turn. Destroying it in this click
    // waits on a frame callback before the close or focus dispatch is written,
    // and the nest then never delivers that frame.
    menuCloseDefer.start()
  }

  Timer {
    id: menuCloseDefer
    interval: 0
    repeat: false
    onTriggered: root.closeMenu()
  }

  Process {
    id: clientsProc
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      onStreamFinished: root.absorbClientSnapshot(text)
    }
  }

  // The event socket is the client list. hyprctl on every event piled up
  // behind the tests' own queries when several nests ran, and the query that
  // finally returned was the list from before the event, which the dock then
  // kept. Events update the list immediately. hyprctl runs once at startup
  // and again every few seconds for fields the events do not carry (mapped,
  // hidden). A window an event touched while that query was in flight keeps
  // the event's version, so a late snapshot cannot put it back.
  // Addresses an event changed while a hyprctl snapshot was in flight.
  // The snapshot must not put those windows back to the older values, and
  // it must not drop a window the snapshot was taken too early to contain.
  property var touchedDuringQuery: ({})

  function normAddr(addr) {
    var s = String(addr || "").toLowerCase()
    if (s === "")
      return ""
    if (s.indexOf("0x") !== 0)
      s = "0x" + s
    return s
  }

  function splitEvent(data, n) {
    var rest = String(data || "")
    var out = []
    var i
    for (i = 0; i < n - 1; i++) {
      var c = rest.indexOf(",")
      if (c < 0) {
        out.push(rest)
        rest = ""
        break
      }
      out.push(rest.slice(0, c))
      rest = rest.slice(c + 1)
    }
    out.push(rest)
    while (out.length < n)
      out.push("")
    return out
  }

  function workspaceIdOf(name) {
    var values = (Hyprland.workspaces && Hyprland.workspaces.values) || []
    for (var i = 0; i < values.length; i++) {
      if (String(values[i].name) === String(name))
        return values[i].id
    }
    var n = parseInt(name, 10)
    return isNaN(n) ? -1 : n
  }

  function clientIndex(list, id) {
    for (var i = 0; i < list.length; i++) {
      if (normAddr(list[i].address) === id)
        return i
    }
    return -1
  }

  function scheduleClientPublish() {
    if (!clientPublish.running)
      clientPublish.start()
  }

  function applyClientEvent(name, data) {
    var list = root.clientBuf.slice()
    var changed = false
    if (name === "openwindow") {
      var o = splitEvent(data, 4)
      var id = normAddr(o[0])
      if (id === "")
        return false
      // A window that just opened is the focused one. activewindowv2 usually
      // follows and says so again; if it arrived first the window was not in
      // the list yet, so the open has to record the focus itself.
      for (var n = 0; n < list.length; n++) {
        var prev = list[n].focusHistoryID
        list[n].focusHistoryID = (typeof prev === "number" ? prev : 1) + 1
      }
      var entry = {
        address: id,
        class: o[2],
        title: o[3],
        mapped: true,
        hidden: false,
        focusHistoryID: 0,
        workspace: { id: workspaceIdOf(o[1]) }
      }
      var at = clientIndex(list, id)
      if (at >= 0)
        list[at] = entry
      else
        list.push(entry)
      var touched = root.touchedDuringQuery
      touched[id] = true
      root.touchedDuringQuery = touched
      changed = true
    } else if (name === "closewindow") {
      var cid = normAddr(data)
      var next = []
      for (var i = 0; i < list.length; i++) {
        if (normAddr(list[i].address) === cid)
          changed = true
        else
          next.push(list[i])
      }
      list = next
      var ctouched = root.touchedDuringQuery
      ctouched[cid] = true
      root.touchedDuringQuery = ctouched
    } else if (name === "movewindowv2" || name === "movewindow") {
      var m = splitEvent(data, name === "movewindowv2" ? 3 : 2)
      var mid = normAddr(m[0])
      var mi = clientIndex(list, mid)
      if (mi >= 0) {
        var wid = name === "movewindowv2" ? parseInt(m[1], 10) : NaN
        list[mi].workspace = { id: isNaN(wid) ? workspaceIdOf(m[m.length - 1]) : wid }
        var mtouched = root.touchedDuringQuery
        mtouched[mid] = true
        root.touchedDuringQuery = mtouched
        changed = true
      }
    } else if (name === "windowtitlev2") {
      var t = splitEvent(data, 2)
      var tid = normAddr(t[0])
      var ti = clientIndex(list, tid)
      if (ti >= 0) {
        list[ti].title = t[1]
        var ttouched = root.touchedDuringQuery
        ttouched[tid] = true
        root.touchedDuringQuery = ttouched
        changed = true
      }
    } else if (name === "activewindowv2") {
      var aid = normAddr(data)
      if (aid === "")
        return false
      for (var f = 0; f < list.length; f++) {
        var h = list[f].focusHistoryID
        list[f].focusHistoryID = (typeof h === "number" ? h : 1) + 1
      }
      var ai = clientIndex(list, aid)
      if (ai >= 0)
        list[ai].focusHistoryID = 0
      var atouched = root.touchedDuringQuery
      atouched[aid] = true
      root.touchedDuringQuery = atouched
      changed = true
    } else {
      return false
    }
    if (changed) {
      root.clientBuf = list
      root.scheduleClientPublish()
    }
    return changed
  }

  function absorbClientSnapshot(raw) {
    var snap = []
    try {
      var d = JSON.parse(raw)
      if (Array.isArray(d))
        snap = d
    } catch (e) {
      return
    }
    var bySnap = {}
    var s
    for (s = 0; s < snap.length; s++)
      bySnap[normAddr(snap[s].address)] = snap[s]
    var touched = root.touchedDuringQuery || {}
    var next = []
    var seen = {}
    var i
    for (i = 0; i < root.clientBuf.length; i++) {
      var row = root.clientBuf[i]
      var id = normAddr(row.address)
      seen[id] = true
      var fromSnap = bySnap[id]
      // A close during the query leaves the window touched and already gone.
      if (touched[id] && !row)
        continue
      if (fromSnap && !touched[id]) {
        row.mapped = fromSnap.mapped
        row.hidden = fromSnap.hidden
        // movewindow can be missed while the nest is busy. The snapshot is
        // the heal: a click then switches to the workspace the window is
        // actually on, instead of treating it as already focused here.
        if (fromSnap.workspace && typeof fromSnap.workspace.id === "number")
          row.workspace = { id: fromSnap.workspace.id }
        if (typeof fromSnap.focusHistoryID === "number")
          row.focusHistoryID = fromSnap.focusHistoryID
        if (!row.class)
          row.class = fromSnap.class
      }
      next.push(row)
    }
    for (s = 0; s < snap.length; s++) {
      var sid = normAddr(snap[s].address)
      // Closed while the query ran: the event removed it and the snapshot
      // still has the older copy.
      if (!seen[sid] && !touched[sid])
        next.push(snap[s])
    }
    root.touchedDuringQuery = ({})
    root.clientBuf = next
    root.scheduleClientPublish()
  }

  function noteClientEvent(event) {
    if (!event || !event.name)
      return
    root.applyClientEvent(String(event.name), String(event.data || ""))
  }

  // interval 0 fires once the events already read have been handled, so the
  // resize is one commit after the burst instead of one commit per event.
  Timer {
    id: clientPublish
    interval: 0
    repeat: false
    onTriggered: {
      root.clients = root.clientBuf
      root.rebuildApps()
    }
  }

  function refreshClients() {
    if (clientsProc.running)
      return
    root.touchedDuringQuery = ({})
    clientsProc.running = true
  }

  FileView {
    id: pinnedFile
    path: root.pinnedPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var next = []
      try {
        var d = JSON.parse(text())
        if (Array.isArray(d))
          next = d
      } catch (e) {}
      // Same list: do not assign. A new array resizes the card, and that
      // commit is what we are trying not to repeat on the re-read below.
      if (root.samePins(root.pinned, next))
        return
      root.pinned = next
      root.rebuildApps()
    }
    onLoadFailed: {
      if (root.pinned.length === 0)
        return
      root.pinned = []
      root.rebuildApps()
    }
  }

  // inotify does not see a pin file that is created after the dock has
  // already started, so the card stays on the running icons only. Reading
  // again once a second is the watch's own reload; an unchanged list returns
  // before the card is touched.
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: pinnedFile.reload()
  }

  // Slow reconcile for mapped/hidden. Events cover open, close, move,
  // title and focus, so this does not have to run on every event.
  Timer {
    interval: 3000
    running: true
    repeat: true
    onTriggered: root.refreshClients()
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      root.noteClientEvent(event)
    }
  }

  // Clear "launching" flags that never appeared (e.g. the launch failed) so the
  // app can be launched again.
  Timer {
    id: launchClearTimer
    interval: 5000
    repeat: false
    onTriggered: root.launching = ({})
  }

  Component.onCompleted: root.refreshClients()

  function applyXModeLine(raw) {
    var on = Logic.parseEnabled(raw)
    if (on !== null)
      root.xModeOn = on
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
      // configreloaded once per reload. scheduleRefresh reads the option
      // 200ms later, which is before x-mode has finished applying "No gaps"
      // when the reload is busy, and that early read is the one the margin
      // would keep. A few more reads cover a reload that is still applying.
      else if (event.name === "configreloaded") {
        Style.scheduleRefresh()
        gapRecheck.kick()
      }
    }
  }

  // The 200ms Style read can land before "No gaps" has been applied, and one
  // follow-up is not enough when the reload is busy. Keep reading for about
  // six seconds; the offset test waits longer than that for the margin to move.
  Timer {
    id: gapRecheck
    interval: 400
    repeat: true
    property int left: 0
    function kick() {
      // A busy reload still has the old gaps a couple of seconds in.
      left = 15
      restart()
    }
    onTriggered: {
      Style.scheduleRefresh()
      left -= 1
      if (left <= 0)
        stop()
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

                // Hide the source icon while the ghost is shown.
                AppIcon {
                  anchors.fill: parent
                  cls: String(item.modelData.cls)
                  source: icons.iconFor(item.modelData.cls)
                  iconVisible: !item.isDragSource
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

                  AppIcon {
                    anchors.fill: parent
                    cls: String(root.dragCls || "")
                    source: root.dragActive ? icons.iconFor(root.dragCls) : ""
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
