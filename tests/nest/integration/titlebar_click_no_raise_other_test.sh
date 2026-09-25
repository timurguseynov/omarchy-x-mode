#!/usr/bin/env bash
# With No gaps on, clicking a titlebar must still raise exactly the window that
# was clicked. The gap toggle reloads the config, so this guards the click path
# across that reload.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_STATE/state/settings.json"

open_window foot
open_window kitty
place_frac foot 4 30 35 35
place_frac kitty 58 30 35 35

printf '%s\n' '{"options":{"noGaps":true},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
assert_eq "$(topmost)" kitty "kitty is on top to begin with"

read -r fx fy _ _ _ <<<"$(win_geom foot)"
read -r tx ty <<<"$(titlebar_point foot)"
pointer_click "$tx" "$ty"
sleep 0.3

assert_eq "$(topmost)" foot "clicking a titlebar raises that window"
assert_eq "$(active_class)" foot "clicking a titlebar focuses that window"
read -r fx2 fy2 _ _ _ <<<"$(win_geom foot)"
assert_eq "$fx2" "$fx" "the click must not move the window"
assert_eq "$fy2" "$fy" "the click must not move the window"
