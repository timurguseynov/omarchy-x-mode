#!/usr/bin/env bash
# Cmd+G toggles a Hyprland group and Cmd+Alt+G pulls a window out of one.
# x-mode drops both so the keys reach the app. The nest plants those binds
# before the pack loads; afterwards neither may remain, and pressing them
# must not group a window.
. "$(dirname "$0")/../../lib.sh"

assert_eq "$(bind_count G 64)" 0 "Super+G must not be bound"
assert_eq "$(bind_count G 72)" 0 "Super+Alt+G must not be bound"

open_window foot
assert_eq "$(group_size foot)" 0 "foot starts ungrouped"

key super+g
sleep 0.3
assert_eq "$(group_size foot)" 0 "Super+G does not group the window"

key super+alt+g
sleep 0.3
assert_eq "$(group_size foot)" 0 "Super+Alt+G does not group the window"
