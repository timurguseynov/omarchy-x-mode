#!/usr/bin/env bash
# Regression: turning the gaps off changed only the top inset. The Lua side
# failed to recognise the snapped window on fractional scale, so it was never
# re-snapped and only the titlebar guard moved it. Every side has to change, and
# every side has to come back when the gaps return.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_STATE/state/settings.json"

open_window foot
snap foot left

read -r x0 y0 w0 h0 _ <<<"$(win_geom foot)"

printf '%s\n' '{"options":{"noGaps":true},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

read -r x1 y1 w1 h1 _ <<<"$(win_geom foot)"
assert_ne "$x1" "$x0" "the left inset changes when the gaps go"
assert_ne "$y1" "$y0" "the top inset changes when the gaps go"
assert_ge "$w1" "$w0" "the window widens when the gaps go"
assert_ge "$h1" "$h0" "the window grows taller when the gaps go"

printf '%s\n' '{"options":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

read -r x2 y2 w2 h2 _ <<<"$(win_geom foot)"
assert_eq "$x2" "$x0" "the left inset comes back"
assert_eq "$y2" "$y0" "the top inset comes back"
assert_eq "$w2" "$w0" "the width comes back"
assert_eq "$h2" "$h0" "the height comes back"
