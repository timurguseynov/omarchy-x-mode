#!/usr/bin/env bash
# The panel's "Show dock" row writes options.dock in the settings file, which
# both halves obey: the dock reads it off the file and hides its layer, and the
# pack stops insetting the right snap zones by the card. The option arrived
# after the dock, so absent means on -- a file that never mentions it keeps its
# dock, and only an explicit false takes it away.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"

dock_inset() {
  nest_ctl getoption plugin:hyprbars:x_mode_dock_inset | head -1 | awk '{print $2}'
}

show_dock() { # VALUE
  printf '{"options":{"dock":%s},"apps":{}}\n' "$1" > "$SETTINGS"
  nest_ctl reload >/dev/null
}

dock_start
dock_settle
card="$(dock_box 2>/dev/null | awk '{print $3}')"
assert_ge "${card:-0}" 1 "the dock is there with the option on"
gap="$(gaps_out)"
assert_eq "$(dock_inset)" "$((card + gap / 2))" "the inset counts the card while the dock shows"

# Off: the layer goes with the shell still running, and the card stops counting.
show_dock false
wait_until 5 '[ -z "$(dock_box 2>/dev/null || true)" ]' || fail "show dock off hides the layer without restarting the shell"
assert_eq "$(dock_box 2>/dev/null || echo none)" none "show dock off hides the layer"
want_zero=$((gap / 2))
wait_until 5 "[ \"\$(dock_inset)\" = \"$want_zero\" ]" || fail "the inset drops the card when the dock is off (got $(dock_inset))"
assert_eq "$(dock_inset)" "$want_zero" "the inset drops the card when the dock is off"

# On again: the layer returns, and the card counts for the inset once more. The
# width is read off the layer that just came back, so this also covers the pack
# refreshing the card for a dock that remaps rather than only at load.
show_dock true
wait_until 5 '[ -n "$(dock_box 2>/dev/null || true)" ]' || fail "show dock on brings the layer back"
assert_ne "$(dock_box 2>/dev/null || echo none)" none "show dock on brings the layer back"
card_again="$(dock_box 2>/dev/null | awk '{print $3}')"
want_back=$((card_again + gap / 2))
wait_until 5 "[ \"\$(dock_inset)\" = \"$want_back\" ]" || fail "the inset counts the card again (got $(dock_inset))"
assert_eq "$(dock_inset)" "$want_back" "the inset counts the card again"

dock_stop