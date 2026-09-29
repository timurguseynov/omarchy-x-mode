import QtQuick
import Quickshell
import Quickshell.Wayland

// A 24px top bar for the nest, so tests run against a reserved top like the
// real Omarchy bar. tests/lib.sh runs it with `qs -p`. The namespace is how
// the harness tells this layer from the reserved area the output reports
// before the bar has actually mapped.
//
// The screen is not there at the moment qs loads: the nest's output is
// configured after the socket accepts. A PanelWindow created with no screen
// stays unmapped. Variants builds one when the screen appears.
ShellRoot {
  Variants {
    model: Quickshell.screens
    delegate: Component {
      PanelWindow {
        required property var modelData
        screen: modelData
        anchors { top: true; left: true; right: true }
        implicitHeight: 24
        exclusiveZone: 24
        color: "#222222"
        WlrLayershell.namespace: "x-mode-nest-bar"
      }
    }
  }
}
