#!/usr/bin/env bash
# install.sh's bar-workspace step is the one place that rewrites a file Omarchy
# owns, and the shape of that file is not ours to assume: Omarchy 4.0.6 ships a
# different, 2 KB Workspaces.qml with none of the anchors the patch rewrites.
# A mismatch used to take the whole install down rather than skip the step --
# the `if [ $? -ne 0 ]` guard after the patch could never run under
# `set -euo pipefail`, so the script died there, before it wired hyprland.lua,
# and left the pack installed but inert. This pins both behaviours: a widget
# that does not match warns and leaves nothing behind, a widget that matches is
# patched.
#
# install.sh is sourced for the step; running it is what installs, so the step
# has to be reachable on its own.
. "$(dirname "$0")/lib.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home/.config" "$TMP/src"
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$TMP/home/.config"
export XDG_STATE_HOME="$TMP/home/.local/state"

# shellcheck disable=SC1091
. "$REPO_DIR/install.sh"

PLUGINS_DIR="$TMP/plugins"
WORKSPACES_SRC="$TMP/src/Workspaces.qml"
DEST="$PLUGINS_DIR/$WORKSPACES_PLUGIN"

# 1. A widget without the anchors (the 4.0.6 shape): the step gives up, and the
#    install keeps going. Run in a subshell that has `set -e` on, because that is
#    how the installer runs it -- inside an `if` or a `||` list the failure would
#    be swallowed and the bug would not show.
printf '%s\n' 'import QtQuick' 'Item {' '  moduleName: "omarchy.workspaces"' '}' > "$WORKSPACES_SRC"
( set -e; workspaces_bar_install ) >"$TMP/out" 2>&1
status=$?
[ "$status" -eq 0 ] || fail "a widget without the anchors aborted the install (exit $status) instead of warning: $(cat "$TMP/out")"
[ -d "$DEST" ] && fail "a widget without the anchors still left $DEST behind"
grep -q "changed shape" "$TMP/out" || fail "a widget without the anchors did not say why the step was skipped: $(cat "$TMP/out")"

# 2. A widget with the anchors (the 4.5 shape): patched into the pack's copy.
#    The fixture carries the glyph block exactly as install.sh matches it -- real
#    characters, since those are what the installed widget holds.
python3 - "$WORKSPACES_SRC" <<'PY'
import sys

text = '''import QtQuick

Item {
  moduleName: "omarchy.workspaces"

  function modeGlyph(mode) {
    if (mode === "scrolling") return "\U000f0765"
    if (mode === "floating") return "\U000f0536"
    return "\U000f14fb"
  }

  var command = "omarchy-hyprland-workspace-layout-toggle"
}
'''
open(sys.argv[1], "w").write(text)
PY
( set -e; workspaces_bar_install ) >"$TMP/out2" 2>&1
status=$?
[ "$status" -eq 0 ] || fail "the step failed on a widget it can patch (exit $status): $(cat "$TMP/out2")"
[ -f "$DEST/Workspaces.qml" ] || fail "a widget with the anchors was not patched: $(cat "$TMP/out2")"
grep -qF 'moduleName: "x-mode.workspaces"' "$DEST/Workspaces.qml" || fail "the patched widget kept Omarchy's module name"
grep -qF ' next"' "$DEST/Workspaces.qml" || fail "the patched widget does not run the pack's layout cycle"
[ -f "$DEST/manifest.json" ] || fail "the patched widget has no manifest"

echo "  ok   the bar-workspace step skips a widget it cannot patch, and patches one it can"
