#!/usr/bin/env bash
# The chrome-growth arithmetic lives in the plugin now (hyprbars/frameFit.hpp,
# exposed as hyprbars.fit_after_chrome), and the config's old fallback -- measuring
# the fit from the desktop's general:gaps_out -- is gone on purpose. So a plugin
# without the function must be a refusal: the tab still joins, the desktop keeps
# working, and the config neither errors nor moves the window on its own.
#
# The config and the plugin ship together, which is what makes the refusal safe;
# this scenario is what keeps it a refusal instead of a crash on the next release
# where the two are briefly out of step.
. "$(dirname "$0")/../../lib.sh"

open_window foot
read -r x1 y1 w1 h1 _ <<<"$(visible_geom foot)"

# The plugin, but without the function: the shape of an older release.
nest_ctl eval 'if hl.plugin and hl.plugin.hyprbars then hl.plugin.hyprbars.fit_after_chrome = nil end' >/dev/null

open_window foot 2
assert_eq "$(group_size foot)" 2 "the second foot joins even without the fit function"

read -r x2 y2 w2 h2 _ <<<"$(visible_geom foot)"

# Nothing is left half-applied: the window is still mapped, still the same width,
# and the config answered its own calls (a Lua error in the handler would have been
# reported as a config warning by the run).
assert_ne "$w2" "" "the window is still there after the join"
assert_eq "$w2" "$w1" "the width is untouched"
assert_eq "$x2" "$x1" "the left edge is untouched"

# The pack did not move the box: with no function there is no compensation, and
# moving on a guess is what the removed fallback used to do.
assert_eq "$y2" "$y1" "no compensation, and no movement either"

# Closing the tab goes through the same path the other way and must not error.
nest_ctl dispatch 'hl.dsp.window.close({ window = "class:foot" })' >/dev/null
settle
assert_ne "$(visible_geom foot)" "" "the remaining window is still mapped"
