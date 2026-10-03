import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "logic.js" as Logic

// X Mode settings, laid out like the Omarchy Bluetooth panel: a hero header
// with the on/off switch, settings rows, then the app list. Opening an app
// shows its chrome flags, Super-as-Ctrl, and a toggle per occupied Super key.
Panel {
  id: root
  moduleName: "x-mode.toggle"
  ipcTarget: "x-mode.toggle"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property bool xModeOn: true
  readonly property var barIdentity: hostWidget || root

  readonly property string settingsPath: (Quickshell.env("HOME") || "") + "/.config/hypr/x-mode.json"
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // Height of every element except the scrolling app list, so the list can be
  // sized to the space actually left in the capped card. Excludes `listFlick`
  // itself -- referencing its height here would be circular.
  readonly property real listFixedHeight: {
    var items = [hero, sepTop, scrollRow, keysEntryRow, gapsRow, sepMid, backRow, sectionHeader, searchField]
    var h = 0
    var n = 0
    for (var i = 0; i < items.length; i++) {
      var it = items[i]
      if (!it || it.visible === false)
        continue
      h += it.implicitHeight
      n++
    }
    if (n > 1)
      h += (n - 1) * column.spacing
    return h
  }

  // The rows that stay above the keys screen: the back row and its header.
  readonly property real keysFixedHeight: {
    var items = [backRow, sectionHeader]
    var h = 0
    var n = 0
    for (var i = 0; i < items.length; i++) {
      var it = items[i]
      if (!it || it.visible === false)
        continue
      h += it.implicitHeight
      n++
    }
    if (n > 1)
      h += (n - 1) * column.spacing
    return h
  }

  property bool nativeScroll: false
  property bool ctrlTabSwitch: false
  property bool noGaps: false
  property bool workspacesOnFkeys: false
  // The card is capped so it never spills past the popup. The app list gets a
  // taller cap than the per-app card: with the fixed content above it, the 480
  // left room for barely two rows before the list had to scroll.
  // Same cap on the app list and the per-app page: the occupied-key rows need
  // the same room, and they scroll inside the card instead of shrinking it.
  readonly property int cardCap: Style.space(720)
  property var appsCfg: ({})
  // The keyboard replacements forced on for every app (settings options.keys).
  // A flag here is read as set for any class, and the card shows the row locked.
  property var globalKeys: ({})
  // Ctrl+Cmd+Q is the Mac lock key, and Omarchy's Calculator sits there. On unless
  // the file says otherwise; off hands the key back to the Calculator.
  property bool lockKey: true
  // The keys screen is a page on top of whatever is showing: back returns to it,
  // and its scope is decided by where it was opened from (no class = every app).
  property bool keysOpen: false
  readonly property string view: root.keysOpen ? "keys" : (root.openCls === "" ? "main" : "app")
  property var running: []
  property string query: ""
  property string openCls: ""
  // Occupied Super keys the pack can steal, written by x-mode.lua from the live
  // bind table. Super+W and the workspace digits stay out of this list.
  property var occupiedKeys: []
  readonly property string occupiedPath: (Quickshell.env("HOME") || "") + "/.local/state/omarchy-x-mode/occupied.json"

  // Pure list work lives in logic.js (unit tested); the resolver callback is
  // the only Quickshell-adjacent bit that stays here.
  readonly property var filtered: Logic.filterPanelApps(running, query, function(cls) { return root.appName(cls) })

  readonly property var openApp: Logic.findPanelApp(running, openCls)

  // Same resolution the dock uses (desktop entry Icon=, web-app URL host,
  // chromium extension manifest, on-disk icon index, then Qt themed lookup).
  function appIcon(cls) {
    return iconResolver.iconFor(cls)
  }

  // The desktop entry's real name ("Files") rather than the window class
  // ("org.gnome.Nautilus"). Falls back to the last dotted segment.
  function appName(cls) {
    return iconResolver.appDisplayName(cls)
  }

  function cfgFor(cls) {
    return Logic.panelCfgFor(appsCfg, cls)
  }

  function setFlag(flag, value) {
    // One per-app flag changed; the entry is dropped again when every flag is
    // back at its default.
    var next = Logic.setPanelFlag(appsCfg, openCls, flag, value)
    if (!next)
      return
    appsCfg = next
    writeSettings("hyprctl eval 'if x_mode and x_mode.refresh_apps_off then x_mode.refresh_apps_off() end' >/dev/null")
  }

  function setOccupiedKey(id, value) {
    var next = Logic.setOccupiedKey(appsCfg, openCls, id, value)
    if (!next)
      return
    appsCfg = next
    writeSettings("hyprctl eval 'if x_mode and x_mode.refresh_apps_off then x_mode.refresh_apps_off() end' >/dev/null")
  }

  // The same two, for the global map: a reload because the handlers read the
  // option block at load, and one key changing hands has to re-plan the binds.
  function setGlobalFlag(flag, value) {
    var next = Logic.setGlobalFlag(globalKeys, flag, value)
    if (!next)
      return
    globalKeys = next
    writeSettings("hyprctl reload >/dev/null")
  }

  function setGlobalSteal(id, value) {
    globalKeys = Logic.setGlobalSteal(globalKeys, id, value)
    writeSettings("hyprctl reload >/dev/null")
  }

  // The lock key is not a replacement for one class, so it is an option of its
  // own; the reload both re-reads it and recreates the Calculator bind it dropped.
  function setLockKey(value) {
    root.lockKey = !!value
    writeSettings("hyprctl reload >/dev/null")
  }

  // The panel's whole state in one file, so the options and the app list can
  // never drift apart. `followUp` is the hyprctl call the change needs.
  function writeSettings(followUp) {
    var apps = {}
    for (var k in appsCfg) {
      var e = appsCfg[k]
      if (e && (e.chrome === false || e.alwaysTabbar || e.ctrlW || e.ctrlAsSuper || e.ctrlCShift || e.ctrlClick || e.digitTabs || (e.ctrlAsSuperKeys && e.ctrlAsSuperKeys.length))) {
        var row = { chrome: e.chrome !== false, alwaysTabbar: !!e.alwaysTabbar, ctrlW: !!e.ctrlW, ctrlAsSuper: !!e.ctrlAsSuper, ctrlCShift: !!e.ctrlCShift, ctrlClick: !!e.ctrlClick }
        if (e.digitTabs)
          row.digitTabs = true
        if (e.ctrlAsSuperKeys && e.ctrlAsSuperKeys.length)
          row.ctrlAsSuperKeys = e.ctrlAsSuperKeys
        apps[k] = row
      }
    }
    var json = JSON.stringify({
      options: { nativeScroll: root.nativeScroll, ctrlTabSwitch: root.ctrlTabSwitch, noGaps: root.noGaps, workspacesOnFkeys: root.workspacesOnFkeys, lockScreenKey: root.lockKey, keys: root.globalKeys },
      apps: apps
    })
    Quickshell.execDetached([
      "sh", "-c",
      "mkdir -p \"$HOME/.config/hypr\" && printf '%s\\n' " + Logic.shellQuote(json) + " > \"$HOME/.config/hypr/x-mode.json\" && " + followUp
    ])
  }

  function setOptions(nativeScroll, ctrlTabSwitch, noGaps, workspacesOnFkeys) {
    root.nativeScroll = !!nativeScroll
    root.ctrlTabSwitch = !!ctrlTabSwitch
    root.noGaps = !!noGaps
    root.workspacesOnFkeys = !!workspacesOnFkeys
    // The reload re-runs the config, which reapplies every option from
    // settings.json, and emits configreloaded. The dock only re-reads its screen
    // margin on that event, so without the reload it stays at the old gap. It is
    // the only step: the natural-scroll eval that used to run first could fail,
    // and with `&&` that skipped the reload and left the option unapplied.
    writeSettings("hyprctl reload >/dev/null")
  }

  function rebuildRunning(clients) {
    running = Logic.buildPanelRunning(clients, appsCfg)
  }

  function refreshClients() {
    clientsProc.running = true
  }

  onOpenedChanged: {
    if (opened) {
      openCls = ""
      keysOpen = false
      // A filter left from the last time the panel was open would hide apps
      // the next time it is, so every open starts from the whole list.
      query = ""
      refreshClients()
    }
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var d = JSON.parse(text())
        var o = (d && d.options) || {}
        root.nativeScroll = !!o.nativeScroll
        root.ctrlTabSwitch = !!o.ctrlTabSwitch
        root.noGaps = !!o.noGaps
        root.workspacesOnFkeys = !!o.workspacesOnFkeys
        root.globalKeys = (o.keys && typeof o.keys === "object") ? o.keys : ({})
        root.lockKey = !(o.lockScreenKey === false)
        root.appsCfg = Logic.parseApps((d && d.apps) || {})
      } catch (e) {
        root.nativeScroll = false
        root.ctrlTabSwitch = false
        root.noGaps = false
        root.workspacesOnFkeys = false
        root.globalKeys = ({})
        root.lockKey = true
        root.appsCfg = {}
      }
      root.refreshClients()
    }
    onLoadFailed: {
      root.nativeScroll = false
      root.ctrlTabSwitch = false
      root.noGaps = false
      root.workspacesOnFkeys = false
      root.globalKeys = ({})
      root.lockKey = true
      root.appsCfg = {}
    }
  }

  FileView {
    id: occupiedFile
    path: root.occupiedPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var d = JSON.parse(text())
        var list = Array.isArray(d) ? d : []
        if (!Logic.sameOccupiedList(root.occupiedKeys, list))
          root.occupiedKeys = list
      } catch (e) {
        if (root.occupiedKeys.length)
          root.occupiedKeys = []
      }
    }
    onLoadFailed: if (root.occupiedKeys.length) root.occupiedKeys = []
  }

  Process {
    id: clientsProc
    command: ["hyprctl", "-j", "clients"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          if (Array.isArray(d))
            root.rebuildRunning(d)
        } catch (e) {}
      }
    }
  }

  IconResolver { id: iconResolver }

  // Two-line settings row with a trailing switch, the same shape as the
  // Bluetooth device rows. The whole row toggles; the switch is not interactive.
  component SwitchRow: CursorSurface {
    id: srow
    property string label: ""
    property string description: ""
    property bool checked: false
    property bool rowEnabled: true
    signal toggled()

    implicitHeight: srowContent.implicitHeight + Style.spacing.rowPaddingX
    foreground: root.contentForeground
    hasCursor: srowMouse.containsMouse && srow.rowEnabled
    opacity: srow.rowEnabled ? 1 : 0.5

    MouseArea {
      id: srowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: srow.rowEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (srow.rowEnabled) srow.toggled()
    }

    Item {
      id: srowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(srowLabels.implicitHeight, srowSwitch.implicitHeight)

      Column {
        id: srowLabels
        spacing: Style.space(1)
        anchors.left: parent.left
        anchors.right: srowSwitch.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          text: srow.label
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          visible: srow.description !== ""
          text: srow.description
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }

      ToggleSwitch {
        id: srowSwitch
        checked: srow.checked
        interactive: false
        foreground: root.contentForeground
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  // A row that opens another screen: a label, a line saying what is behind it, and
  // a chevron. Used for the keyboard replacements from the main panel and from an
  // app's card, which is where the scope is decided.
  component LinkRow: CursorSurface {
    id: lrow
    property string label: ""
    property string description: ""
    signal clicked()

    implicitHeight: lrowContent.implicitHeight + Style.spacing.rowPaddingX
    foreground: root.contentForeground
    hasCursor: lrowMouse.containsMouse

    MouseArea {
      id: lrowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: lrow.clicked()
    }

    Item {
      id: lrowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(lrowText.implicitHeight, lrowChevron.implicitHeight)

      Column {
        id: lrowText
        spacing: Style.space(1)
        anchors.left: parent.left
        anchors.right: lrowChevron.left
        anchors.rightMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter

        Text {
          text: lrow.label
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          visible: lrow.description !== ""
          text: lrow.description
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }

      Text {
        id: lrowChevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "›"
        color: Qt.darker(root.contentForeground, 1.5)
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
      }
    }
  }

  // The keyboard replacements themselves, in one element used by both scopes: with
  // `cls` empty it is the "for every app" screen, with a class it is that app's.
  // The two desktop options that used to sit on the main panel (the digits as
  // tabs, the workspaces on the F keys) open each screen; they are global, so
  // only the "for every app" one shows them.
  // A row the main panel forces is shown checked and locked instead of hidden --
  // it is still in force, and hiding it would make the app look like it decides.
  // The force lives in one place, the rows are identical in both screens.
  component KeyRows: Column {
    id: krows
    property string cls: ""
    property var cfg: ({})
    property var forced: ({})
    property bool workspacesOnFkeys: false
    property var occupiedKeys: []
    signal flagToggled(string flag, bool value)
    signal keyToggled(string id, bool value)

    width: parent ? parent.width : 0
    spacing: Style.space(4)

    // A card cannot disagree with the main panel, so its forced rows are locked.
    readonly property bool isApp: krows.cls !== ""

    // Desktop options that used to sit on the main panel, global only: they
    // write the settings file through the panel's setOptions (the pack re-reads
    // it on the reload), so an app's screen hides them -- one app cannot move
    // the desktop's workspaces or take the digits for the whole desktop.
    Column {
      width: krows.width
      spacing: krows.spacing
      visible: !krows.isApp

      SwitchRow {
        id: krowsTabKeysRow
        width: parent.width
        label: "Ctrl+1..0 switches tabs"
        description: "Jump to a titlebar tab; off, the shortcut goes to the app"
        checked: root.ctrlTabSwitch
        rowEnabled: root.xModeOn
        onToggled: root.setOptions(root.nativeScroll, !root.ctrlTabSwitch, root.noGaps, root.workspacesOnFkeys)
      }

      SwitchRow {
        id: krowsWorkspaceKeysRow
        width: parent.width
        label: "Workspaces on F1..F10"
        description: "Super+F1..F10 switch workspaces; the freed digits follow Key replacements"
        checked: root.workspacesOnFkeys
        rowEnabled: root.xModeOn
        onToggled: root.setOptions(root.nativeScroll, root.ctrlTabSwitch, root.noGaps, !root.workspacesOnFkeys)
      }

      SwitchRow {
        id: krowsLockKeyRow
        width: parent.width
        label: "⌃⌘Q locks the screen"
        description: "Takes Omarchy's Calculator key; off gives it back"
        checked: root.lockKey
        rowEnabled: root.xModeOn
        onToggled: root.setLockKey(!root.lockKey)
      }

      PanelSeparator {
        width: krows.width
        foreground: root.contentForeground
      }
    }

    readonly property var flagRows: [
      { flag: "ctrlAsSuper", label: "Super works as Ctrl", description: "Keys Omarchy does not already use" },
      { flag: "digitTabs", label: "⌘+1..0 for the pack's tabs", description: krows.workspacesOnFkeys ? "Reserved: no tab of that number means the key does nothing" : "Needs Workspaces on F1..F10, which frees the digits" },
      { flag: "ctrlW", label: "⌘+W as Ctrl+W", description: "Close window" },
      { flag: "ctrlClick", label: "⌘+click as Ctrl+click", description: "Links, multi-select" },
      { flag: "ctrlCShift", label: "Ctrl+C as Ctrl+Shift+C", description: "Interrupt in a terminal; Super+C still copies" }
    ]

    Repeater {
      model: krows.flagRows
      SwitchRow {
        required property var modelData
        width: krows.width
        label: modelData.label
        description: {
          var st = Logic.keyFlagState(krows.cfg, krows.forced, modelData.flag)
          return (krows.isApp && st.locked) ? "Set for every app" : modelData.description
        }
        checked: Logic.keyFlagState(krows.cfg, krows.forced, modelData.flag).checked
        rowEnabled: !(krows.isApp && Logic.keyFlagState(krows.cfg, krows.forced, modelData.flag).locked)
        onToggled: krows.flagToggled(modelData.flag, !Logic.keyFlagState(krows.cfg, krows.forced, modelData.flag).checked)
      }
    }

    PanelSeparator {
      width: krows.width
      visible: krows.occupiedKeys.length > 0
      foreground: root.contentForeground
    }

    Repeater {
      model: krows.occupiedKeys
      SwitchRow {
        required property var modelData
        width: krows.width
        label: Logic.stealToggleLabel(modelData.label || modelData.id)
        description: {
          var st = Logic.keyStealState(krows.cfg, krows.forced, modelData.id)
          return (krows.isApp && st.locked) ? "Set for every app" : String(modelData.description || "")
        }
        checked: Logic.keyStealState(krows.cfg, krows.forced, modelData.id).checked
        rowEnabled: !(krows.isApp && Logic.keyStealState(krows.cfg, krows.forced, modelData.id).locked)
        onToggled: krows.keyToggled(modelData.id, !Logic.keyStealState(krows.cfg, krows.forced, modelData.id).checked)
      }
    }
  }

  // App list row: icon + class name + the focused window's title, like the
  // Bluetooth paired-device rows.
  component AppRow: CursorSurface {
    id: arow
    required property var modelData

    implicitHeight: arowContent.implicitHeight + Style.spacing.rowPaddingX
    foreground: root.contentForeground
    hasCursor: arowMouse.containsMouse

    MouseArea {
      id: arowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openCls = String(arow.modelData.cls).toLowerCase()
    }

    Item {
      id: arowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(Style.font.iconLarge, arowInfo.implicitHeight)

      AppIcon {
        width: Style.font.iconLarge
        height: Style.font.iconLarge
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        cls: String(arow.modelData.cls)
        source: root.appIcon(arow.modelData.cls)
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
        letterPixelSize: Style.font.body
      }

      Column {
        id: arowInfo
        spacing: Style.space(1)
        anchors.left: parent.left
        anchors.leftMargin: Style.font.iconLarge + Style.space(10)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        Text {
          text: root.appName(arow.modelData.cls)
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          visible: text !== ""
          text: String(arow.modelData.title || "").trim()
          color: Qt.darker(root.contentForeground, 1.5)
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: searchField
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, root.cardCap)

    Column {
      id: column
      width: parent.width
      // Match the card's inner height and clip, so a miscalculation can never
      // paint content over the popup border.
      height: parent.height
      clip: true
      spacing: Style.space(14)

      // Hero: X Mode icon, name and status, with the on/off switch on the
      // trailing edge — same layout as the Bluetooth header.
      Item {
        id: hero
        width: parent.width
        implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight)

        Text {
          id: heroIcon
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "󰀵"
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.display
          opacity: root.xModeOn ? 1.0 : 0.5
        }

        ToggleSwitch {
          id: powerSwitch
          checked: root.xModeOn
          foreground: root.contentForeground
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          onToggled: {
            if (root.hostWidget && root.hostWidget.setOn)
              root.hostWidget.setOn(!root.xModeOn)
          }
        }

        Column {
          id: heroLabels
          anchors.left: heroIcon.right
          anchors.leftMargin: Style.space(14)
          anchors.right: parent.right
          anchors.rightMargin: powerSwitch.width + Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Text {
            text: "X Mode"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }
          Text {
            textFormat: Text.PlainText
            text: (root.xModeOn ? "On" : "Off").toUpperCase()
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            elide: Text.ElideRight
            width: parent.width
          }
        }
      }

      PanelSeparator { id: sepTop; foreground: root.contentForeground }

      SwitchRow {
        id: scrollRow
        width: parent.width
        visible: root.view === "main"
        label: "Native scroll"
        description: "Natural (reversed) touchpad scrolling"
        checked: root.nativeScroll
        rowEnabled: root.xModeOn
        onToggled: root.setOptions(!root.nativeScroll, root.ctrlTabSwitch, root.noGaps, root.workspacesOnFkeys)
      }

      SwitchRow {
        id: gapsRow
        width: parent.width
        visible: root.view === "main"
        label: "No gaps"
        description: "Remove the space between windows and their borders"
        checked: root.noGaps
        rowEnabled: root.xModeOn
        onToggled: root.setOptions(root.nativeScroll, root.ctrlTabSwitch, !root.noGaps, root.workspacesOnFkeys)
      }

      // The keys screen is several rows long, so the main panel gets an entry
      // like an app's card does, and the scope is decided by where it was opened.
      LinkRow {
        id: keysEntryRow
        width: parent.width
        visible: root.view === "main"
        label: "Key replacements"
        description: Logic.globalKeysSummary(root.globalKeys)
        onClicked: root.keysOpen = true
      }

      PanelSeparator {
        id: sepMid
        visible: root.view === "main"
        foreground: root.contentForeground
      }

      CursorSurface {
        id: backRow
        width: parent.width
        visible: root.view === "app" || root.keysOpen
        implicitHeight: backText.implicitHeight + Style.spacing.rowPaddingX
        foreground: root.contentForeground
        hasCursor: backMouse.containsMouse

        MouseArea {
          id: backMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            // The keys screen is a page on top of the current one, so back closes
            // it before it leaves an app's card.
            if (root.keysOpen)
              root.keysOpen = false
            else
              root.openCls = ""
          }
        }

        Text {
          id: backText
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          textFormat: Text.PlainText
          text: "Back"
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }

      PanelSectionHeader {
        id: sectionHeader
        text: root.keysOpen
          ? (root.openCls === "" ? "FOR EVERY APP" : "KEY REPLACEMENTS")
          : (root.openCls === "" ? "APPS" : root.appName(root.openApp ? root.openApp.cls : root.openCls).toUpperCase())
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
      }

      TextField {
        id: searchField
        width: parent.width
        visible: root.view === "main"
        placeholderText: "Filter apps"
        text: root.query
        foreground: root.contentForeground
        onTextChanged: root.query = text
      }

      Flickable {
        id: detailFlick
        width: parent.width
        visible: root.view === "app"
        // Same leftover-space math as the app list: the chrome flags and the
        // occupied Super keys are one page, so they scroll inside the card
        // instead of sitting above it and getting clipped.
        height: {
          var cap = root.cardCap
          var avail = panel.availableCardHeight > 0 ? panel.availableCardHeight : cap
          var cardContent = Math.max(0, Math.min(cap, avail) - panel.verticalContentInset)
          var room = cardContent - root.listFixedHeight - column.spacing
          var wanted = Math.max(Style.space(80), detailColumn.implicitHeight)
          return Math.max(Style.space(80), Math.min(wanted, room))
        }
        contentHeight: detailColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Column {
          id: detailColumn
          width: detailFlick.width
          spacing: Style.space(4)

          SwitchRow {
            width: parent.width
            label: "Titlebar and grouping"
            description: "Mac titlebar, tabs, same-app groups"
            checked: root.cfgFor(root.openCls).chrome
            onToggled: root.setFlag("chrome", !root.cfgFor(root.openCls).chrome)
          }

          SwitchRow {
            width: parent.width
            label: "Always show tabbar"
            description: "Tab strip with + even for a single window"
            checked: root.cfgFor(root.openCls).alwaysTabbar
            rowEnabled: root.cfgFor(root.openCls).chrome
            onToggled: root.setFlag("alwaysTabbar", !root.cfgFor(root.openCls).alwaysTabbar)
          }

          LinkRow {
            width: parent.width
            label: "Key replacements"
            description: Logic.appKeysSummary(root.cfgFor(root.openCls), root.globalKeys)
            onClicked: root.keysOpen = true
          }
        }
      }

      // The keys screen: one page, two scopes. Opened from the main panel it is
      // "for every app" and writes the global map; opened from a card it is that
      // app, and a row the main panel forced shows as checked and locked there.
      Flickable {
        id: keysFlick
        width: parent.width
        visible: root.view === "keys"
        height: {
          var cap = root.cardCap
          var avail = panel.availableCardHeight > 0 ? panel.availableCardHeight : cap
          var cardContent = Math.max(0, Math.min(cap, avail) - panel.verticalContentInset)
          var room = cardContent - root.keysFixedHeight - column.spacing
          var wanted = Math.max(Style.space(80), keysColumn.implicitHeight)
          return Math.max(Style.space(80), Math.min(wanted, room))
        }
        contentHeight: keysColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        KeyRows {
          id: keysColumn
          cls: root.openCls
          cfg: root.openCls === "" ? Logic.globalScopeCfg(root.globalKeys) : root.cfgFor(root.openCls)
          forced: root.openCls === "" ? ({}) : root.globalKeys
          workspacesOnFkeys: root.workspacesOnFkeys
          occupiedKeys: root.occupiedKeys
          onFlagToggled: (flag, value) => {
            if (root.openCls === "")
              root.setGlobalFlag(flag, value)
            else
              root.setFlag(flag, value)
          }
          onKeyToggled: (id, value) => {
            if (root.openCls === "")
              root.setGlobalSteal(id, value)
            else
              root.setOccupiedKey(id, value)
          }
        }
      }

      Flickable {
        id: listFlick
        width: parent.width
        visible: root.view === "main"
        // Fill only the space left under the fixed content inside the capped
        // card, so a long list scrolls in place instead of spilling past the
        // popup. `listFixedHeight` excludes this list, so this is not circular.
        height: {
          var cap = root.cardCap
          var avail = panel.availableCardHeight > 0 ? panel.availableCardHeight : cap
          var cardContent = Math.max(0, Math.min(cap, avail) - panel.verticalContentInset)
          var room = cardContent - root.listFixedHeight - column.spacing
          var wanted = Math.max(Style.space(80), appColumn.implicitHeight)
          return Math.max(Style.space(80), Math.min(wanted, room))
        }
        contentHeight: appColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: appColumn
          width: listFlick.width
          spacing: Style.space(4)

          Repeater {
            model: root.filtered
            AppRow {
              width: appColumn.width
            }
          }

          Text {
            visible: root.filtered.length === 0
            width: parent.width
            textFormat: Text.PlainText
            text: root.query === "" ? "No running apps" : "No matches"
            color: Qt.darker(root.contentForeground, 1.4)
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}