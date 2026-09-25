#!/usr/bin/env bash
# Regression: switching No gaps used to move windows that were not in a snap
# zone. Only a window the pack recognises as snapped may be re-laid out; a
# freely floating one has to stay exactly where the user left it.
#
# Positions are fractions of the monitor: the nest is a host window, so the
# logical size follows the host scale (900x1000 at scale 1, 450x500 at scale 2),
# and a hard-coded position would fall off the screen on one of them.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_STATE/state/settings.json"

extent="$(pointer_extent)"
mw="${extent%x*}"
mh="${extent#*x}"
pw=$((mw / 3))
ph=$((mh / 3))
free_x=$((mw / 2 - pw / 2))
free_y=$((mh / 3))

open_window foot
open_window kitty
snap foot left

# Park kitty in the middle, away from every edge zone.
nest_ctl dispatch "hl.dsp.window.move({ x = $free_x, y = $free_y, relative = false, window = 'class:kitty' })" >/dev/null
nest_ctl dispatch "hl.dsp.window.resize({ x = $pw, y = $ph, relative = false, window = 'class:kitty' })" >/dev/null
sleep 0.3

read -r fx _ _ _ _ <<<"$(win_geom foot)"
read -r kx ky _ _ _ <<<"$(win_geom kitty)"

printf '%s\n' '{"options":{"noGaps":true},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

assert_ne "$(win_geom foot | awk '{print $1}')" "$fx" "the snapped window is re-laid out"
read -r kx2 ky2 _ _ _ <<<"$(win_geom kitty)"
assert_eq "$kx2" "$kx" "a free window must not move when the gaps go"
assert_eq "$ky2" "$ky" "a free window must not move when the gaps go"

printf '%s\n' '{"options":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

read -r kx3 ky3 _ _ _ <<<"$(win_geom kitty)"
assert_eq "$kx3" "$kx" "a free window must not move when the gaps come back"
assert_eq "$ky3" "$ky" "a free window must not move when the gaps come back"
