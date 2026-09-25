#!/usr/bin/env bash
# Regression: a lone window turned into a group of one (hyprbars then draws the
# tabbar above the box, so the chrome grows by the tabbar height) was never
# pushed back below the bar. The open watch skips grouped windows, and a group
# change has no geometry event of its own, so nothing moved it — kdenlive was
# caught in exactly that state: box y=34 with a 52px chrome, its titlebar and
# tabbar at -18, above the screen.
#
# window.update_rules is what a group change raises (CGroup::applyWindowDecosAndUpdates
# calls propertiesChanged, as does switching tabs). x-mode.lua's push_bars_below
# acts on it; this holds that down.
. "$(dirname "$0")/../../lib.sh"

open_window foot
# Clear the open watch so this is only about the group change, not the watch.
sleep 2.2
assert_ge "$(visual_top foot)" "$(bar_top)" "a lone window starts below the bar"

nest_ctl dispatch "hl.dsp.group.toggle({ window = 'class:foot' })" >/dev/null
sleep 0.5
assert_eq "$(group_size foot)" 1 "the lone window is now a group of one"
assert_ge "$(visual_top foot)" "$(bar_top)" "the lone group's tabbar stays below the bar"
