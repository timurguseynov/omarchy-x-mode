#!/usr/bin/env bash
# Dragging by the titlebar picks a snap zone from where the cursor is let go:
# the side strips give halves, the top strip maximizes, the corner squares give
# quarters, and the middle gives nothing. This drives the real gesture, not the
# snap function, so it covers zoneAtCursor() as well.
#
# The strips are px, not fractions: margin 12, corner 20, and a top band of the
# reserved height plus 8. So a target 5px from an edge is inside the strip at any
# monitor size, and the middle of a side is far from both corners.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"
mh="${extent#*x}"
mid_y=$((mh / 2))
mid_x=$((mw / 2))

open_window foot

drag_to foot 5 "$mid_y"
read -r x _ w _ _ <<<"$(win_geom foot)"
assert_le "$x" 20 "the left strip snaps to the left half"
assert_le "$w" $((mw * 6 / 10)) "the left strip gives a half, not the full width"

read -r tx ty <<<"$(titlebar_point foot)"
pointer_drag "$tx" "$ty" "$((mw - 5))" "$mid_y"
sleep 0.3
read -r x _ w _ _ <<<"$(win_geom foot)"
# Not mw/2: the right half stops short of the dock inset, so it starts left of
# the midpoint. What tells it from the left half is that it sits on the right.
assert_ge "$x" $((mw / 3)) "the right strip snaps to the right half"
assert_le "$w" $((mw * 6 / 10)) "the right strip gives a half, not the full width"

read -r tx ty <<<"$(titlebar_point foot)"
pointer_drag "$tx" "$ty" "$mid_x" 10
sleep 0.3
read -r _ _ w _ _ <<<"$(win_geom foot)"
assert_ge "$w" $((mw * 8 / 10)) "the top strip maximizes"

read -r tx ty <<<"$(titlebar_point foot)"
pointer_drag "$tx" "$ty" 5 5
sleep 0.3
read -r x _ w h _ <<<"$(win_geom foot)"
assert_le "$x" 20 "the top-left corner snaps to the left"
assert_le "$w" $((mw * 6 / 10)) "a corner gives a quarter, not the full width"
assert_le "$h" $((mh * 6 / 10)) "a corner gives a quarter, not the full height"

# Let go in the middle: no zone, so the window stays where it was dropped.
read -r tx ty <<<"$(titlebar_point foot)"
pointer_drag "$tx" "$ty" "$mid_x" "$mid_y"
sleep 0.3
read -r x1 y1 _ _ _ <<<"$(win_geom foot)"

read -r tx ty <<<"$(titlebar_point foot)"
pointer_drag "$tx" "$ty" "$((mid_x + 20))" "$((mid_y + 20))"
sleep 0.3
read -r x2 y2 _ _ _ <<<"$(win_geom foot)"
assert_ge "$x2" "$x1" "letting go in the middle leaves the window where it was dropped"
assert_ge "$y2" "$y1" "letting go in the middle leaves the window where it was dropped"
