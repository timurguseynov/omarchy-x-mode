#!/usr/bin/env bash
# Super+Tab cycles apps like the macOS switcher, most recently used first. The
# overlay itself is drawn by the shell and only lives while the keys are held, so
# what a test can see is what the switcher does: the focus lands on the next app,
# and the next press comes back.
#
# The pack also writes a command file for the overlay in the runtime directory;
# that it is written is checked here as the sign that this ran the switcher and
# not some other focus path.
. "$(dirname "$0")/../../lib.sh"

rm -f "$NEST_RUNTIME/omarchy-switcher.cmd"

open_window foot
open_window kitty
nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
before="$(active_class)"
assert_ne "$before" "" "something is focused to begin with"

key super+tab
sleep 0.5
assert_ne "$(active_class)" "$before" "Super+Tab moves to the next app"

key super+tab
sleep 0.5
assert_eq "$(active_class)" "$before" "and the next press comes back"

assert_ge "$(wc -c < "$NEST_RUNTIME/omarchy-switcher.cmd")" 1 \
  "the switcher's command file was written"
