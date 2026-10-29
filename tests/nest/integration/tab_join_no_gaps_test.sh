#!/usr/bin/env bash
# A tab joining a snapped window must not resize it, including on a workspace the
# pack keeps gapless. "No gaps" is a workspace rule (gaps_out 0, border_size 1),
# while the gap and border the desktop reports globally stay at 10 and 2, so the
# join measured its own fit in the wrong frame: the box was pulled 11px down and
# cut 22px shorter, centred, and it stayed that way after the tab closed.
. "$(dirname "$0")/../../lib.sh"

printf '%s\n' '{"options":{"noGaps":true,"compactTabs":true},"apps":{}}' > "$NEST_SETTINGS"
nest_ctl eval 'if x_mode and x_mode.refresh_options then x_mode.refresh_options() end' >/dev/null
sleep 0.4

open_command nogapjoin foot -a nogapjoin
settle
snap nogapjoin maximize
sleep 0.5
read -r x1 y1 w1 h1 _ <<<"$(win_geom nogapjoin)"

open_command nogapjoin foot -a nogapjoin
sleep 1.5
assert_eq "$(group_size nogapjoin)" 2 "the second window joins the group"
read -r x2 y2 w2 h2 _ <<<"$(win_geom nogapjoin)"

assert_eq "$y2" "$y1" "a tab with no second row must not push the box down"
assert_eq "$h2" "$h1" "a tab with no second row must not shorten the box"
assert_eq "$w2" "$w1" "the width is untouched"
assert_eq "$x2" "$x1" "the left edge is untouched"
