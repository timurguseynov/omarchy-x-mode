#!/usr/bin/env bash
# Regression: after a snap the window flickered while the cursor stayed over it.
# The snap forced a client configure, so the client kept turning while the chrome
# was already in place. Nothing may move now that the pointer does nothing but
# sit there.
. "$(dirname "$0")/../../lib.sh"

open_window foot
snap foot left

read -r x1 y1 w1 h1 _ <<<"$(win_geom foot)"

pointer_move $((x1 + w1 / 2)) $((y1 + h1 / 2))
sleep 0.3
read -r x2 y2 w2 h2 _ <<<"$(win_geom foot)"
assert_eq "$x2" "$x1" "a still cursor must not move a snapped window"
assert_eq "$y2" "$y1" "a still cursor must not move a snapped window"
assert_eq "$w2" "$w1" "a still cursor must not resize a snapped window"
assert_eq "$h2" "$h1" "a still cursor must not resize a snapped window"

# Hovering the bar is not a drag either.
pointer_move 5 5
sleep 0.3
read -r x3 y3 w3 h3 _ <<<"$(win_geom foot)"
assert_eq "$x3" "$x1" "hovering the bar must not move a snapped window"
assert_eq "$y3" "$y1" "hovering the bar must not move a snapped window"
assert_eq "$w3" "$w1" "hovering the bar must not resize a snapped window"
assert_eq "$h3" "$h1" "hovering the bar must not resize a snapped window"
