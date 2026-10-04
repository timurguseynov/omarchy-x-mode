#!/usr/bin/env bash
# A workspace with a single group has nothing to be on a side of: the arrange
# centres it -- the plugin's almost-maximize box, the same one Super+Alt+A gives --
# instead of dealing it onto the left half. Two or more groups still alternate,
# which install_arrange_halves_test covers.
#
# The expected box is the plugin's own: the scenario snaps the window to
# almost-maximize explicitly first, so this compares the arrange against what the
# pack itself calls a centred window, not against geometry rebuilt in the test.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"
half=$((mw / 2))

open_window foot
wait_still foot

nest_ctl eval 'x_mode.layout.snap("almost-maximize", hl.get_active_window())' >/dev/null
wait_still foot
want="$(win_geom foot | cut -d' ' -f1-4)"

touch "$NEST_STATE/state/arrange"
nest_ctl reload >/dev/null
sleep 1.2

got="$(win_geom foot | cut -d' ' -f1-4)"
assert_eq "$got" "$want" "a lone group is centred, not dealt onto a half"

read -r _ _ w _ _ <<<"$got"
# And it is the big centred box, not something that happens to match: a half is
# around half the monitor, this is the almost-maximize percentage of it.
assert_ge "$w" $((half + 40)) "the centred box is wider than a half"
