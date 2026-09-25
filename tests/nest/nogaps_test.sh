#!/usr/bin/env bash
# The No gaps toggle: the panel writes settings.json and reloads. The gaps go to
# zero and the windows sitting in a snap zone are re-snapped wider.
. "$(dirname "$0")/../lib.sh"

SETTINGS="$NEST_STATE/state/settings.json"

open_window foot
snap foot left
read -r _ _ before_w _ _ <<<"$(win_geom foot)"

printf '%s\n' '{"options":{"nativeScroll":false,"ctrlTabSwitch":false,"noGaps":true},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

assert_eq "$(gaps_out)" 0 "gaps_out is zero while No gaps is on"
read -r _ y w _ _ <<<"$(win_geom foot)"
assert_ne "$w" "$before_w" "the snapped window re-laid out"
assert_ge "$y" 25 "still below the bar"

printf '%s\n' '{"options":{},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6
