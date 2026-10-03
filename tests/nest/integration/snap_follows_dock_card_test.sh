#!/usr/bin/env bash
# Regression: a window on the right zone has to follow the dock card, not just
# the inset. The inset itself follows the card (dock_inset_follows_card_test),
# but the windows already placed on a zone were left where they were -- and
# install.sh restarts the shell *after* its reload, so an install arranges
# against the fallback card width and the right-edge windows stay off by half
# the difference until the next reload. That is the state "install is flaky"
# leaves behind.
#
# The window is snapped through the plugin, not through the pack's own snap(), so
# this covers a titlebar drag-to-edge snap too, which Lua never sees.
#
# The right zone's right edge is the frame's right minus the inset, so an inset
# that grew by delta has to pull the window's right edge in by the same delta.
. "$(dirname "$0")/../../lib.sh"

dock_inset() {
  nest_ctl getoption plugin:hyprbars:x_mode_dock_inset | head -1 | awk '{print $2}'
}

dock_start
gap="$(gaps_out)"

# The dock's layer maps before it reports the width the pack can use, and the
# pack then publishes the inset it read off it. Wait for both: the window has to
# be snapped against the card this scenario is about, not the one a previous
# scenario left behind (a missing layer keeps the last width on purpose).
card=""
for _ in $(seq 1 40); do
  read -r _ _ card _ <<<"$(dock_box)" 2>/dev/null || card=""
  [ -n "$card" ] && [ "$card" -gt 0 ] && break
  sleep 0.25
done
assert_ge "${card:-0}" 1 "the dock layer reports its card width"

want1=$((card + gap / 2))
inset1=""
for _ in $(seq 1 40); do
  inset1="$(dock_inset)"
  [ "$inset1" = "$want1" ] && break
  sleep 0.25
done
assert_eq "$inset1" "$want1" "the pack reads the inset off the card before the snap"

open_window foot
snap foot right

read -r x1 _ w1 _ _ <<<"$(win_geom foot)"
right1=$((x1 + w1))

# A wider card, same dock. The width is the only thing that changes.
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

# The replacement shell sometimes loses the race against the one just killed and
# never maps. Start it, and once more if the layer stays absent.
wide_dock_start() {
  env HOME="$NEST_STATE/home" \
    XDG_RUNTIME_DIR="$DOCK_RUNTIME" \
    WAYLAND_DISPLAY="$DOCK_RUNTIME/$(nest_socket)" \
    HYPRLAND_INSTANCE_SIGNATURE="$SIG" QT_QPA_PLATFORM=wayland \
    setsid qs -p "$WIDE_CFG" > "$DOCK_LOG" 2>&1 < /dev/null &
  echo $! > "$NEST_STATE/dock.pid"
  local wide="" i
  for i in $(seq 1 80); do
    wide="$(dock_layer_box x-mode-dock 2>/dev/null | awk '{print $3}' || true)"
    [ "$wide" = 80 ] && break
    sleep 0.25
  done
  [ "$wide" = 80 ]
}

kill "$(cat "$NEST_STATE/dock.pid")" 2>/dev/null || true
if ! wide_dock_start; then
  kill "$(cat "$NEST_STATE/dock.pid")" 2>/dev/null || true
  wide_dock_start || fail "the wider dock never mapped"
fi

want=$((80 + gap / 2))
inset2=""
for _ in $(seq 1 40); do
  inset2="$(dock_inset)"
  [ "$inset2" = "$want" ] && break
  sleep 0.25
done
assert_eq "$inset2" "$want" "the inset follows the wider card"

delta=$((inset2 - inset1))
assert_ge "$delta" 1 "the card really grew (inset $inset1 -> $inset2)"

right2="$right1"
for _ in $(seq 1 40); do
  read -r x2 _ w2 _ _ <<<"$(win_geom foot)"
  right2=$((x2 + w2))
  [ "$((right1 - right2))" = "$delta" ] && break
  sleep 0.25
done
assert_between $((right1 - right2)) $((delta - 2)) $((delta + 2)) \
  "a right-snapped window follows the dock card (moved $((right1 - right2)), want $delta)"

dock_stop
