import Quickshell

// A 24px top bar for the nest, so tests run against a reserved top like the
// real Omarchy bar. tests/lib.sh runs it with `qs -p`.
ShellRoot {
  PanelWindow {
    anchors { top: true; left: true; right: true }
    implicitHeight: 24
    exclusiveZone: 24
    color: "#222222"
  }
}
