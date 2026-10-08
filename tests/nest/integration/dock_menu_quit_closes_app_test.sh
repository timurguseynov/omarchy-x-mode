#!/usr/bin/env bash
# The menu's last row quits the app: every window of its class is closed. Quit is
# the last row in every menu the dock builds, so it can be aimed at without
# knowing the rows above it.
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window foot
open_window kitty
dock_settle

dock_menu_open 0

read -r rx ry <<<"$(dock_menu_row_point 0 5 "26 7 26 7 26 26")"
dock_menu_click "$rx" "$ry"
# The quit dispatch is itself a hyprctl. A tight poll fills the nest's socket
# and the close sits behind it until this wait gives up.
foot_gone() { [ "$(count_class foot)" = 0 ]; }
for _ in $(seq 1 12); do
  foot_gone && break
  sleep 0.25
done

assert_eq "$(count_class foot)" 0 "the quit row closes the app's windows (got $(count_class foot))"
assert_eq "$(count_class kitty)" 1 "the other app is left alone"

dock_stop
