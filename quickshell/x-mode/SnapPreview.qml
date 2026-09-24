import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import "logic.js" as Logic

// Rectangle-style footprint preview: a border-only layer-shell overlay that
// tracks the snap target while a floating window is dragged to a screen edge.
// Driven by hyprbars (cmd file + xmodesnap IPC event), absolute logical pixels:
//   show <x> <y> <w> <h>
//   hide
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string cmdPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-snap-preview.cmd"

  property bool shown: false
  property bool xModeOn: true
  property real rx: 0
  property real ry: 0
  property real rw: 0
  property real rh: 0
  // Geometry follows the snap zones smoothly while visible, but must not animate
  // on the frame the preview appears (it would fly in from the previous snap).
  property bool geomAnim: false

  property color lineColor: Color.accent
  property color fillColor: Util.alpha(Color.accent, 0.12)
  property real lineWidth: Math.max(2, Math.round(Style.space(2)))
  property real cornerRadius: Style.cornerRadius
  readonly property int animMs: 90

  function intersects(s) {
    return root.shown && Logic.rectsIntersect({ x: root.rx, y: root.ry, w: root.rw, h: root.rh }, s)
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
    var m = Logic.parseSnapCmd(raw, root.xModeOn)
    if (!m.shown) {
      root.shown = false
      return
    }
    // Place without animating on the frame it appears (no fly-in from the
    // previous snap), then animate while it follows the zones.
    if (!root.shown)
      root.geomAnim = false
    root.rx = m.x
    root.ry = m.y
    root.rw = m.w
    root.rh = m.h
    root.shown = true
    if (!root.geomAnim)
      Qt.callLater(function() { root.geomAnim = true })
  }

  FileView {
    id: cmdView
    path: root.cmdPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyCmd(text())
  }

  // hyprbars also posts an IPC event on every preview change. Prefer it when
  // present so the overlay does not depend on inotify catching the file write.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event)
        return
      if (event.name === "xmode")
        root.applyXModeLine(event.data)
      else if (event.name === "xmodesnap")
        root.applyCmd(event.data)
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: panel
        required property var modelData

        screen: modelData
        visible: root.intersects(modelData)
        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }
        color: "transparent"
        WlrLayershell.namespace: "omarchy-snap-preview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        // Visual-only surface: never swallow pointer input during the drag.
        mask: Region {}

        Rectangle {
          x: root.rx - modelData.x
          y: root.ry - modelData.y
          width: root.rw
          height: root.rh
          radius: root.cornerRadius
          color: root.fillColor
          border.color: root.lineColor
          border.width: root.lineWidth
          opacity: root.shown ? 1 : 0

          Behavior on x { enabled: root.geomAnim; NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic } }
          Behavior on y { enabled: root.geomAnim; NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic } }
          Behavior on width { enabled: root.geomAnim; NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic } }
          Behavior on height { enabled: root.geomAnim; NumberAnimation { duration: root.animMs; easing.type: Easing.OutCubic } }
          Behavior on opacity { NumberAnimation { duration: root.animMs } }
        }
      }
    }
  }
}
