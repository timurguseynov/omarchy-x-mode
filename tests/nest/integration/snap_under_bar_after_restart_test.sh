#!/usr/bin/env bash
# A shell restart -- what an install ends with -- takes the bar away for a moment.
# A window snapped while it is away is placed against the screen's own top edge,
# because the zones are fractions of the frame the bar carves out. That window has
# to come back under the bar when the bar returns: the frame moved, so everything
# on a zone moves with it. Without that, an install leaves a window over the topbar
# until the next snap, which is the "sometimes a window ends up above the bar".
#
# The plugin remembers the last bar top for a while; the scenario turns that
# memory off, the one situation where the frame really is unknown (no bar now,
# nothing remembered), so this pins the behavior instead of the timing.
. "$(dirname "$0")/../../lib.sh"

memory_off() {
  nest_ctl eval "hl.config({ plugin = { hyprbars = { x_mode_bar_top_memory_ms = 0 } } })" >/dev/null 2>&1 || true
}

open_window foot
wait_still foot

nest_bar_stop
memory_off
wait_until 5 '[ "$(bar_top)" = 0 ]' || fail "the bar never released the top"

# The snap a shell restart leaves behind: the bar is away and nothing is
# remembered, so the plugin has no bar top to use.
key super+alt+left
wait_still foot
snapped="$(win_geom foot | cut -d' ' -f1-4)"

nest_bar_start
top="$(bar_top)"
want=$((top + 8))
wait_until 8 '[ "$(visual_top foot)" -ge "$want" ]' \
  || fail "after the bar returned the window stayed at $(win_geom foot) (visual top $(visual_top foot)), bar at $top"
read -r _ ry _ _ _ <<<"$(win_geom foot)"
assert_ge "$ry" "$want" "the window is back under the bar"
assert_ne "$(win_geom foot | cut -d' ' -f1-4)" "$snapped" "the window was placed again for the frame the bar makes"
