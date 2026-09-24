#!/usr/bin/env bash
# The pointer injects real input, so a titlebar drag must move the window the
# way a mouse does: through hyprbars' drag session, not through a direct call to
# the pack's snap function.
#
# This also guards the tool itself. If zwlr_virtual_pointer_manager_v1 is gone,
# or a warp stops reaching input.mouse.move, the window simply does not move and
# every scenario built on the pointer would fail for the wrong reason.
. "$(dirname "$0")/../lib.sh"

open_window foot

read -r x0 y0 w0 h0 _ <<<"$(win_geom foot)"
read -r tx ty <<<"$(titlebar_point foot)"

# Down and to the left, away from the screen edges: a snap zone starts only
# within x_mode_snap margin of an edge, and a snap would change the size.
pointer_drag "$tx" "$ty" "$((tx - 60))" "$((ty + 60))"

read -r x1 y1 w1 h1 _ <<<"$(win_geom foot)"

assert_eq "$w1" "$w0" "a titlebar drag must not resize the window"
assert_eq "$h1" "$h0" "a titlebar drag must not resize the window"
assert_le "$x1" $((x0 - 30)) "the window follows the pointer to the left"
assert_ge "$y1" $((y0 + 30)) "the window follows the pointer down"

# A click that never crosses the drag threshold is a click: the window stays put.
read -r tx2 ty2 <<<"$(titlebar_point foot)"
pointer_click "$tx2" "$ty2"
read -r x2 y2 _ _ _ <<<"$(win_geom foot)"
assert_eq "$x2" "$x1" "a titlebar click must not move the window"
assert_eq "$y2" "$y1" "a titlebar click must not move the window"
