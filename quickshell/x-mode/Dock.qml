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

  // Overlays (own files, same plugin).
  SnapPreview {}
  Switcher {}

  property var clients: []
  property var pinned: []
  property var apps: []
  property string appsSig: ""
  // Apps we just launched (via the dock) that have not appeared yet, so repeated
  // clicks do not spawn several instances.
  property var launching: ({})
  property var iconIndex: ({})
  property var pendingIconIndex: ({})
  property bool menuOpen: false
  property var menuApp: null
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
  readonly property var menuActionsModel: menuOpen ? menuActions() : []
  readonly property bool emptyDock: pinnedApps.length === 0 && runningApps.length === 0

  readonly property string pinnedPath: Quickshell.env("HOME") + "/.config/omarchy/x-mode-dock.json"
  readonly property int iconSize: 26
  readonly property int pad: 7
  readonly property int iconSpacing: 6
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
    for (var m = 0; m < out.length; m++)
      sig += out[m].cls + "|" + out[m].pinned + "|" + out[m].running + "|" + out[m].bestAddr + ";"
    if (sig !== root.appsSig) {
      root.appsSig = sig
      root.apps = out
    }
  }

  function iconScanCommand() {
    return [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
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
      .replace(/\.desktop$/, "")
  }

  function iconFor(cls) {
    var candidates = [String(cls || ""), cleanName(cls)]
    for (var i = 0; i < candidates.length; i++) {
      var c = candidates[i]
      if (c === "")
        continue
      var p = root.iconIndex[c]
      if (p)
        return Util.fileUrl(p)
      var themed = Quickshell.iconPath(c, true)
      if (themed && themed.length > 0)
        return themed
    }
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

  function activate(app) {
    if (app.running) {
      focusGroup(app)
      return
    }
    // Ignore repeated clicks while the app is still starting up.
    if (root.launching[app.cls])
      return
    root.launching[app.cls] = true
    launchClearTimer.restart()
    Quickshell.execDetached(["gtk-launch", app.cls])
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

  function openMenu(app) {
    menuApp = app
    menuOpen = true
  }

  function closeMenu() {
    menuOpen = false
    menuApp = null
  }

  function menuActions() {
    var a = []
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
        if (title.length > 28)
          title = title.slice(0, 27) + "…"
        var ws = win.ws ? "WS" + win.ws : ""
        a.push({
          id: "win:" + win.addr,
          label: title ? (ws ? title + "  " + ws : title) : (ws || "Window"),
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
    } else if (id === "pin" || id === "unpin")
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

  Component.onCompleted: {
    clientsProc.running = true
    iconScan.running = true
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
      if (event && event.name === "xmode")
        root.applyXModeLine(event.data)
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
          implicitWidth: root.iconSize + root.pad * 2 + 12
          implicitHeight: Math.max(col.implicitHeight, root.minIconsHeight) + root.pad * 2
          margins {
            top: Math.max(0, Math.round((modelData.height - implicitHeight) / 2))
          }
          color: "transparent"
          WlrLayershell.namespace: "x-mode-dock"
          WlrLayershell.layer: WlrLayer.Top
          WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
          exclusionMode: ExclusionMode.Ignore

          Rectangle {
            id: dockBg
            anchors.centerIn: parent
            width: root.iconSize + root.pad * 2
            height: Math.max(col.implicitHeight, root.minIconsHeight) + root.pad * 2
            radius: root.dockRadius
            color: Util.alpha(Color.background, 0.85)
            border.color: Util.alpha(Color.foreground, 0.15)
            border.width: 1

            Component {
              id: appIconDelegate

              Item {
                id: item
                required property var modelData
                required property int index
                property bool pinnedItem: !!item.modelData.pinned
                property bool isDragSource: item.pinnedItem && root.dragCls === String(item.modelData.cls)
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
                      root.openMenu(item.modelData)
                    else if (mouse.button === Qt.LeftButton)
                      root.activate(item.modelData)
                  }
                  onCanceled: {
                    root.clearDrag()
                    dragArmed = false
                  }
                  onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton && !dragArmed)
                      root.openMenu(item.modelData)
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

          MouseArea {
            anchors.fill: parent
            onClicked: root.closeMenu()
          }

          Rectangle {
            id: menuCard
            width: 240
            height: menuCol.implicitHeight + 12
            x: modelData.width - 6 - (root.iconSize + root.pad * 2) - width - (Style.gapsOut * 2)
            y: Math.max(8, Math.min(modelData.height - height - 8, modelData.height / 2 - height / 2))
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

                  Text {
                    visible: modelData.id !== "sep" && modelData.id !== "sep2"
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    text: modelData.label
                    color: modelData.enabled ? Color.foreground : Util.alpha(Color.foreground, 0.4)
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
