#!/usr/bin/env bash
# Regression: clicking the icon of the app that is already focused on the
# workspace being viewed retargeted a group member, which switched tabs. The
# click has to be a no-op for a group the user is already looking at.
. "$(dirname "$0")/../../lib.sh"

dock_start
open_window foot
open_window foot 2
dock_settle
assert_eq "$(group_size foot)" 2 "two windows share the group"

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
before="$(active_tab_index foot)"

read -r px py <<<"$(dock_icon_point 0)"
pointer_click "$px" "$py"
sleep 0.5

assert_eq "$(active_tab_index foot)" "$before" "clicking the focused app's icon must not switch tabs"
assert_eq "$(active_class)" foot "the group stays focused"

dock_stop
