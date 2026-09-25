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
  // `dock` is only kept so the existing `Switcher { dock: root }` in Dock.qml
  // still binds. The icon lookup moved out of the dock into IconResolver.
  property var dock: null
  IconResolver { id: icons }

  readonly property string cmdPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-switcher.cmd"

  property bool shown: false
  property bool xModeOn: true
  property string activeClass: ""
  property var classes: []

  function iconFor(cls) {
    return icons.iconFor(cls)
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
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.window.alter_zorder({ mode = \"top\", window = 'address:" + addr + "' })"])
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ window = 'address:" + addr + "' })"])
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

                Image {
                  anchors.centerIn: parent
                  source: root.iconFor(modelData.cls)
                  sourceSize.width: 40
                  sourceSize.height: 40
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
