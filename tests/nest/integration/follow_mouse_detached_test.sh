#!/usr/bin/env bash
# x-mode sets input:follow_mouse = 2 (detached): moving the pointer does not move
# keyboard focus, and a click is what focuses the window under the cursor. At 0
# or 1 the click would behave differently, so the value is part of the contract.
#
# Positions are fractions of the monitor: the nest is a host window, so the
# logical size follows the host scale, and a hard-coded position could fall off
# the screen. The two windows are parked apart so the click has one answer.
. "$(dirname "$0")/../../lib.sh"

assert_eq "$(nest_ctl getoption input:follow_mouse | head -1 | awk '{print $2}')" 2 \
  "follow_mouse must stay detached (2)"

extent="$(pointer_extent)"
mw="${extent%x*}"
mh="${extent#*x}"
pw=$((mw / 3))
ph=$((mh / 3))
ly=$((mh / 4))

open_window foot
open_window kitty

nest_ctl dispatch "hl.dsp.window.move({ x = $((mw / 16)), y = $ly, relative = false, window = 'class:foot' })" >/dev/null
nest_ctl dispatch "hl.dsp.window.resize({ x = $pw, y = $ph, relative = false, window = 'class:foot' })" >/dev/null
nest_ctl dispatch "hl.dsp.window.move({ x = $((mw * 3 / 5)), y = $ly, relative = false, window = 'class:kitty' })" >/dev/null
nest_ctl dispatch "hl.dsp.window.resize({ x = $pw, y = $ph, relative = false, window = 'class:kitty' })" >/dev/null
nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
assert_eq "$(active_class)" foot "foot is focused to begin with"

read -r kx ky kw kh _ <<<"$(visible_geom kitty)"
pointer_click $((kx + kw / 2)) $((ky + kh / 2))

assert_eq "$(active_class)" kitty "a click focuses the window under the cursor"
