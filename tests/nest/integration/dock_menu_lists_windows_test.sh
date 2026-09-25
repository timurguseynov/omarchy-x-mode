#!/usr/bin/env bash
# The menu lists every window of the app, not just one per workspace, and a click
# on a row focuses that window. With two windows of one class in a group, the
# rows are the windows sorted by focus, so the row after the current one is the
# other tab.
#
# Rows: New, separator, the two windows, separator, Pin, Quit.
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window foot
open_window foot 2
dock_settle
assert_eq "$(group_size foot)" 2 "two windows share the group"

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3

current="$(active_address)"
order="$(group_order foot)"
other=""
for a in $order; do
  [ "$a" != "$current" ] && other="$a"
done
assert_ne "$other" "" "there is another window of the app"

read -r px py <<<"$(dock_icon_point 0)"
pointer_click "$px" "$py" right
sleep 0.6

read -r rx ry <<<"$(dock_menu_row_point 0 3 "26 7 26 26 7 26 26")"
pointer_click "$rx" "$ry"
sleep 0.6

assert_eq "$(active_address)" "$other" "the window row focuses that window"

dock_stop
