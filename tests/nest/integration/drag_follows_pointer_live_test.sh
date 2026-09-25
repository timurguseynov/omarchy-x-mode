#!/usr/bin/env bash
# During a titlebar drag the window has to follow the pointer and keep its size:
# the move is compositor-only, so the client must not be reconfigured on every
# step of the gesture.
#
# Driven through one `pointer hold` session, because the geometry has to be read
# while the button is still down, and a process per command would drop the button
# when it exited.
#
# The first motion after the press only crosses the drag threshold, so the
# window starts moving on the second one; the test moves twice before reading.
. "$(dirname "$0")/../../lib.sh"

open_window foot

read -r x0 y0 w0 h0 _ <<<"$(win_geom foot)"
read -r tx ty <<<"$(titlebar_point foot)"

pointer_begin
pointer_do "move $tx $ty"
pointer_do "press left"
pointer_do "move $((tx + 30)) $((ty + 30))"
pointer_do "move $((tx + 60)) $((ty + 60))"
sleep 0.3

read -r x1 y1 w1 h1 _ <<<"$(win_geom foot)"
assert_ge "$x1" $((x0 + 20)) "the window follows the pointer while the button is held"
assert_ge "$y1" $((y0 + 20)) "the window follows the pointer while the button is held"
assert_eq "$w1" "$w0" "the client must not be reconfigured mid-drag"
assert_eq "$h1" "$h0" "the client must not be reconfigured mid-drag"

pointer_do "move $((tx + 100)) $((ty + 100))"
sleep 0.3
read -r x2 y2 _ _ _ <<<"$(win_geom foot)"
assert_ge "$x2" "$x1" "the window keeps following the pointer"
assert_ge "$y2" "$y1" "the window keeps following the pointer"

pointer_do "release left"
pointer_end
sleep 0.3
