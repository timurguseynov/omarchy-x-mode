#!/usr/bin/env bash
# Alt+Tab is the pack's own binding for the next tab of a group, and Alt+Shift+Tab
# goes back. Driving the keys covers the binding and the handler that has to keep
# the group focused while the tab changes.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window foot 2
open_window foot 3
assert_eq "$(group_size foot)" 3 "three windows share the group"

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
before="$(active_tab_index foot)"

key alt+tab
sleep 0.4
assert_ne "$(active_tab_index foot)" "$before" "Alt+Tab moves to another tab"
assert_eq "$(active_class)" foot "the group keeps the focus"

key alt+shift+tab
sleep 0.4
assert_eq "$(active_tab_index foot)" "$before" "Alt+Shift+Tab goes back"
assert_eq "$(group_size foot)" 3 "the group is intact"
