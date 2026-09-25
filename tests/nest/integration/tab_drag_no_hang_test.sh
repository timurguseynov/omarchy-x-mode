#!/usr/bin/env bash
# Regression: dragging a tab in a group froze the whole compositor, because the
# raise ran inside the window.active handler. After a tab drag the compositor has
# to still answer, the group has to keep its windows, and the z-order has to be
# sane (the topmost window is one of the group's).
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window foot 2
open_window foot 3
assert_eq "$(group_size foot)" 3 "three windows share the group"

read -r fx fy <<<"$(tab_point foot 0 3)"
read -r tx ty <<<"$(tab_point foot 2 3)"
pointer_drag "$fx" "$fy" "$tx" "$ty"
sleep 0.5

assert_eq "$(group_size foot)" 3 "the group survives the drag"
assert_eq "$(topmost)" foot "the compositor is alive: z-order is still readable"

# A second drag on the group, to catch a session left in a bad state.
read -r fx fy <<<"$(tab_point foot 0 3)"
read -r tx ty <<<"$(tab_point foot 2 3)"
pointer_drag "$fx" "$fy" "$tx" "$ty"
sleep 0.5
assert_eq "$(group_size foot)" 3 "a second drag leaves the group intact"
