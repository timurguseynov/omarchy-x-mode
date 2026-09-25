#!/usr/bin/env bash
# A window snapped to a zone can be dragged out of it: dropped where there is no
# zone it stays where the pointer left it, with the size it already had. The drop
# lands in the middle of the screen, away from the edge strips and corner squares.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"
mh="${extent#*x}"

open_window foot
snap foot left

read -r x1 _ w1 h1 _ <<<"$(win_geom foot)"

drag_to foot $((mw / 2)) $((mh / 3))

read -r x2 _ w2 h2 _ <<<"$(win_geom foot)"
assert_ne "$x2" "$x1" "dragging a snapped window out of its zone moves it"
assert_eq "$w2" "$w1" "the window keeps its width when it leaves the zone"
assert_eq "$h2" "$h1" "the window keeps its height when it leaves the zone"
assert_ge "$(visual_top foot)" "$(bar_top)" "it still clears the bar"
