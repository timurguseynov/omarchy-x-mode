#!/usr/bin/env bash
# A snapped window dragged a little down by its titlebar has to stay where it was
# dropped when another window takes focus. It used to jump back into its snap:
# the drag writes the box on the layout target, and the next focus change put the
# target back to the position the snap had written.
#
# The snap is made with the plugin (snap foot left) rather than a key, so this is
# only about the drop and the focus change, not about the cycle.
. "$(dirname "$0")/../../lib.sh"

open_window foot
# Let the open watch stop: this is only about the drag and the focus change.
sleep 2.2

snap foot left
read -r x0 y0 _ _ _ <<<"$(win_geom foot)"

# Grab the titlebar and drop it 60px lower, same column.
read -r tx ty <<<"$(titlebar_point foot)"
pointer_drag "$tx" "$ty" "$tx" "$((ty + 60))"
sleep 0.4
read -r x1 y1 _ _ _ <<<"$(win_geom foot)"
assert_eq "$x1" "$x0" "the drag keeps the column"
assert_ge "$y1" "$((y0 + 40))" "the drag lands the window lower"

# A second program takes focus.
open_window kitty
sleep 0.6
read -r x2 y2 _ _ _ <<<"$(win_geom foot)"
assert_eq "$x2" "$x1" "focusing another window keeps the dragged column"
assert_eq "$y2" "$y1" "focusing another window keeps the dragged drop"

# And a click on that program, for the other way focus moves.
read -r kx ky kw kh _ <<<"$(win_geom kitty)"
pointer_click "$((kx + kw / 2))" "$((ky + kh / 2))"
sleep 0.4
read -r x3 y3 _ _ _ <<<"$(win_geom foot)"
assert_eq "$x3" "$x1" "clicking another window keeps the dragged column"
assert_eq "$y3" "$y1" "clicking another window keeps the dragged drop"
