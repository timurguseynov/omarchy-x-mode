import QtQuick
import qs.Commons
import "logic.js" as Logic

// One app icon with a letter fallback: the image while it loads, and the
// class initial (last segment, so "dev.zed.Zed" reads "Z") when the class has
// no desktop icon or the image is not ready yet. Shared by the dock (pinned +
// running icons, drag ghost), the switcher row and the panel app list so the
// four cannot drift apart again.
Item {
  id: root

  // Window class, for the fallback letter only.
  property string cls: ""
  // Resolved icon URL (icons.iconFor(cls)). Kept as a plain string so the
  // caller owns resolution: rescan bindings keep working as before.
  property string source: ""
  // Extra gate: the dock hides both while its drag ghost is shown.
  property bool iconVisible: true
  property color foreground: Color.foreground
  property string fontFamily: ""
  // 0 means the default: 60% of the shorter side.
  property real letterPixelSize: 0

  Image {
    id: iconImg
    anchors.fill: parent
    source: root.source
    sourceSize.width: width
    sourceSize.height: height
    fillMode: Image.PreserveAspectFit
    asynchronous: false
    visible: root.iconVisible && status === Image.Ready
  }

  Text {
    anchors.centerIn: parent
    visible: root.iconVisible && iconImg.status !== Image.Ready
    text: Logic.iconLetter(root.cls)
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.letterPixelSize > 0 ? root.letterPixelSize : Math.round(Math.min(root.width, root.height) * 0.6)
  }
}
