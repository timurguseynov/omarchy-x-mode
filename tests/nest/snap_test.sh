#!/usr/bin/env bash
# Snapping: halves keep the bar/gap/border inset and never overlap.
. "$(dirname "$0")/../lib.sh"

open_window foot
open_window kitty
snap foot left
snap kitty right

read -r fx fy fw fh _ <<<"$(win_geom foot)"
read -r kx ky kw kh _ <<<"$(win_geom kitty)"

assert_ge "$fy" 64 "a snapped window keeps the gap under the bar"
assert_ge "$ky" 64 "a snapped window keeps the gap under the bar"
assert_eq "$fx" 12 "the left half starts at the left inset"
assert_ge "$kx" $((fx + fw)) "the halves must not overlap"
assert_ge "$(visual_top foot)" 36 "the titlebar clears the bar"
