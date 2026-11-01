#!/usr/bin/env bash
# Clicking a dock icon focuses and raises that app. The dock lists one icon per
# class, pinned first and the running ones in launch order, so the icon for kitty
# is the one after foot (kitty is opened second).
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window foot
open_window kitty
dock_settle

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
assert_eq "$(active_class)" foot "foot is focused to begin with"

read -r px py <<<"$(dock_icon_point 1)"
pointer_click "$px" "$py"
# Wait for the thing, not for a fixed pause: under five nests the dock's dispatch
# can take longer than a settle, and asserting on the pause reported a lost click
# that had only not landed yet.
wait_until 5 '[ "$(active_class)" = kitty ]' || fail "clicking an icon did not focus that app (got $(active_class))"
assert_eq "$(active_class)" kitty "clicking an icon focuses that app"
assert_eq "$(topmost)" kitty "clicking an icon raises that app"

dock_stop
