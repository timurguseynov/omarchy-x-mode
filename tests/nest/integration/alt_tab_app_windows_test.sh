#!/usr/bin/env bash
# Alt+Tab is the next tab of a group. A window that is in no group -- the pack
# floats a dialog into its own window and refuses it a tab, and KeePassXC's
# access prompt is a second window of the class of the vault it asks about --
# left the key doing nothing at all, so the two windows of one app could not be
# reached with the keys (Cmd+Tab lists apps, and the app is already one entry).
# It steps to the app's next window on the workspace instead, and back.
#
# The shape is the dialog's: two toplevels of one class, the second one a child
# of the first, which Hyprland floats and hyprbars.groupable refuses a tab.
. "$(dirname "$0")/../../lib.sh"

open_xdgchild xmode-app xmode-app
wait_for_count xmode-app 2
settle

assert_eq "$(count_class xmode-app)" 2 "the app has two windows"
assert_le "$(group_size xmode-app)" 1 "and the dialog is not a tab of the other"

# Addresses rather than a class: both windows are the app's, and which one the
# xdgchild mapped first is not something this scenario should depend on.
read -r first second <<<"$(nest_ctl clients -j | python3 -c "
import json, sys
print(' '.join(c['address'] for c in json.load(sys.stdin)
               if c['class'] == 'xmode-app' and c['mapped'] and not c['hidden']))")"
[ -n "$first" ] && [ -n "$second" ] || fail "expected two xmode-app windows, saw '$first' '$second'"

nest_ctl dispatch "hl.dsp.focus({ window = 'address:$first' })" >/dev/null
sleep 0.3
assert_eq "$(active_address)" "$first" "the first window took the focus"

key alt+tab
sleep 0.4
assert_eq "$(active_address)" "$second" "Alt+Tab steps to the app's other window"
assert_eq "$(active_class)" xmode-app "and stays on the app"

key alt+shift+tab
sleep 0.4
assert_eq "$(active_address)" "$first" "Alt+Shift+Tab steps back"

# The group path is unchanged: a window that has tabs still cycles its tabs.
assert_le "$(group_size xmode-app)" 1 "stepping the app's windows makes no tab"
