#!/usr/bin/env bash
# Alt+Tab is the focused app's own ring: the tabs of its group in tab order, and
# then the app's other floating windows. A Wayland dialog is refused a tab
# (hyprbars.groupable sees its xdg parent) and has no peer to group with, so it
# is a second window of the same class -- the shape of Geary's Accounts window.
# Another app's window is never in the ring, even when it is the most recently
# used one.
#
# The order is by real use, and the focus the ring itself makes does not count
# as a use: the ring has to keep still while it is walked, or Alt+Shift+Tab
# could not be the way back.
. "$(dirname "$0")/../../lib.sh"

# Both windows share a class, so the title says which of the two is active.
addr_of() { # TITLE
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['title'] == '$1':
        print(c['address'])
        break"
}

open_xdgchild xmode-app xmode-app
parent_addr="$(addr_of 'x-mode dialog parent')"
child_addr="$(addr_of 'x-mode dialog child')"
assert_ne "$parent_addr" "" "the app's own window is there"
assert_ne "$child_addr" "" "and so is its dialog"

open_window foot
open_window foot 2
open_window kitty

# Start in the app, on its own window: the dialog was used after it, and kitty
# is the freshest window of all.
nest_ctl dispatch "hl.dsp.focus({ window = 'address:$parent_addr' })" >/dev/null
settle
assert_eq "$(active_address)" "$parent_addr" "the app's own window is focused"

key alt+tab
settle
assert_eq "$(active_address)" "$child_addr" "the next stop is the app's dialog"

key alt+tab
settle
assert_eq "$(active_address)" "$parent_addr" "the ring wraps inside the app, not to kitty"

key alt+shift+tab
settle
assert_eq "$(active_address)" "$child_addr" "Alt+Shift+Tab comes back the same way"
