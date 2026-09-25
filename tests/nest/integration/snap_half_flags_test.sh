#!/usr/bin/env bash
# x_mode_snap_top_half is off by default, so the top of a side strip is still a
# left or right half. Turning it on makes that strip pick a top half, which is
# the full width instead of half of it.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"

open_window foot

# 60px down the left strip: inside the 145px short-edge band.
drag_to foot 5 60
read -r _ _ w1 _ _ <<<"$(win_geom foot)"
assert_le "$w1" $((mw * 6 / 10)) "with top_half off the strip gives a left half"

plugin_option x_mode_snap_top_half true

snap foot left
drag_to foot 5 60
read -r _ _ w2 _ _ <<<"$(win_geom foot)"
assert_ge "$w2" $((mw * 8 / 10)) "with top_half on the strip's top picks a top half"

plugin_option x_mode_snap_top_half false
