import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "logic.js" as Logic

// Bar button for the x-mode desktop. Click opens the settings panel
// (global on/off + per-app chrome). Same popout contract as omarchy.clock.
BarWidget {
  id: root
  moduleName: "x-mode.toggle"

  readonly property string statePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-x-mode.state"
  readonly property string persistPath: (Quickshell.env("HOME") || "") + "/.local/state/omarchy-x-mode/enabled"
  property bool on: true

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  // Same as other icon bar widgets: leave openPanelIndicatorWidth unset so
  // Bar.qml uses slot.width * 0.55. Only text modules (clock) override it.
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function applyLine(raw) {
    var on = Logic.parseEnabled(raw)
    if (on !== null)
      root.on = on
  }

  function setOn(value) {
    var next = !!value
    root.on = next
    var line = next ? "on" : "off"
    Quickshell.execDetached([
      "sh", "-c",
      "mkdir -p \"$HOME/.local/state/omarchy-x-mode\" && printf '%s\\n' '" + line + "' > \"$HOME/.local/state/omarchy-x-mode/enabled\" && hyprctl reload >/dev/null"
    ])
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("xModeOn" in target) target.xModeOn = root.on
  }

  onOnChanged: injectPanel()
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  FileView {
    id: persistFile
    path: root.persistPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyLine(text())
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyLine(text())
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || event.name !== "xmode")
        return
      root.applyLine(event.data)
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Same Nerd Font apple glyph Omarchy uses for macOS/iOS (tailscale Model.js).
    text: "󰀵"
    tooltipText: ""
    active: root.on || root.opened
    useActiveColor: false
    dimmed: !root.on
    onPressed: function() { root.togglePanel() }
  }
}
