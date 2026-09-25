#!/usr/bin/env bash
# A window resized after it has opened must still clear the bar. Hyprland resizes
# around the window's centre, so growing a window moves its top-left up, and its
# own fit for floating windows (CDefaultFloatingAlgorithm::fitBoxInWorkArea) is
# only reached from placement and from moving between monitors or workspaces —
# never from a resize. So the pack watches a fresh window until its geometry stops
# changing and re-clamps it (x-mode.lua's watch_until_settled); before that, this
# was a known gap that reported instead of failing.
#
# The resize here lands inside that watch, which is the shape seen live: a client
# that reports its class and size late, and the nest being resized by the harness
# right after it started.
. "$(dirname "$0")/../../lib.sh"

open_window foot
sleep 0.6

read -r _ _ w h _ <<<"$(win_geom foot)"
nest_ctl dispatch "hl.dsp.window.resize({ x = $((w + 120)), y = $((h + 150)), relative = false, window = 'class:foot' })" >/dev/null
sleep 0.5

assert_ge "$(visual_top foot)" "$(bar_top)" "a resized window clears the bar"

# Shrinking never pushed anything up, and it is worth holding to anyway: if this
# fails, something moved the window up while making it smaller.
nest_ctl dispatch "hl.dsp.window.resize({ x = 200, y = 200, relative = false, window = 'class:foot' })" >/dev/null
sleep 0.5
assert_ge "$(visual_top foot)" "$(bar_top)" "shrinking a window does not push it over the bar"
