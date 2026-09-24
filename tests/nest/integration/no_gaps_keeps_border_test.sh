#!/usr/bin/env bash
# Regression: turning No gaps on zeroed general:border_size, so windows merged
# into one another with no hairline left. The panel's toggle writes
# settings.json and reloads, which is the path a user takes.
#
# nogaps_test.sh covers the re-snap and gaps_out; this covers the border. The
# exact inset is left to the geometry layer (unit), so this only asserts the
# window actually moved toward the edge.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_STATE/state/settings.json"

open_window foot
snap foot left

read -r bx _ _ _ _ <<<"$(win_geom foot)"
base_gaps="$(gaps_out)"
assert_ge "$base_gaps" 1 "gaps are on to begin with"
assert_ge "$bx" 1 "a snapped window is inset from the left edge"

printf '%s\n' '{"options":{"noGaps":true},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

assert_eq "$(gaps_out)" 0 "no gaps zeroes gaps_out"
assert_eq "$(border_size)" 1 "no gaps keeps a 1px border so windows stay separable"
read -r nx _ _ _ _ <<<"$(win_geom foot)"
assert_le "$nx" "$bx" "the snapped window moves toward the edge"
# Not the gaps-on 36 from snap_test.sh: with no gaps the inset is just the 1px
# border, so the titlebar sits right under the bar. The contract is that it must
# not climb above where the bar ends.
assert_ge "$(visual_top foot)" "$(bar_top)" "the titlebar stays below the bar without gaps"

printf '%s\n' '{"options":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

assert_ge "$(gaps_out)" 1 "turning gaps back on restores gaps_out"
assert_eq "$(border_size)" 2 "turning gaps back on restores the border"
read -r rx _ _ _ _ <<<"$(win_geom foot)"
assert_eq "$rx" "$bx" "the snapped window returns to its inset"
