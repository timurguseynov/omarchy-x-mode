#!/usr/bin/env bash
# A window row for a window on another workspace moves there and focuses it.
# Rows for an app with one window: New, separator, the window, separator, Pin,
# Quit, so the window is row 2.
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window kitty
open_window foot
dock_settle

nest_ctl dispatch "hl.dsp.window.move({ workspace = \"2\", window = 'class:foot' })" >/dev/null
sleep 0.3
nest_ctl dispatch "hl.dsp.focus({ workspace = \"1\" })" >/dev/null
sleep 0.3
assert_eq "$(viewed_workspace)" 1 "the test starts on workspace 1"

# foot sorts before kitty, so its icon is the first one.
read -r px py <<<"$(dock_icon_point 0)"
pointer_click "$px" "$py" right
sleep 0.6

read -r rx ry <<<"$(dock_menu_row_point 0 2 "26 7 26 7 26 26")"
pointer_click "$rx" "$ry"
sleep 0.8

assert_eq "$(viewed_workspace)" 2 "the window row moves to that window's workspace"
assert_eq "$(active_class)" foot "the window row focuses that window"

dock_stop
