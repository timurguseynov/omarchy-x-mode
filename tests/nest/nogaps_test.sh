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

# The pack owns the gaps on its own workspaces -- the panel's row is the switch --
# but every other mode is Omarchy's, and there the key is her gaps toggle. So the
# bind exists exactly once (no duplicate left behind), and on an xmode workspace a
# press changes nothing.
# Two spellings, the way the pack binds it: Omarchy may write the key by name or by
# keycode, and both have to end up doing the same thing per mode.
assert_eq "$(bind_count_desc 'Toggle window gaps' 65)" 2 "the gaps key is bound, both spellings"
assert_eq "$(bind_count 3 65)" 1 "and the pack's own binds are there (Cmd+Shift+3)"
key super+shift+backspace
sleep 0.4
assert_eq "$(gaps_out)" "$base_out" "on an xmode workspace the gaps key leaves the gaps alone"

printf '%s\n' '{"options":{"nativeScroll":false,"ctrlTabSwitch":false,"noGaps":true},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

assert_eq "$(gaps_out)" "$base_out" "no gaps leaves the desktop gaps alone"
read -r _ y w _ _ <<<"$(win_geom foot)"
assert_ne "$w" "$before_w" "the snapped window re-laid out"
assert_ge "$y" 25 "still below the bar"

printf '%s\n' '{"options":{},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
wait_until 5 '[ "$(gaps_out)" = "$base_out" ]' || fail "turning No gaps off left gaps_out at $(gaps_out), not the desktop's $base_out"
assert_eq "$(gaps_out)" "$base_out" "turning No gaps off gives the desktop's gaps back"

# The gaps are an xmode setting, so they are never taken off the desktop.
# Switching the pack off has to leave the tiling desktop with its own gaps.
printf '%s\n' '{"options":{"noGaps":true},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
wait_until 5 '[ "$(gaps_out)" = "$base_out" ]' || fail "No gaps changed the desktop gaps to $(gaps_out), not $base_out"
printf '%s\n' 'off' > "$NEST_STATE/state/enabled"
nest_ctl reload >/dev/null
wait_until 5 '[ "$(gaps_out)" = "$base_out" ]' || fail "x-mode off left gaps_out at $(gaps_out), not the desktop's $base_out"
assert_eq "$(gaps_out)" "$base_out" "switching x-mode off gives the tiling desktop its gaps back"
rm -f "$NEST_STATE/state/enabled"
