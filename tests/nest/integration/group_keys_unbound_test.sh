#!/usr/bin/env bash
# Cmd+G toggles a Hyprland group and Cmd+Alt+G pulls a window out of one.
# x-mode drops both so the keys reach the app. The nest plants those binds
# before the pack loads; afterwards neither may remain, and pressing them
# must not group a window.
. "$(dirname "$0")/../../lib.sh"

# By description, not by key: the Super-as-Ctrl plan binds free keys as Ctrl+key,
# and `Super+G` can legitimately carry one of those while the thing this checks --
# Omarchy's grouping bind -- is gone.
assert_eq "$(bind_count_desc 'Toggle window grouping' 64)" 0 "Super+G no longer toggles a group"
assert_eq "$(bind_count_desc 'Move active window out of group' 72)" 0 "Super+Alt+G no longer moves a window out of a group"

open_window foot
assert_eq "$(group_size foot)" 0 "foot starts ungrouped"

key super+g
sleep 0.3
assert_eq "$(group_size foot)" 0 "Super+G does not group the window"

key super+alt+g
sleep 0.3
assert_eq "$(group_size foot)" 0 "Super+Alt+G does not group the window"
