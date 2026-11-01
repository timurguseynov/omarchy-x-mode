#!/usr/bin/env bash
# The panel's No gaps is an xmode setting. It pulls snapped windows out to the
# edge on an xmode workspace, and it must leave Omarchy's gaps in place for
# every other mode: dwindle, scrolling, her floating. Zeroing general:gaps_out
# is what used to take the gaps off those desktops too.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"
SCRIPT="$REPO_DIR/hypr/x-mode/xmode"

xmode() {
  timeout 15 env WAYLAND_DISPLAY="$(nest_display)" XDG_RUNTIME_DIR="$NEST_RUNTIME" \
    HYPRLAND_INSTANCE_SIGNATURE="$SIG" XDG_STATE_HOME="$NEST_STATE/home/.local/state" \
    "$SCRIPT" "$@" 2>/dev/null
}

floating() {
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c.get('class') == 'foot' and c.get('mapped') and not c.get('hidden'):
        print('yes' if c.get('floating') else 'no')
        break
else:
    print('missing')
"
}

open_window foot
snap foot left

read -r bx _ _ _ _ <<<"$(win_geom foot)"
base_gaps="$(gaps_out)"
base_border="$(border_size)"
assert_ge "$base_gaps" 1 "gaps are on to begin with"
assert_ge "$bx" 1 "a snapped window is inset from the left edge"

printf '%s\n' '{"options":{"noGaps":true},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

assert_eq "$(gaps_out)" "$base_gaps" "no gaps leaves the desktop gaps for the other modes"
assert_eq "$(border_size)" "$base_border" "no gaps leaves the desktop border for the other modes"
read -r nx _ _ _ _ <<<"$(win_geom foot)"
assert_le "$nx" "$bx" "on xmode the snapped window moves toward the edge"
assert_eq "$(floating)" yes "the window stays floating while the workspace is xmode"

xmode set 1 dwindle
sleep 0.6

assert_eq "$(gaps_out)" "$base_gaps" "leaving xmode does not change the desktop gaps"
assert_eq "$(floating)" no "dwindle tiles the window the pack had floated"
read -r tx _ _ _ _ <<<"$(win_geom foot)"
assert_ge "$tx" "$base_gaps" "dwindle keeps the desktop's outer gap"

xmode set 1 xmode
sleep 0.6

assert_eq "$(floating)" yes "coming back to xmode floats the window again"
# Entering xmode deals a single window to almost-maximize. Snap it back to the
# left edge: that is the zone No gaps has to place with the desktop gap gone.
snap foot left
sleep 0.3
read -r rx _ _ _ _ <<<"$(win_geom foot)"
assert_eq "$rx" "$nx" "back on xmode the window sits on the no-gap edge"
