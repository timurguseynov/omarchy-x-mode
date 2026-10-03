#!/usr/bin/env bash
# Cmd+arrows were Omarchy's directional focus. x-mode drops that, and the keys
# are the pack's macOS text chords now (Cmd+Left is the start of the line), so
# Super-as-Ctrl must not also claim them: one press would then run both. The
# nest plants Omarchy's four binds before the pack loads; afterwards the pack's
# chord is the only bind on the key, and pressing one still must not move focus.
. "$(dirname "$0")/../../lib.sh"

expect_text_chord() { # KEY OLD_DESCRIPTION NEW_DESCRIPTION
  assert_eq "$(bind_count_desc_exact "$2" 64)" 0 "Super+$1 is no longer \"$2\""
  assert_eq "$(bind_count "$1" 64)" 1 "Super+$1 has exactly one bind"
  assert_eq "$(bind_count_desc_exact "$3" 64)" 1 "Super+$1 sends \"$3\""
  assert_eq "$(bind_count_desc_exact "x-mode-super-ctrl $1" 64)" 0 "Super+$1 is not also sent as Ctrl+$1"
}

expect_text_chord LEFT "Focus on left window" "Start of line"
expect_text_chord RIGHT "Focus on right window" "End of line"
expect_text_chord UP "Focus on above window" "Start of document"
expect_text_chord DOWN "Focus on below window" "End of document"

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
