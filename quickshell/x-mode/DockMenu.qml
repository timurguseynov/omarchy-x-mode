import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons

// Right-click context menu for a dock icon: a full-screen overlay layer that
// lets clicks everywhere except the dock strip fall through (so a right-click
// on another icon swaps the menu in one click), with the card aligned to the
// icon it was opened from. Only instantiated while open, so the overlay never
// captures input when closed.
//
// State (what is open, where, which rows) stays on the dock: this component
// only draws `actions` and reports back via pick/close.
Item {
  id: root

  required property var screen
  property bool open: false
  property var actions: []
  // Screen Y of the icon the menu was opened from.
  property real menuY: 0
  property int pad: 7
  property int cardWidth: 40
  property int dockGap: 0
  property int dockRadius: 0

  signal pick(string id)
  signal close()

  Loader {
    active: root.open

    sourceComponent: Component {
      PanelWindow {
        id: menuPanel
        screen: root.screen
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
          width: root.screen.width
          height: root.screen.height

          Region {
            intersection: Intersection.Subtract
            x: root.screen.width - root.cardWidth - root.dockGap
            y: 0
            width: root.cardWidth + root.dockGap
            height: root.screen.height
          }
        }

        MouseArea {
          anchors.fill: parent
          onClicked: root.close()
        }

        Rectangle {
          id: menuCard
          width: 240
          height: menuCol.implicitHeight + 12
          x: root.screen.width - root.dockGap - root.cardWidth - width - (Style.gapsOut * 2)
          // Align the popup with the icon it was opened from (the card's
          // pad puts the first row at the icon's top).
          y: Math.max(8, Math.min(root.screen.height - height - 8, root.menuY - root.pad))
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
              model: root.actions

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
                  onClicked: root.pick(modelData.id)
                }
              }
            }
          }
        }
      }
    }
  }
}
