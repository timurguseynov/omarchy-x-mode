#!/usr/bin/env bash
# The menu's last row quits the app: every window of its class is closed. Quit is
# the last row in every menu the dock builds, so it can be aimed at without
# knowing the rows above it.
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window foot
open_window kitty
dock_settle

read -r px py <<<"$(dock_icon_point 0)"
pointer_click "$px" "$py" right
settle

read -r rx ry <<<"$(dock_menu_row_point 0 5 "26 7 26 7 26 26")"
pointer_click "$rx" "$ry"
foot_gone() { [ "$(count_class foot)" = 0 ]; }
wait_until 3 foot_gone || true

assert_eq "$(count_class foot)" 0 "the quit row closes the app's windows (got $(count_class foot))"
assert_eq "$(count_class kitty)" 1 "the other app is left alone"

dock_stop
