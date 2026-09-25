#!/usr/bin/env bash
# Regression: snapping the same window again moved it down by the height of the
# chrome it does not have. The C++ snap returns chromeH 0 for a window with the
# hyprbars:no_bar rule, but the Lua path added TITLEBAR (plus GROUPBAR in a
# group) anyway, so the first snap was right and the second crept down.
#
# The window has chrome off from its first map, so the rule is in place before
# the snap starts.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_STATE/state/settings.json"

printf '%s\n' '{"options":{},"apps":{"foot":{"chrome":false}}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

open_window foot
snap foot left
read -r _ y1 _ _ _ <<<"$(win_geom foot)"

snap foot left
read -r _ y2 _ _ _ <<<"$(win_geom foot)"

snap foot left
read -r _ y3 _ _ _ <<<"$(win_geom foot)"

assert_ge "$y1" 24 "the window stays below the bar"
assert_eq "$y2" "$y1" "a second snap must not creep down by the chrome height"
assert_eq "$y3" "$y1" "a third snap holds the same top"
