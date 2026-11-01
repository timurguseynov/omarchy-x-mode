#!/usr/bin/env bash
# The menu's Force Quit row ends the app: SIGKILL, for the window whose app
# stopped reading its close request (the dispatcher itself is pinned in
# tests/qml/tst_logic.qml -- both rows make the window disappear).
#
# Rows for one class with one window: New, separator, window, separator, Pin,
# Force Quit, Quit. Force Quit is above Quit on purpose: the last row is what a
# hurried click lands on, and that has to stay the one that asks nicely.
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window foot
open_window kitty
dock_settle

read -r px py <<<"$(dock_icon_point "$(dock_icon_index foot)")"
pointer_click "$px" "$py" right
settle

read -r kx ky <<<"$(dock_menu_row_point 0 5 "26 7 26 7 26 26 26")"
pointer_click "$kx" "$ky"
wait_until 5 '[ "$(count_class foot)" = 0 ]' || fail "Force Quit did not end the app (got $(count_class foot))"
assert_eq "$(count_class foot)" 0 "Force Quit ends the app"
assert_eq "$(count_class kitty)" 1 "the other app is left alone"

dock_stop
