#!/usr/bin/env bash
# Regression: turning No gaps on zeroed general:border_size, so windows merged
# into one another with no hairline left. The panel's toggle writes
# settings.json and reloads, which is the path a user takes.
#
# nogaps_test.sh covers the re-snap and gaps_out; this covers the border. The
# exact inset is left to the geometry layer (unit), so this only asserts the
# window actually moved toward the edge.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"

open_window foot
snap foot left

read -r bx _ _ _ _ <<<"$(win_geom foot)"
base_gaps="$(gaps_out)"
assert_ge "$base_gaps" 1 "gaps are on to begin with"
assert_ge "$bx" 1 "a snapped window is inset from the left edge"

printf '%s\n' '{"options":{"noGaps":true},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

assert_eq "$(gaps_out)" "$base_gaps" "no gaps leaves the desktop gaps for the other modes"
assert_eq "$(border_size)" 2 "no gaps leaves the desktop border for the other modes"
# The hairline is the xmode workspace's own rule, not general:border_size.
rule="$(nest_ctl workspacerules -j)"
printf '%s\n' "$rule" | python3 -c "
import json, sys
rules = json.load(sys.stdin)
hit = [r for r in rules if str(r.get('workspaceString')) == '1' and r.get('enabled')]
assert hit, 'no enabled rule for workspace 1'
r = hit[-1]
assert r.get('gapsOut') == [0, 0, 0, 0], r.get('gapsOut')
assert r.get('borderSize') == 1, r.get('borderSize')
" || fail "no gaps did not give the xmode workspace a 1px border and zero gaps"
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
