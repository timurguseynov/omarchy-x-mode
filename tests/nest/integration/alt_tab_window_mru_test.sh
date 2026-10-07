#!/usr/bin/env bash
# Alt+Tab walks the tabs of the focused group, and once the group's tabs are
# done it goes on to the next window of the workspace in the switcher's MRU
# order. A window the pack refuses to tab -- Geary's Accounts dialog, a lone
# app -- is in the same ring as the tabs, so Alt+Tab reaches it; from a window
# with no group (or from the group's last tab) the old handler did nothing at
# all.
#
# The order is by real use: foot (two tabs) was used last, kitty before it.
# Alt+Tab goes tab 1 -> tab 2 -> kitty, and Alt+Shift+Tab comes back the same
# way -- the ring must not move under the key while it is walked.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window foot 2
assert_eq "$(group_size foot)" 2 "two foot windows share the group"
open_window kitty

# group.active only moves the tab when the group holds the focus, so put the
# focus in the group first (kitty was opened last and still has it).
nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
group_tab 1 foot
assert_eq "$(active_class)" foot "foot is focused"
assert_eq "$(active_tab_index foot)" 0 "on its first tab"

key alt+tab
settle
assert_eq "$(active_class)" foot "Alt+Tab keeps the group focused"
assert_eq "$(active_tab_index foot)" 1 "and moves tab by tab"

key alt+tab
settle
assert_eq "$(active_class)" kitty "after the group's last tab comes the next window by MRU"

key alt+shift+tab
settle
assert_eq "$(active_class)" foot "Alt+Shift+Tab comes back to the group"
assert_eq "$(active_tab_index foot)" 1 "on the tab it left"

key alt+shift+tab
settle
assert_eq "$(active_class)" foot "one more step back"
assert_eq "$(active_tab_index foot)" 0 "is the previous tab"

key alt+tab
settle
assert_eq "$(active_class)" foot "and Alt+Tab goes on around the tabs"
assert_eq "$(active_tab_index foot)" 1 "to the next one"
