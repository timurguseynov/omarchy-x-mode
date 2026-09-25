#!/usr/bin/env bash
# The same cycle as snap_cycle_chrome_off_test.sh, driven by the key. The C++ snap
# reports chromeH 0 for a window with the hyprbars:no_bar rule while the Lua path
# added a titlebar anyway, so the first press was right and the second crept down.
#
# The widths have to keep cycling too, or the window is being resized down instead
# of snapping.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_STATE/state/settings.json"

printf '%s\n' '{"options":{},"apps":{"foot":{"chrome":false}}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

open_window foot

key super+alt+left
sleep 0.4
read -r _ y1 w1 _ _ <<<"$(win_geom foot)"
key super+alt+left
sleep 0.4
read -r _ y2 w2 _ _ <<<"$(win_geom foot)"
key super+alt+left
sleep 0.4
read -r _ y3 w3 _ _ <<<"$(win_geom foot)"

assert_ge "$y1" 24 "the window stays below the bar"
assert_eq "$y2" "$y1" "a second press must not creep down by the chrome height"
assert_eq "$y3" "$y1" "a third press holds the same top"
assert_ge "$w2" "$w1" "the cycle still widens on the second press"
assert_le "$w3" "$w1" "and narrows on the third"
