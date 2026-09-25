#!/usr/bin/env bash
# The switcher lists apps most recently used first, like the macOS one. After
# focusing foot by hand the history is foot, zenity, kitty, so the next Super+Tab
# goes to zenity — not to kitty, which is what name or open order would give. That
# is what makes this a test of the MRU order rather than of "some other window".
#
# The keys are pressed and released, and the list is rebuilt on the next first
# press, so every press goes to the app used before the current one: with the
# history above, the presses alternate between zenity and foot.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window kitty
open_command zenity zenity --info --text=xmode-test

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.4
assert_eq "$(active_class)" foot "foot is focused by hand"

key super+tab
sleep 0.5
assert_eq "$(active_class)" zenity "the next app is the one used before foot"

key super+tab
sleep 0.5
assert_eq "$(active_class)" foot "and the one used before that is foot itself"

key super+tab
sleep 0.5
assert_eq "$(active_class)" zenity "so the presses alternate"
