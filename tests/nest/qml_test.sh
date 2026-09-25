#!/usr/bin/env bash
# The shell plugin in a real Quickshell, against the nest.
#
# `import Quickshell` cannot be loaded by qmltestrunner (the types are linked
# into the Quickshell binary, there is no plugin to dlopen), so a component can
# only be exercised by a Quickshell process. This starts one with a minimal
# config that instantiates the plugin's Dock and checks it comes up: it catches
# a broken component (import, binding, syntax) that qmllint cannot see.
. "$(dirname "$0")/../lib.sh"

CFG="$NEST_STATE/qml"
LOG="$NEST_STATE/qml.log"
rm -rf "$CFG" "$LOG"
mkdir -p "$CFG"

# qs.* are resolved from the Quickshell config folder, so the Omarchy modules the
# plugin imports have to be reachable from it.
[ -d /usr/share/omarchy/shell/Commons ] || fail "Omarchy shell modules not found (needed for qs.Commons)"
ln -s /usr/share/omarchy/shell/Commons "$CFG/Commons"
ln -s /usr/share/omarchy/shell/Ui "$CFG/Ui"

# The plugin lives outside the config folder; an absolute path import is
# rejected, a file: URL is not.
cat > "$CFG/shell.qml" <<QML
import Quickshell
import "file:$REPO_DIR/quickshell/x-mode" as X

ShellRoot {
  X.Dock {}
}
QML

env WAYLAND_DISPLAY="$(nest_display)" HYPRLAND_INSTANCE_SIGNATURE="$SIG" QT_QPA_PLATFORM=wayland \
  setsid qs -p "$CFG" > "$LOG" 2>&1 < /dev/null &

cleanup() { pkill -f "qs -p $CFG" 2>/dev/null || true; }
trap cleanup EXIT

for _ in $(seq 1 40); do
  nest_ctl layers 2>/dev/null | grep -q "x-mode-dock" && break
  sleep 0.25
done

if ! nest_ctl layers 2>/dev/null | grep -q "x-mode-dock"; then
  sed 's/^/       /' "$LOG" >&2
  fail "the dock never created its layer in the nest"
fi

# The dock overlays: it must not have reserved space, so the bar keeps the top.
assert_eq "$(bar_top)" 24 "the dock reserves nothing"
