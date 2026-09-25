#!/usr/bin/env bash
# The switcher lists apps most recently used first, like the macOS one. After
# focusing foot by hand the history is foot, xmode-extra, kitty, so the next
# Super+Tab goes to xmode-extra — not to kitty, which is what name or open order
# would give. That is what makes this a test of the MRU order rather than of "some
# other window".
#
# The keys are pressed and released, and the list is rebuilt on the next first
# press, so every press goes to the app used before the current one: with the
# history above, the presses alternate between xmode-extra and foot.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window kitty
# A third app with its own class, and not a dialog: `--app-id` is what Hyprland
# reads as the class. A zenity dialog would work too but puts a modal-looking
# "Information" window on screen for the whole run.
open_command xmode-extra foot --app-id=xmode-extra

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.4
assert_eq "$(active_class)" foot "foot is focused by hand"

key super+tab
sleep 0.5
assert_eq "$(active_class)" xmode-extra "the next app is the one used before foot"

key super+tab
sleep 0.5
assert_eq "$(active_class)" foot "and the one used before that is foot itself"

key super+tab
sleep 0.5
assert_eq "$(active_class)" xmode-extra "so the presses alternate"
