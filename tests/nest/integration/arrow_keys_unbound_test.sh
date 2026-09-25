#!/usr/bin/env bash
# Cmd+arrows are Omarchy's directional focus. x-mode drops them so the keys
# reach the app. The nest plants those four binds before the pack loads;
# afterwards none may remain, and pressing one must not move focus.
. "$(dirname "$0")/../../lib.sh"

for arrow in LEFT RIGHT UP DOWN; do
  assert_eq "$(bind_count "$arrow" 64)" 0 "Super+$arrow must not be bound"
done

open_window foot
open_window kitty
place_frac foot 4 30 35 35
place_frac kitty 58 30 35 35

nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
assert_eq "$(active_class)" kitty "kitty is focused to begin with"

# One at a time: Left then Right would walk away and back, and a final check
# would miss a bind that is still there.
for combo in super+left super+right super+up super+down; do
  key "$combo"
  sleep 0.3
  assert_eq "$(active_class)" kitty "$combo leaves the focused window alone"
done
