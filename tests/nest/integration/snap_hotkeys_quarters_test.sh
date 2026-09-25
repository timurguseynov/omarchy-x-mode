#!/usr/bin/env bash
# Ctrl+Alt+U/I/J/K snap to the four quarters. Each corner keeps its own quadrant
# and the quarters are half the frame wide and half of it tall.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"
mh="${extent#*x}"

open_window foot

key ctrl+alt+u
sleep 0.4
read -r ux uy uw uh _ <<<"$(win_geom foot)"
key ctrl+alt+i
sleep 0.4
read -r ix iy iw ih _ <<<"$(win_geom foot)"
key ctrl+alt+j
sleep 0.4
read -r jx jy jw jh _ <<<"$(win_geom foot)"
key ctrl+alt+k
sleep 0.4
read -r kx ky kw kh _ <<<"$(win_geom foot)"

assert_le "$ux" $((mw / 3)) "top-left starts on the left"
assert_ge "$ix" "$ux" "top-right starts to the right"
assert_le "$uy" $((mh / 3)) "the top quarters are at the top"
assert_ge "$jy" $((mh / 2)) "the bottom quarters are below the middle"
assert_le "$jx" $((mw / 3)) "bottom-left starts on the left"
assert_ge "$kx" "$ix" "bottom-right starts where top-right does"
assert_eq "$ky" "$jy" "both bottom quarters share their top"

for size in "$uw $uh" "$iw $ih" "$jw $jh" "$kw $kh"; do
  read -r w h <<<"$size"
  assert_le "$w" $((mw * 6 / 10)) "a quarter is not the full width"
  assert_le "$h" $((mh * 6 / 10)) "a quarter is not the full height"
  assert_ge "$h" $((mh / 3)) "a quarter is a substantial half"
done
