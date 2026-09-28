#!/usr/bin/env bash
# A window whose client minimum is wider than a half is snapped to a box bigger
# than its zone (oversized_snap_anchors_test). The cycle used to stop there: it
# built its candidates from the raw fractions, so the grown window matched none
# of them and the next press only re-snapped the same half. The candidates are
# now grown to the minimum the same way a snap is (geom.grow_to_min,
# Snap::contentBox), so the next press steps on -- wider, and holding the edge
# the side is anchored to.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"
mh="${extent#*x}"
# Between a half and two thirds of the frame, so the half has to grow and two
# thirds still fits. The minimum height stays inside the frame (a minimum taller
# than the work area is a different, pre-existing mismatch: contentBox grows to
# it, the compositor then fits the window inside).
minw=$((mw * 55 / 100))
minh=$((mh / 2))

open_window foot
# Let the open watch stop: this is only about the snap and the cycle.
sleep 2.2

nest_ctl eval "hl.window_rule({ name = 'oversized-cycle', match = { class = 'foot' }, min_size = '${minw} ${minh}' })" >/dev/null
sleep 0.5

key super+alt+left
sleep 0.4
read -r x1 _ w1 _ _ <<<"$(win_geom foot)"
key super+alt+left
sleep 0.4
read -r x2 _ w2 _ _ <<<"$(win_geom foot)"
key super+alt+left
sleep 0.4
read -r x3 _ w3 _ _ <<<"$(win_geom foot)"

assert_ge "$w1" "$minw" "the snapped half keeps the window's minimum width"
assert_ge "$x1" 0 "the grown snap does not hang off the left edge"
assert_eq "$x1" "$x2" "the cycle holds the snapped edge"
assert_ge "$w2" "$w1" "the next press widens the snap"
assert_ne "$w2" "$w1" "and it widens past the minimum"
assert_eq "$x2" "$x3" "the cycle does not creep sideways"
assert_le "$w3" "$w2" "the press after that comes back down"
assert_ge "$w3" "$minw" "and it still keeps the minimum"
