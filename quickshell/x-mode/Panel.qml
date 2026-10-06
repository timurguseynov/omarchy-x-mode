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

  // The card's three scroll regions: the app list, an app's card, the keys
  // screen. They are what `fixedAboveHeight` below leaves out -- a region is
  // sized by the room the rest of the card leaves, so counting the region in
  // that room would be sizing it against itself.
  readonly property var scrollRegions: [listFlick, detailFlick, keysFlick]

  // Height of every visible row of the card outside the scroll regions: the
  // room a region has to leave for what sits above it.
  // Read off the card's own column rather than a hand-kept list of ids. A list
  // kept in step by hand is what left the keys screen sized for a card taller
  // than the one it was in -- it named the back row and the header, but not the
  // hero and the top separator above them -- so the region ran past the bottom
  // of the card and its last rows could not be scrolled to. A row added to the
  // column now costs every region its room on its own. The column lays its
  // children out by height, so height is what counts here. Excludes the regions
  // themselves -- referencing a region's height here would be circular.
  readonly property real fixedAboveHeight: {
    var h = 0
    var n = 0
    for (var i = 0; i < column.children.length; i++) {
      var it = column.children[i]
      if (it.visible === false || root.scrollRegions.indexOf(it) !== -1)
        continue
      h += it.height
      n++
    }
    if (n > 1)
      h += (n - 1) * column.spacing
    return h
  }

  property bool nativeScroll: false
  property bool noGaps: false
  property bool workspacesOnFkeys: false
  // The card is capped so it never spills past the popup. The app list gets a
  // taller cap than the per-app card: with the fixed content above it, the 480
  // left room for barely two rows before the list had to scroll.
  // Same cap on the app list and the per-app page: the occupied-key rows need
  // the same room, and they scroll inside the card instead of shrinking it.
  readonly property int cardCap: Style.space(720)
  property var appsCfg: ({})
  // The keyboard shortcuts forced on for every app (settings options.keys).
  // A flag here is the fallback a card's row can pin against, and the colors.toml
  // accents are what a pinned row is painted with.
  property var globalKeys: ({})
  property var accents: ({})
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

  // The class the panel is showing, under the name its desktop entry gives it
  // ("Files", not "org.gnome.Nautilus"), upper-cased for a section header.
  readonly property string openName: root.appName(root.openApp ? root.openApp.cls : root.openCls).toUpperCase()

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

  function setOccupiedKey(id, state) {
    var next = Logic.setOccupiedKey(appsCfg, openCls, id, state)
    if (!next)
      return
    appsCfg = next
    writeSettings("hyprctl eval 'if x_mode and x_mode.refresh_apps_off then x_mode.refresh_apps_off() end' >/dev/null")
  }

  // One keyboard shortcut set to a state for this app: inherit, Always on, or
  // Always off. A pin is what lets the app disagree with the desktop.
  function setKeyFlag(flag, state) {
    var next = Logic.setKeyFlag(appsCfg, openCls, flag, state)
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
      var row = { chrome: e.chrome !== false, alwaysTabbar: !!e.alwaysTabbar }
      var pinned = false
      for (var j = 0; j < Logic.KEY_FLAG_NAMES.length; j++) {
        var name = Logic.KEY_FLAG_NAMES[j]
        if (e[name] !== undefined) {
          row[name] = e[name] === true
          pinned = true
        }
      }
      var keys = e.ctrlAsSuperKeys || []
      var keysOff = e.ctrlAsSuperKeysOff || []
      if (keys.length)
        row.ctrlAsSuperKeys = keys
      if (keysOff.length)
        row.ctrlAsSuperKeysOff = keysOff
      // Only what was set: an unset flag has to stay unset, or it would read as a
      // pin once the desktop has an answer of its own.
      if (e.chrome !== false && !e.alwaysTabbar && !pinned && keys.length === 0 && keysOff.length === 0)
        continue
      apps[k] = row
    }
    var json = JSON.stringify({
      options: { nativeScroll: root.nativeScroll, noGaps: root.noGaps, workspacesOnFkeys: root.workspacesOnFkeys, lockScreenKey: root.lockKey, keys: root.globalKeys },
      apps: apps
    })
    // Atomic (see Logic.stateWriteCommand): the panel watches this file, and an
    // in-place write would have it read its own half-written settings back.
    Quickshell.execDetached([
      "sh", "-c",
      Logic.stateWriteCommand(root.settingsPath, json, followUp)
    ])
  }

  function setOptions(nativeScroll, noGaps, workspacesOnFkeys) {
    root.nativeScroll = !!nativeScroll
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
    id: themeFile
    // The theme's colors.toml, for the green and red the pinned rows use: Omarchy's
    // QML palette has no green, and these are the theme's own colours either way.
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.accents = Logic.parseThemeAccents(text())
    onFileChanged: reload()
    onLoadFailed: root.accents = ({})
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      // A read that is not an answer is a torn one, not "every flag off": keep
      // what is showing and let the writer's next event bring the real content.
      var d = Logic.readJsonAnswer(text())
      if (d === null)
        return
      var o = (d && d.options) || {}
      root.nativeScroll = !!o.nativeScroll
      root.noGaps = !!o.noGaps
      root.workspacesOnFkeys = !!o.workspacesOnFkeys
      root.globalKeys = Logic.migrateGlobalKeys(o.keys)
      root.lockKey = !(o.lockScreenKey === false)
      root.appsCfg = Logic.parseApps((d && d.apps) || {})
      root.refreshClients()
    }
    onLoadFailed: {
      root.nativeScroll = false
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
      // Same rule as the settings file: a torn read must not read as "no
      // occupied keys", which emptied the keys screen and collapsed the card
      // mid-write. A real `[]` parses, and clears the list.
      var d = Logic.readJsonAnswer(text())
      if (d === null)
        return
      var list = Array.isArray(d) ? d : []
      if (!Logic.sameOccupiedList(root.occupiedKeys, list))
        root.occupiedKeys = list
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
    // A left edge in a state's colour: green for Always on, red for Always off,
    // nothing while the row follows the desktop. The pack's rows are otherwise flat,
    // so the edge is the whole marker.
    property color tint: "transparent"
    signal toggled()

    implicitHeight: srowContent.implicitHeight + Style.spacing.rowPaddingX
    foreground: root.contentForeground
    hasCursor: srowMouse.containsMouse && srow.rowEnabled
    opacity: srow.rowEnabled ? 1 : 0.5

    Rectangle {
      visible: srow.tint !== "transparent"
      width: Style.space(2)
      height: parent.height
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      color: srow.tint
    }

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
  // a chevron. Used for the shortcuts entry from the main panel and from an
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

  // The keyboard shortcuts themselves, in one element used by both scopes: with
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
    // The theme's own green and red, read by the panel from colors.toml.
    property var accents: ({})
    // The value is the row's three-state, a string: "inherit", "on", "off".
    // Declared a bool it would turn "on" into true before the handler ever sees
    // it, and a state that matches nothing *clears* the flag instead of pinning
    // it: the switch blinked, the file was rewritten without the flag, and the
    // panel read it back as off.
    signal flagToggled(string flag, string value)
    signal keyToggled(string id, string value)

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
        id: krowsWorkspaceKeysRow
        width: parent.width
        label: "Workspaces on F1..F10"
        description: "⌘F1..F10 switch workspaces; the freed digits follow Shortcuts"
        checked: root.workspacesOnFkeys
        rowEnabled: root.xModeOn
        onToggled: root.setOptions(root.nativeScroll, root.noGaps, !root.workspacesOnFkeys)
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
      { flag: "ctrlAsSuper", label: "Super as Ctrl", description: "Keys Omarchy does not already use" },
      { flag: "digitTabs", label: "⌘1..0 for the pack's tabs", description: krows.workspacesOnFkeys ? "Reserved: no tab of that number means the key does nothing" : "Needs Workspaces on F1..F10, which frees the digits" },
      { flag: "ctrlTabSwitch", label: "⌃1..0 switches tabs", description: "Jump to a titlebar tab; off, the shortcut goes to the app" },
      { flag: "ctrlClick", label: "⌘-click as ⌃-click", description: "Links, multi-select" },
      { flag: "ctrlCShift", label: "⌃C as ⌃⇧C", description: "Interrupt in a terminal; ⌘C still copies" }
    ]

    // Green, red, or nothing: the theme's own colours for the two pinned states, out
    // of colors.toml (Omarchy's QML palette has no green), falling back to its accent
    // and urgent.
    readonly property color onTint: krows.accents.green || Color.accent
    readonly property color offTint: krows.accents.red || Color.urgent

    // How long a click's own answer stays under the switch before the row goes
    // back to what the replacement is for.
    readonly property int noticeMs: 2000

    function stateColor(state) {
      return state === "on" ? krows.onTint : state === "off" ? krows.offTint : "transparent"
    }

    Repeater {
      model: krows.flagRows
      SwitchRow {
        id: flagRow
        required property var modelData
        // In a card the row is three-state; on the "for every app" screen it is the
        // desktop's own answer, so a plain switch with no "Always" to say.
        readonly property var st: krows.isApp
          ? Logic.keyFlagState(krows.cfg, krows.forced, modelData.flag)
          : Logic.keyFlagState(krows.cfg, ({}), modelData.flag)
        // Set by the click, cleared a moment later, so the row shows the state
        // it was just put into and then its meaning again (appRowDescription).
        property bool notice: false
        width: krows.width
        label: modelData.label
        description: krows.isApp
          ? Logic.appRowDescription(st.state, st.global, flagRow.notice, modelData.description)
          : modelData.description
        checked: st.checked
        tint: krows.isApp ? krows.stateColor(st.state) : "transparent"
        onToggled: {
          if (krows.isApp) {
            flagRow.notice = true
            flagNoticeTimer.restart()
          }
          krows.flagToggled(modelData.flag, krows.isApp ? Logic.nextKeyFlagState(st.state) : (st.checked ? "off" : "on"))
        }

        Timer {
          id: flagNoticeTimer
          interval: krows.noticeMs
          onTriggered: flagRow.notice = false
        }
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
        id: stealRow
        required property var modelData
        readonly property var st: krows.isApp
          ? Logic.keyStealState(krows.cfg, krows.forced, modelData.id)
          : ({ state: Logic.hasGlobalSteal(krows.forced, modelData.id) ? "on" : "off", checked: Logic.hasGlobalSteal(krows.forced, modelData.id), global: false, pinned: false })
        // Same notice as the flag rows above.
        property bool notice: false
        width: krows.width
        label: Logic.stealToggleLabel(modelData.label || modelData.id)
        description: krows.isApp
          ? Logic.appRowDescription(st.state, st.global, stealRow.notice, modelData.description)
          : String(modelData.description || "")
        checked: st.checked
        tint: krows.isApp ? krows.stateColor(st.state) : "transparent"
        onToggled: {
          if (krows.isApp) {
            stealRow.notice = true
            stealNoticeTimer.restart()
          }
          krows.keyToggled(modelData.id, krows.isApp ? Logic.nextKeyFlagState(st.state) : (st.checked ? "off" : "on"))
        }

        Timer {
          id: stealNoticeTimer
          interval: krows.noticeMs
          onTriggered: stealRow.notice = false
        }
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
        onToggled: root.setOptions(!root.nativeScroll, root.noGaps, root.workspacesOnFkeys)
      }

      SwitchRow {
        id: gapsRow
        width: parent.width
        visible: root.view === "main"
        label: "No gaps"
        description: "Remove the space between windows and their borders"
        checked: root.noGaps
        rowEnabled: root.xModeOn
        onToggled: root.setOptions(root.nativeScroll, !root.noGaps, root.workspacesOnFkeys)
      }

      // The keys screen is several rows long, so the main panel gets an entry
      // like an app's card does, and the scope is decided by where it was opened.
      LinkRow {
        id: keysEntryRow
        width: parent.width
        visible: root.view === "main"
        label: "Shortcuts"
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
        // Which screen this is, in the panel's small-caps: the app list, the
        // shortcuts screen for every app or for one app (by its real name, so the
        // header says whose card it is), or the app's own card.
        text: root.keysOpen
          ? (root.openCls === "" ? "EVERY APP: SHORTCUTS" : root.openName + ": SHORTCUTS")
          : (root.openCls === "" ? "APPS" : root.openName)
        width: parent.width
        elide: Text.ElideRight
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
          var room = cardContent - root.fixedAboveHeight - column.spacing
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
            label: "Shortcuts"
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
          var room = cardContent - root.fixedAboveHeight - column.spacing
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
          forced: root.openCls === "" ? root.globalKeys : root.globalKeys
          accents: root.accents
          workspacesOnFkeys: root.workspacesOnFkeys
          occupiedKeys: root.occupiedKeys
          onFlagToggled: (flag, state) => {
            if (root.openCls === "")
              root.setGlobalFlag(flag, Logic.triState(state) === "on")
            else
              root.setKeyFlag(flag, state)
          }
          onKeyToggled: (id, state) => {
            if (root.openCls === "")
              root.setGlobalSteal(id, Logic.triState(state) === "on")
            else
              root.setOccupiedKey(id, state)
          }
        }
      }

      Flickable {
        id: listFlick
        width: parent.width
        visible: root.view === "main"
        // Fill only the space left under the fixed content inside the capped
        // card, so a long list scrolls in place instead of spilling past the
        // popup. `fixedAboveHeight` excludes the regions, so this is not circular.
        height: {
          var cap = root.cardCap
          var avail = panel.availableCardHeight > 0 ? panel.availableCardHeight : cap
          var cardContent = Math.max(0, Math.min(cap, avail) - panel.verticalContentInset)
          var room = cardContent - root.fixedAboveHeight - column.spacing
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