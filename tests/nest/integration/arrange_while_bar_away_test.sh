#!/usr/bin/env bash
# An install asks for the arrange at a reload, and the shell restart that follows
# takes the bar away for a moment. If the arrange's pass runs then, the zones are
# fractions of the whole screen: the windows land at the top edge, over the bar.
# The pass has to wait for a frame it can trust -- the bar, or a top the plugin
# still remembers -- and deal the windows once the bar is back, under it.
#
# The plugin's memory of the last bar top is turned off, which is the only state
# where the frame is really unknown (no bar now, nothing remembered), so the wait
# is the behavior under test and not the timing.
. "$(dirname "$0")/../../lib.sh"

memory_off() {
  nest_ctl eval "hl.config({ plugin = { hyprbars = { x_mode_bar_top_memory_ms = 0 } } })" >/dev/null 2>&1 || true
}

extent="$(pointer_extent)"
mw="${extent%x*}"

open_window foot
wait_still foot
before="$(win_geom foot | cut -d' ' -f1-4)"

nest_bar_stop
memory_off
wait_until 5 '[ "$(bar_top)" = 0 ]' || fail "the bar never released the top"

touch "$NEST_STATE/state/arrange"
nest_ctl reload >/dev/null
# A reload publishes the config file's values again, so the memory is turned off
# once more, before the arrange timer fires.
memory_off

# The arrange timer (600ms) has come and gone. The pass may not have placed
# anything: the frame it would have used was the whole screen.
sleep 1.0
assert_eq "$(win_geom foot | cut -d' ' -f1-4)" "$before" \
  "an arrange does not place windows against a frame with no bar"

# With the bar back the frame is known, and the arrange deals the window -- below
# the bar. It is one group on its workspace, so the deal is the centred box.
nest_bar_start
top="$(bar_top)"
want=$((top + 8))
half=$((mw / 2))
wait_until 8 '[ "$(visual_top foot)" -ge "$want" ]' \
  || fail "the arrange never ran after the bar returned: $(win_geom foot), visual top $(visual_top foot), bar at $top"
read -r _ ry rw _ _ <<<"$(win_geom foot)"
assert_ge "$ry" "$want" "the arranged content is under the bar"
assert_ge "$rw" $((half + 40)) "the lone group took the centred box"
assert_ne "$(win_geom foot | cut -d' ' -f1-4)" "$before" "the arrange dealt the window"
