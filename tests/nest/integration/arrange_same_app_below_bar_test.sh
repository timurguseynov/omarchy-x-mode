#!/usr/bin/env bash
# The arrange must leave every window's titlebar below the bar -- including a
# window that carries the tabbar. Two windows of the same app are one group, and
# a group's chrome is the titlebar *plus* the tabbar; a box placed with the wrong
# chrome puts the titlebar over the bar (or at the top edge of the screen), which
# is what an install looked like: the arrange and the grouping happen together,
# and a plain snap (one window, no tabbar) was always fine.
#
# install_arrange_halves_test covers the arrange with two *different* apps, where
# visual_top counts only the titlebar; this is the same deal with a tabbar.
. "$(dirname "$0")/../../lib.sh"

top="$(bar_top)"

open_window foot
open_window foot
wait_until 5 '[ "$(group_size foot)" = 2 ]' || fail "the two foot windows did not become one group"

touch "$NEST_STATE/state/arrange"
nest_ctl reload >/dev/null
sleep 1.2

# Every window of the group shares one box: whichever the arrange dealt, the
# titlebar has to clear the bar.
vis="$(visual_top foot)"
read -r _ fy _ _ _ <<<"$(win_geom foot)"
echo "bar_top=$top fy=$fy visual_top=$vis"
assert_ge "$fy" "$((top + 8))" "the arranged content stays below the bar"
assert_ge "$vis" "$((top + 8))" "the arranged titlebar clears the bar"
