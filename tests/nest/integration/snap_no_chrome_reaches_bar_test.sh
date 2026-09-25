#!/usr/bin/env bash
# Regression: with the titlebar and tabbar off, a snap left a 28+24px gap above
# the window as if it still had chrome. The C++ snap reports chromeH 0 for a
# window with the hyprbars:no_bar rule, so the window has to reach the bar.
#
# With no chrome the window box is what is on screen, so its top sits one inset
# below the bar: 24 + gaps_out/2 + border, around 36 here. The chrome-on value
# is 64, so the bounds below are what tells the two apart.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_STATE/state/settings.json"

printf '%s\n' '{"options":{},"apps":{"foot":{"chrome":false}}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

open_window foot
snap foot left

read -r _ y _ _ _ <<<"$(win_geom foot)"
assert_ge "$y" 24 "the window stays below the bar"
assert_le "$y" 40 "without chrome the window reaches the bar, not the titlebar inset"
