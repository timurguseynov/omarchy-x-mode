#!/usr/bin/env bash
# Regression: a reload left a snapped window with the layout from the previous
# gaps. The re-snap only looked for a zone match and ignored the geometry the
# window actually had, so it was not recognised as snapped at all.
#
# This is the path a theme switch and the panel's toggles take: they write
# settings.json and reload.
. "$(dirname "$0")/../../lib.sh"

open_window foot
snap foot left

read -r x1 y1 w1 h1 _ <<<"$(win_geom foot)"

nest_ctl reload >/dev/null
sleep 0.6

read -r x2 y2 w2 h2 _ <<<"$(win_geom foot)"

assert_eq "$x2" "$x1" "a snapped window keeps its x across a reload"
assert_eq "$y2" "$y1" "a snapped window keeps its y across a reload"
assert_eq "$w2" "$w1" "a snapped window keeps its width across a reload"
assert_eq "$h2" "$h1" "a snapped window keeps its height across a reload"
assert_ge "$(visual_top foot)" "$(bar_top)" "the titlebar stays below the bar"
