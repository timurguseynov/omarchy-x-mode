#!/usr/bin/env bash
# Super+Alt+Left cycles a window through the Rectangle fractions: half, then two
# thirds, then a third, then half again. Super+Alt+Right does the same from the
# right edge, where the edge that stays put is the right one.
#
# This is the gesture's keybinding, so it covers the bind and the cycle state
# together: pressing it must not creep the window sideways either.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"

open_window foot

read -r x0 _ _ _ _ <<<"$(win_geom foot)"
key super+alt+left
sleep 0.4
read -r x1 _ w1 _ _ <<<"$(win_geom foot)"
key super+alt+left
sleep 0.4
read -r x2 _ w2 _ _ <<<"$(win_geom foot)"
key super+alt+left
sleep 0.4
read -r x3 _ w3 _ _ <<<"$(win_geom foot)"
key super+alt+left
sleep 0.4
read -r x4 _ w4 _ _ <<<"$(win_geom foot)"

assert_le "$w1" $((mw * 6 / 10)) "the first press is a half"
assert_ge "$w2" "$w1" "the second press is wider than a half"
assert_le "$w3" "$w1" "the third press is narrower than a half"
# Within a pixel: each fraction is recomputed from the frame, so the wrap can
# land a pixel off the first pass.
assert_between "$w4" $((w1 - 2)) $((w1 + 2)) "the fourth press wraps back to a half"
assert_eq "$x1" "$x2" "the cycle does not creep sideways"
assert_eq "$x3" "$x4" "the cycle does not creep sideways"

# From the right the same widths, held against the right edge of the frame.
read -r rw _ _ _ _ <<<"$(win_geom foot)"
key super+alt+right
sleep 0.4
read -r rx _ rw1 _ _ <<<"$(win_geom foot)"
key super+alt+right
sleep 0.4
read -r rx2 _ rw2 _ _ <<<"$(win_geom foot)"
key super+alt+right
sleep 0.4
read -r rx3 _ rw3 _ _ <<<"$(win_geom foot)"

assert_ge "$rw2" "$rw1" "the right cycle is a half, then wider"
assert_le "$rw3" "$rw1" "the right cycle then narrows below a half"
assert_eq $((rx + rw1)) $((rx2 + rw2)) "the right cycle holds the right edge"
assert_eq $((rx2 + rw2)) $((rx3 + rw3)) "the right cycle holds the right edge"
