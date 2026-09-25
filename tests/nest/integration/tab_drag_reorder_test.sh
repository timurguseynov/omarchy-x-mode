#!/usr/bin/env bash
# Dragging a tab sideways reorders the group. The tabbar splits its width evenly,
# so tab 0 and tab 2 are two slots apart; the group must keep all of its windows
# and its box.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window foot 2
open_window foot 3
assert_eq "$(group_size foot)" 3 "three windows share the group"

before="$(group_order foot)"
read -r x1 y1 _ _ _ <<<"$(visible_geom foot)"

read -r fx fy <<<"$(tab_point foot 0 3)"
read -r tx ty <<<"$(tab_point foot 2 3)"
pointer_drag "$fx" "$fy" "$tx" "$ty"
sleep 0.5

after="$(group_order foot)"
assert_ne "$after" "$before" "dragging a tab rewrites the order"
assert_eq "$(wc -w <<<"$after")" 3 "the group keeps all three windows"
read -r x2 y2 _ _ _ <<<"$(visible_geom foot)"
assert_eq "$x2" "$x1" "reordering a tab must not move the group"
assert_eq "$y2" "$y1" "reordering a tab must not move the group"
