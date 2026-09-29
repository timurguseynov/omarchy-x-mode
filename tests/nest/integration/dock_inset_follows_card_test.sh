#!/usr/bin/env bash
# The right snap inset is the dock card plus half of gaps_out. The card width
# belongs to the dock (iconSize + pad*2); Lua has to read it off the dock's
# layer, not keep a copy. A dock whose card is twice as wide must push the
# inset by the same amount, or a right snap lands under it.
. "$(dirname "$0")/../../lib.sh"

dock_inset() {
  nest_ctl getoption plugin:hyprbars:x_mode_dock_inset | head -1 | awk '{print $2}'
}

dock_start
read -r _ _ card _ <<<"$(dock_box)"
gap="$(gaps_out)"
want=$((card + gap / 2))
assert_eq "$(dock_inset)" "$want" "the inset is the dock card plus half the gap"

# A wider card, same dock. The width is the only thing that changes, so the
# inset has nothing else it could be following.
WIDE_CFG="$NEST_STATE/dock-wide"
rm -rf "$WIDE_CFG"
mkdir -p "$WIDE_CFG"
ln -s /usr/share/omarchy/shell/Commons "$WIDE_CFG/Commons"
ln -s /usr/share/omarchy/shell/Ui "$WIDE_CFG/Ui"
cat > "$WIDE_CFG/shell.qml" <<QML
import Quickshell
import "file:$REPO_DIR/quickshell/x-mode" as X

ShellRoot {
  X.Dock { cardWidth: 80 }
}
QML

kill "$(cat "$NEST_STATE/dock.pid")" 2>/dev/null || true
env HOME="$NEST_STATE/home" \
  XDG_RUNTIME_DIR="$DOCK_RUNTIME" \
  WAYLAND_DISPLAY="$DOCK_RUNTIME/$(nest_socket)" \
  HYPRLAND_INSTANCE_SIGNATURE="$SIG" QT_QPA_PLATFORM=wayland \
  setsid qs -p "$WIDE_CFG" > "$DOCK_LOG" 2>&1 < /dev/null &
echo $! > "$NEST_STATE/dock.pid"

wide=""
for _ in $(seq 1 40); do
  wide="$(dock_layer_box x-mode-dock 2>/dev/null | awk '{print $3}' || true)"
  [ "$wide" = 80 ] && break
  sleep 0.25
done
assert_eq "$wide" 80 "the wider dock came up"

want=$((80 + gap / 2))
got=""
for _ in $(seq 1 20); do
  got="$(dock_inset)"
  [ "$got" = "$want" ] && break
  sleep 0.25
done
assert_eq "$got" "$want" "the inset follows the wider card"

dock_stop
