import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// X Mode settings, laid out like the Omarchy Bluetooth panel: a hero header
// with the on/off switch, settings rows, then the app list. Opening an app
// shows its two chrome toggles.
Panel {
  id: root
  moduleName: "x-mode.toggle"
  ipcTarget: "x-mode.toggle"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property bool xModeOn: true
  readonly property var barIdentity: hostWidget || root

  readonly property string settingsPath: (Quickshell.env("HOME") || "") + "/.local/state/omarchy-x-mode/settings.json"
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // Height of every element except the scrolling app list, so the list can be
  // sized to the space actually left in the capped card. Excludes `listFlick`
  // itself -- referencing its height here would be circular.
  readonly property real listFixedHeight: {
    var items = [hero, sepTop, scrollRow, tabKeysRow, gapsRow, sepMid, backRow, sectionHeader, searchField, detailColumn]
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
  property var appsCfg: ({})
  property var running: []
  property string query: ""
  property string openCls: ""

  readonly property var filtered: {
    var q = String(query || "").trim().toLowerCase()
    var out = []
    for (var i = 0; i < running.length; i++) {
      var a = running[i]
      if (q === "" || String(a.cls).toLowerCase().indexOf(q) >= 0 || root.appName(a.cls).toLowerCase().indexOf(q) >= 0 || String(a.title || "").toLowerCase().indexOf(q) >= 0)
        out.push(a)
    }
    return out
  }

  readonly property var openApp: {
    if (openCls === "")
      return null
    for (var i = 0; i < running.length; i++) {
      if (String(running[i].cls).toLowerCase() === openCls)
        return running[i]
    }
    return { cls: openCls, title: "" }
  }

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
    var key = String(cls || "").toLowerCase()
    var e = appsCfg[key]
    if (!e)
      return { chrome: true, alwaysTabbar: false }
    return {
      chrome: e.chrome !== false,
      alwaysTabbar: !!e.alwaysTabbar
    }
  }

  function setCfg(cls, chrome, alwaysTabbar) {
    var key = String(cls || "").toLowerCase()
    if (key === "")
      return
    var next = {}
    for (var k in appsCfg)
      next[k] = appsCfg[k]
    // Persist only non-default chrome (off) or alwaysTabbar; chrome-on alone
    // is the implicit default and can be dropped from the app list.
    if (chrome && !alwaysTabbar)
      delete next[key]
    else
      next[key] = { chrome: chrome, alwaysTabbar: !!alwaysTabbar }
    appsCfg = next
    writeSettings("hyprctl eval 'if x_mode and x_mode.refresh_apps_off then x_mode.refresh_apps_off() end' >/dev/null")
  }

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  // The panel's whole state in one file, so the options and the app list can
  // never drift apart. `followUp` is the hyprctl call the change needs.
  function writeSettings(followUp) {
    var apps = {}
    for (var k in appsCfg) {
      var e = appsCfg[k]
      if (e && (e.chrome === false || e.alwaysTabbar))
        apps[k] = { chrome: e.chrome !== false, alwaysTabbar: !!e.alwaysTabbar }
    }
    var json = JSON.stringify({
      options: { nativeScroll: root.nativeScroll, ctrlTabSwitch: root.ctrlTabSwitch, noGaps: root.noGaps },
      apps: apps
    })
    Quickshell.execDetached([
      "sh", "-c",
      "mkdir -p \"$HOME/.local/state/omarchy-x-mode\" && printf '%s\\n' " + shellQuote(json) + " > \"$HOME/.local/state/omarchy-x-mode/settings.json\" && " + followUp
    ])
  }

  function setOptions(nativeScroll, ctrlTabSwitch, noGaps) {
    root.nativeScroll = !!nativeScroll
    root.ctrlTabSwitch = !!ctrlTabSwitch
    root.noGaps = !!noGaps
    // The reload re-runs the config, which reapplies every option from
    // settings.json, and emits configreloaded. The dock only re-reads its screen
    // margin on that event, so without the reload it stays at the old gap. It is
    // the only step: the natural-scroll eval that used to run first could fail,
    // and with `&&` that skipped the reload and left the option unapplied.
    writeSettings("hyprctl reload >/dev/null")
  }

  function rebuildRunning(clients) {
    var by = {}
    for (var i = 0; i < clients.length; i++) {
      var c = clients[i]
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
    for (var k in appsCfg) {
      if (!by[k])
        by[k] = { cls: k, title: "", focus: 999998 }
    }
    var list = []
    for (var k2 in by)
      list.push(by[k2])
    list.sort(function(a, b) { return String(a.cls).localeCompare(String(b.cls)) })
    running = list
  }

  function refreshClients() {
    clientsProc.running = true
  }

  function parseApps(raw) {
    var set = {}
    try {
      // The merged settings file hands the apps object over already parsed;
      // the old standalone apps.json was a JSON string.
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

  onOpenedChanged: {
    if (opened) {
      openCls = ""
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
        root.appsCfg = root.parseApps((d && d.apps) || {})
      } catch (e) {
        root.nativeScroll = false
        root.ctrlTabSwitch = false
        root.noGaps = false
        root.appsCfg = {}
      }
      root.refreshClients()
    }
    onLoadFailed: {
      root.nativeScroll = false
      root.ctrlTabSwitch = false
      root.noGaps = false
      root.appsCfg = {}
    }
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

      Image {
        id: arowIcon
        width: Style.font.iconLarge
        height: Style.font.iconLarge
        source: root.appIcon(arow.modelData.cls)
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        asynchronous: false
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: status === Image.Ready
      }

      Text {
        visible: !arowIcon.visible
        text: String(arow.modelData.cls).charAt(0).toUpperCase()
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.body
        width: Style.font.iconLarge
        height: Style.font.iconLarge
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(480))

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
        visible: root.openCls === ""
        label: "Native scroll"
        description: "Natural (reversed) touchpad scrolling"
        checked: root.nativeScroll
        rowEnabled: root.xModeOn
        onToggled: root.setOptions(!root.nativeScroll, root.ctrlTabSwitch, root.noGaps)
      }

      SwitchRow {
        id: tabKeysRow
        width: parent.width
        visible: root.openCls === ""
        label: "Ctrl+1..9 switches tabs"
        description: "Jump to a titlebar tab; off, the shortcut goes to the app"
        checked: root.ctrlTabSwitch
        rowEnabled: root.xModeOn
        onToggled: root.setOptions(root.nativeScroll, !root.ctrlTabSwitch, root.noGaps)
      }

      SwitchRow {
        id: gapsRow
        width: parent.width
        visible: root.openCls === ""
        label: "No gaps"
        description: "Remove the space between windows and their borders"
        checked: root.noGaps
        rowEnabled: root.xModeOn
        onToggled: root.setOptions(root.nativeScroll, root.ctrlTabSwitch, !root.noGaps)
      }

      PanelSeparator {
        id: sepMid
        visible: root.openCls === ""
        foreground: root.contentForeground
      }

      CursorSurface {
        id: backRow
        width: parent.width
        visible: root.openCls !== ""
        implicitHeight: backText.implicitHeight + Style.spacing.rowPaddingX
        foreground: root.contentForeground
        hasCursor: backMouse.containsMouse

        MouseArea {
          id: backMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openCls = ""
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
        text: root.openCls === "" ? "APPS" : root.appName(root.openApp ? root.openApp.cls : root.openCls).toUpperCase()
        foreground: root.contentForeground
        fontFamily: root.contentFontFamily
      }

      TextField {
        id: searchField
        width: parent.width
        visible: root.openCls === ""
        placeholderText: "Filter apps"
        text: root.query
        foreground: root.contentForeground
        onTextChanged: root.query = text
      }

      Column {
        id: detailColumn
        width: parent.width
        spacing: Style.space(4)
        visible: root.openCls !== ""

        SwitchRow {
          width: parent.width
          label: "Titlebar and grouping"
          description: "Mac titlebar, tabs, same-app groups"
          checked: root.cfgFor(root.openCls).chrome
          onToggled: {
            var c = root.cfgFor(root.openCls)
            root.setCfg(root.openCls, !c.chrome, c.alwaysTabbar)
          }
        }

        SwitchRow {
          width: parent.width
          label: "Always show tabbar"
          description: "Tab strip with + even for a single window"
          checked: root.cfgFor(root.openCls).alwaysTabbar
          rowEnabled: root.cfgFor(root.openCls).chrome
          onToggled: root.setCfg(root.openCls, true, !root.cfgFor(root.openCls).alwaysTabbar)
        }
      }

      Flickable {
        id: listFlick
        width: parent.width
        visible: root.openCls === ""
        // Fill only the space left under the fixed content inside the capped
        // card, so a long list scrolls in place instead of spilling past the
        // popup. `listFixedHeight` excludes this list, so this is not circular.
        height: {
          var cap = Style.space(480)
          var avail = panel.availableCardHeight > 0 ? panel.availableCardHeight : cap
          var cardContent = Math.max(0, Math.min(cap, avail) - panel.verticalContentInset)
          var room = cardContent - root.listFixedHeight - column.spacing
          var wanted = Math.max(Style.space(80), appColumn.implicitHeight)
          return Math.max(Style.space(80), Math.min(Style.space(280), wanted, room))
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