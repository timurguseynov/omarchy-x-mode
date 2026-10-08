#!/usr/bin/env bash
# A snapped window is recognised by where it sits horizontally and by its width,
# not by an exact vertical match: a window pushed down by a titlebar's worth is
# still the one in that zone, so a reload re-snaps it back instead of leaving it
# with the gaps from before.
. "$(dirname "$0")/../../lib.sh"

open_window foot
snap foot left

read -r x0 y0 w0 h0 _ <<<"$(win_geom foot)"

nest_ctl dispatch "hl.dsp.window.move({ x = $x0, y = $((y0 + 60)), relative = false, window = 'class:foot' })" >/dev/null
sleep 0.3

nest_ctl reload >/dev/null
# The re-snap is the pack's own pass after the reparse, and the zone it has to put
# the window back in is what is waited for -- a clock here read whatever frame the
# pass happened to be in.
want="$x0 $y0 $w0 $h0"
wait_until 8 '[ "$(win_geom foot | cut -d" " -f1-4)" = "'"$want"'" ]'

read -r x1 y1 w1 h1 _ <<<"$(win_geom foot)"
assert_eq "$x1" "$x0" "the window keeps the x of its zone"
assert_eq "$y1" "$y0" "a vertically shifted window is put back in its zone"
assert_eq "$w1" "$w0" "the window keeps the width of its zone"
assert_eq "$h1" "$h0" "the window keeps the height of its zone"
