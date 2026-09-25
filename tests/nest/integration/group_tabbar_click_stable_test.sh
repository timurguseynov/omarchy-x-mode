#!/usr/bin/env bash
# Regression: clicking the tabbar of an already focused group changed the window
# geometry and the z-order. The tab switch focused, then focused again, so there
# was a frame in between with no focused window, and the client was reconfigured.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window foot 2
assert_eq "$(group_size foot)" 2 "the second foot joins the group"

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3

read -r x1 y1 w1 h1 _ <<<"$(visible_geom foot)"

# The tabbar occupies the 24px above the window box; click in the middle of it.
pointer_click $((x1 + w1 / 2)) $((y1 - 12))
sleep 0.3

read -r x2 y2 w2 h2 _ <<<"$(visible_geom foot)"
assert_eq "$x2" "$x1" "clicking the tabbar must not move the window"
assert_eq "$y2" "$y1" "clicking the tabbar must not move the window"
assert_eq "$w2" "$w1" "clicking the tabbar must not resize the window"
assert_eq "$h2" "$h1" "clicking the tabbar must not resize the window"
assert_eq "$(topmost)" foot "the group stays on top"
assert_eq "$(active_class)" foot "the group stays focused"
