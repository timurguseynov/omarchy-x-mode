import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// X Mode settings: global on/off, then a list of apps. Opening an app shows
// two toggles: chrome (titlebar/tabbar/grouping) and always-show tabbar.
Panel {
  id: root
  moduleName: "x-mode.toggle"
  ipcTarget: "x-mode.toggle"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property bool xModeOn: true
  readonly property var barIdentity: hostWidget || root

  readonly property string appsPath: (Quickshell.env("HOME") || "") + "/.local/state/omarchy-x-mode/apps.json"
  readonly property string optionsPath: (Quickshell.env("HOME") || "") + "/.local/state/omarchy-x-mode/options.json"
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // Height of everything except the scrolling app list. The panel card is
  // capped (see contentHeight), so the list must be sized to the space that is
  // actually left under the fixed content -- otherwise a long list overflows
  // the card, which does not clip its children.
  readonly property real listFixedHeight: {
    var items = []
    if (toggleX.visible) items.push(toggleX)
    if (toggleScroll.visible) items.push(toggleScroll)
    if (sepRow.visible) items.push(sepRow)
    if (sectionHeader.visible) items.push(sectionHeader)
    if (searchField.visible) items.push(searchField)
    if (detailColumn.visible) items.push(detailColumn)
    var h = 0
    for (var i = 0; i < items.length; i++) {
      h += items[i].implicitHeight
      if (i > 0)
        h += column.spacing
    }
    return h
  }

  property bool nativeScroll: false
  property var appsCfg: ({})
  property var running: []
  property string query: ""
  property string openCls: ""

  readonly property var filtered: {
    var q = String(query || "").trim().toLowerCase()
    var out = []
    for (var i = 0; i < running.length; i++) {
      var a = running[i]
      if (q === "" || String(a.cls).toLowerCase().indexOf(q) >= 0 || String(a.title || "").toLowerCase().indexOf(q) >= 0)
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
    // is the implicit default and can be dropped from apps.json.
    if (chrome && !alwaysTabbar)
      delete next[key]
    else
      next[key] = { chrome: chrome, alwaysTabbar: !!alwaysTabbar }
    appsCfg = next
    writeApps()
  }

  function writeApps() {
    var obj = {}
    for (var k in appsCfg) {
      var e = appsCfg[k]
      if (e && (e.chrome === false || e.alwaysTabbar))
        obj[k] = { chrome: e.chrome !== false, alwaysTabbar: !!e.alwaysTabbar }
    }
    var json = JSON.stringify(obj)
    Quickshell.execDetached([
      "sh", "-c",
      "mkdir -p \"$HOME/.local/state/omarchy-x-mode\" && printf '%s\\n' " + shellQuote(json) + " > \"$HOME/.local/state/omarchy-x-mode/apps.json\" && hyprctl eval 'if x_mode and x_mode.refresh_apps_off then x_mode.refresh_apps_off() end' >/dev/null"
    ])
  }

  function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function setOptions(nativeScroll) {
    root.nativeScroll = !!nativeScroll
    var json = JSON.stringify({ nativeScroll: root.nativeScroll })
    var on = root.nativeScroll ? "true" : "false"
    Quickshell.execDetached([
      "sh", "-c",
      "mkdir -p \"$HOME/.local/state/omarchy-x-mode\" && printf '%s\\n' " + shellQuote(json) + " > \"$HOME/.local/state/omarchy-x-mode/options.json\" && hyprctl eval 'hl.config({ input = { natural_scroll = " + on + ", touchpad = { natural_scroll = " + on + " } } })' >/dev/null && hyprctl eval 'if x_mode and x_mode.refresh_options then x_mode.refresh_options() end' >/dev/null"
    ])
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
      var d = JSON.parse(raw)
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
    id: appsFile
    path: root.appsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.appsCfg = root.parseApps(text())
      root.refreshClients()
    }
    onLoadFailed: root.appsCfg = {}
  }

  FileView {
    id: optionsFile
    path: root.optionsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var d = JSON.parse(text())
        root.nativeScroll = !!(d && d.nativeScroll)
      } catch (e) {
        root.nativeScroll = false
      }
    }
    onLoadFailed: {
      root.nativeScroll = false
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
      spacing: Style.spacing.md

      Toggle {
        id: toggleX
        width: parent.width
        visible: root.openCls === ""
        label: "X Mode"
        description: "Titlebars, snap, grouping, dock"
        checked: root.xModeOn
        foreground: root.contentForeground
        onClicked: {
          if (root.hostWidget && root.hostWidget.setOn)
            root.hostWidget.setOn(!root.xModeOn)
        }
      }

      Toggle {
        id: toggleScroll
        width: parent.width
        visible: root.openCls === ""
        enabled: root.xModeOn
        opacity: root.xModeOn ? 1 : 0.45
        label: "Native scroll"
        description: "Natural (reversed) touchpad scrolling"
        checked: root.nativeScroll
        foreground: root.contentForeground
        onClicked: {
          if (!root.xModeOn)
            return
          root.setOptions(!root.nativeScroll)
        }
      }

      PanelSeparator { id: sepRow; width: parent.width; visible: root.openCls === "" }

      BorderSurface {
        id: backRow
        visible: root.openCls !== ""
        implicitHeight: backText.implicitHeight + Style.spacing.sm * 2
        implicitWidth: backText.implicitWidth + Style.spacing.rowPaddingX * 2 + borderLeft + borderRight
        radius: Style.cornerRadius
        readonly property bool _hot: backMouse.containsMouse
        color: Style.controlFill(false, _hot, root.contentForeground, Color.accent)
        borderSpec: Border.controlSpec(_hot ? "hover-cursor" : "normal", root.contentForeground, Color.accent)
        Behavior on color { ColorAnimation { duration: 100 } }

        Text {
          id: backText
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: parent.borderLeft + Style.spacing.rowPaddingX
          textFormat: Text.PlainText
          text: "Back"
          color: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        MouseArea {
          id: backMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openCls = ""
        }
      }

      PanelSectionHeader {
        id: sectionHeader
        text: root.openCls === "" ? "APPS" : String(root.openApp ? root.openApp.cls : root.openCls).toUpperCase()
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
        spacing: Style.spacing.sm
        visible: root.openCls !== ""

        Toggle {
          width: parent.width
          label: "Titlebar and grouping"
          description: "Mac titlebar, tabs, same-app groups"
          checked: root.cfgFor(root.openCls).chrome
          foreground: root.contentForeground
          onClicked: {
            var c = root.cfgFor(root.openCls)
            root.setCfg(root.openCls, !c.chrome, c.alwaysTabbar)
          }
        }

        Toggle {
          width: parent.width
          enabled: root.cfgFor(root.openCls).chrome
          opacity: enabled ? 1 : 0.45
          label: "Always show tabbar"
          description: "Tab strip with + even for a single window"
          checked: root.cfgFor(root.openCls).alwaysTabbar
          foreground: root.contentForeground
          onClicked: {
            var c = root.cfgFor(root.openCls)
            if (!c.chrome)
              return
            root.setCfg(root.openCls, true, !c.alwaysTabbar)
          }
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
          spacing: Style.spacing.xs

          Repeater {
            model: root.filtered
            BorderSurface {
              required property var modelData
              id: appRow
              width: appColumn.width
              implicitHeight: Math.max(48, appRowText.implicitHeight + Style.spacing.huge)
              radius: Style.cornerRadius
              readonly property bool _hot: appRowMouse.containsMouse
              color: Style.controlFill(false, _hot, root.contentForeground, Color.accent)
              borderSpec: Border.controlSpec(_hot ? "hover-cursor" : "normal", root.contentForeground, Color.accent)
              Behavior on color { ColorAnimation { duration: 100 } }

              Text {
                id: appRowText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: parent.borderLeft + Style.spacing.rowPaddingX
                anchors.rightMargin: parent.borderRight + Style.spacing.rowPaddingX
                textFormat: Text.PlainText
                text: appRow.modelData.cls
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                elide: Text.ElideRight
              }

              MouseArea {
                id: appRowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openCls = String(appRow.modelData.cls).toLowerCase()
              }
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
