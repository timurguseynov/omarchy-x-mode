import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import "logic.js" as Logic

// Cmd+Tab app switcher preview: a centered row of app icons with the active app
// highlighted. Driven by the command file x-mode.lua writes:
//   show <active-class> <class>...
//   hide
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  // Icon lookup reuses the dock's resolver (one scan per shell process),
  // so this component owns no IconResolver of its own. Without a dock the
  // row still shows the class letters.
  property var dock: null

  readonly property string cmdPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-switcher.cmd"

  property bool shown: false
  property bool xModeOn: true
  property string activeClass: ""
  property var classes: []

  function iconFor(cls) {
    if (root.dock && typeof root.dock.iconFor === "function")
      return root.dock.iconFor(cls)
    return ""
  }

  function applyXModeLine(raw) {
    var on = Logic.parseEnabled(raw)
    if (on === null)
      return
    root.xModeOn = on
    if (!on)
      root.shown = false
  }

  function applyCmd(raw) {
    var m = Logic.parseSwitcherCmd(raw, root.xModeOn)
    root.activeClass = m.activeClass
    root.classes = m.classes
    root.shown = m.shown
  }

  // Click an icon: raise + focus that window (by address, like the dock) and
  // hide the switcher.
  function pick(addr) {
    if (!addr)
      return
    // Same dispatcher as the dock. hyprbars.raise is not a dispatcher, so
    // hl.dispatch rejects that string. window.active raises the floating window.
    Hyprland.dispatch("hl.dsp.focus({ window = 'address:" + addr + "' })")
    root.shown = false
  }

  FileView {
    id: cmdView
    path: root.cmdPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyCmd(text())
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
      PanelWindow {
        id: panel
        required property var modelData

        screen: modelData
        visible: root.shown
        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }
        color: "transparent"
        WlrLayershell.namespace: "omarchy-switcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        // Only the switcher box takes pointer input (click an icon to switch).
        mask: Region { item: switcherBox }

        Rectangle {
          id: switcherBox
          anchors.centerIn: parent
          width: row.implicitWidth + Style.space(28)
          height: row.implicitHeight + Style.space(24)
          radius: Style.cornerRadius
          color: Util.alpha(Color.background, 0.94)
          border.color: Util.alpha(Color.foreground, 0.14)
          border.width: 1
          opacity: root.shown ? 1 : 0

          Behavior on opacity { NumberAnimation { duration: 90 } }

          Row {
            id: row
            anchors.centerIn: parent
            spacing: Style.space(14)

            Repeater {
              model: root.classes

              delegate: Item {
                width: 48
                height: 48

                // A class with no desktop icon (a portal file dialog, a
                // terminal launched under another app id) would otherwise be a
                // blank slot. Same letter the dock draws until the image loads.
                AppIcon {
                  anchors.centerIn: parent
                  width: 40
                  height: 40
                  cls: String(modelData.cls)
                  source: root.iconFor(modelData.cls)
                  letterPixelSize: 22
                  opacity: modelData.cls === root.activeClass ? 1 : 0.45
                }

                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  width: 5
                  height: 5
                  radius: 2
                  color: Color.accent
                  visible: modelData.cls === root.activeClass
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.pick(modelData.addr)
                }
              }
            }
          }
        }
      }
    }
  }
}
