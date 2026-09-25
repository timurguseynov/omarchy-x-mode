#!/usr/bin/env bash
# Super+Alt+A gives the almost-maximized size: most of the workarea, but not all
# of it (x_mode_almost_maximize_percent, 90 by default).
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"

open_window foot
key super+alt+f
sleep 0.4
read -r _ _ max_w _ _ <<<"$(win_geom foot)"

key super+alt+a
sleep 0.4
read -r _ _ w _ _ <<<"$(win_geom foot)"

# Almost-maximize is 90% of the workarea, which is not 90% of what maximize
# gives: the workarea it is a share of excludes the gaps, so the margin is
# smaller than a tenth of max_w. What has to hold is that it is most of the
# workarea and not all of it.
assert_ge "$w" $((max_w * 8 / 10)) "almost-maximize is most of the workarea"
assert_le "$w" "$max_w" "almost-maximize is not wider than maximize"
assert_ne "$w" "$max_w" "almost-maximize leaves a margin"
