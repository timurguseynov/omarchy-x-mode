#!/usr/bin/env bash
# Switching tabs with Alt+Tab must leave the window geometry alone. The hidden
# member used to report desiredExtents 0, so the group's box was recomputed for a
# frame and the client got a configure with another height (the status bar blink
# seen in zed). The same invariant is checked through the dispatcher elsewhere;
# this is the key the user presses.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window foot 2
open_window foot 3
assert_eq "$(group_size foot)" 3 "three windows share the group"

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3

read -r x1 y1 w1 h1 _ <<<"$(visible_geom foot)"
key alt+tab
sleep 0.4
read -r x2 y2 w2 h2 _ <<<"$(visible_geom foot)"

assert_eq "$x2" "$x1" "x must not change on the key"
assert_eq "$y2" "$y1" "y must not change on the key"
assert_eq "$w2" "$w1" "width must not change on the key"
assert_eq "$h2" "$h1" "height must not change on the key"
