#!/usr/bin/env bash
# The No gaps toggle: the panel writes settings.json and reloads. The gaps go to
# zero and the windows sitting in a snap zone are re-snapped wider.
. "$(dirname "$0")/../lib.sh"

SETTINGS="$NEST_SETTINGS"

open_window foot
snap foot left
read -r _ _ before_w _ _ <<<"$(win_geom foot)"
# The desktop's own gaps, from the config this session started with: the test is
# that they come back, not that they are any particular number.
base_out="$(gaps_out)"

# The pack owns the gaps now, so Omarchy's own toggle is retired: its key is not
# bound at all, and the panel's row is the switch. The nest plants that bind, so
# this is about the pack taking it away. The second assertion is the sanity check
# that the bind table is readable, without which the first proves nothing.
assert_eq "$(bind_count_desc 'Toggle window gaps' 65)" 0 "Omarchy's gaps toggle is not bound"
assert_eq "$(bind_count 3 65)" 1 "and the pack's own binds are there (Cmd+Shift+3)"

printf '%s\n' '{"options":{"nativeScroll":false,"ctrlTabSwitch":false,"noGaps":true},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

assert_eq "$(gaps_out)" 0 "gaps_out is zero while No gaps is on"
read -r _ y w _ _ <<<"$(win_geom foot)"
assert_ne "$w" "$before_w" "the snapped window re-laid out"
assert_ge "$y" 25 "still below the bar"

printf '%s\n' '{"options":{},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
wait_until 5 '[ "$(gaps_out)" = "$base_out" ]' || fail "turning No gaps off left gaps_out at $(gaps_out), not the desktop's $base_out"
assert_eq "$(gaps_out)" "$base_out" "turning No gaps off gives the desktop's gaps back"

# And the same for the whole desktop: the gaps are an x-mode setting, so switching
# x-mode off has to leave the tiling desktop with its own gaps.
printf '%s\n' '{"options":{"noGaps":true},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
wait_until 5 '[ "$(gaps_out)" = 0 ]' || fail "No gaps did not come back on for the off test"
printf '%s\n' 'off' > "$NEST_STATE/state/enabled"
nest_ctl reload >/dev/null
wait_until 5 '[ "$(gaps_out)" = "$base_out" ]' || fail "x-mode off left gaps_out at $(gaps_out), not the desktop's $base_out"
assert_eq "$(gaps_out)" "$base_out" "switching x-mode off gives the tiling desktop its gaps back"
rm -f "$NEST_STATE/state/enabled"
