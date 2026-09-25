#!/usr/bin/env bash
# Regression: a right-click on the titlebar started the move drag, and the drag
# session only ended on the left button (272), so the window stuck to the cursor
# until the left button was clicked. RMB must do nothing here.
. "$(dirname "$0")/../../lib.sh"

open_window foot
read -r x0 y0 _ _ _ <<<"$(win_geom foot)"
read -r tx ty <<<"$(titlebar_point foot)"

pointer_drag "$tx" "$ty" "$((tx - 60))" "$((ty + 60))" right

read -r x1 y1 _ _ _ <<<"$(win_geom foot)"
assert_eq "$x1" "$x0" "a right-button drag must not move the window"
assert_eq "$y1" "$y0" "a right-button drag must not move the window"

# The left button still drags: without this the test would pass on a broken tool.
read -r tx2 ty2 <<<"$(titlebar_point foot)"
pointer_drag "$tx2" "$ty2" "$((tx2 - 60))" "$((ty2 + 60))" left

read -r x2 y2 _ _ _ <<<"$(win_geom foot)"
assert_le "$x2" $((x0 - 30)) "a left-button drag still moves the window"
assert_ge "$y2" $((y0 + 30)) "a left-button drag still moves the window"
