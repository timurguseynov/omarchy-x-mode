#!/usr/bin/env bash
# A reload clears a half-faded window.
#
# The arrange fades every window out before it deals them into halves and reveals
# them at 1 again, in 1/10 steps of 25ms each. The timers that would bring them
# back die with the config, so a reload in the middle -- install.sh reloads, so a
# reinstall does it -- leaves the windows at whatever step they reached, and the
# first step is exactly 0.9. Since the titlebar is part of the window's surface,
# that is a desktop whose titlebars look translucent.
#
# The stuck state is set directly here rather than by racing a reload against a
# 250ms fade: it is the same state the interrupted fade leaves, and pinning it
# means this cannot pass by happening to reload at a lucky moment.
. "$(dirname "$0")/../../lib.sh"

dimmer() { # CLASS PROP -> "%.3f"
  nest_ctl getprop "class:$1" "$2" 2>/dev/null | python3 -c '
import sys
try:
    print("%.3f" % float(sys.stdin.read().strip()))
except ValueError:
    print("none")'
}

open_window foot
nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
assert_eq "$(dimmer foot opacity)" "1.000" "a fresh window is opaque"

# What an interrupted fade leaves behind, both props the fade sets.
nest_ctl eval 'local w = hl.get_active_window(); hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity", value = "0.9", window = w })); hl.dispatch(hl.dsp.window.set_prop({ prop = "opacity_inactive", value = "0.9", window = w }))' >/dev/null
sleep 0.3
assert_eq "$(dimmer foot opacity)" "0.900" "the stuck state is in place to begin with"

nest_ctl reload >/dev/null
wait_until 5 '[ "$(dimmer foot opacity)" = "1.000" ]' || fail "a reload left the window dimmed at $(dimmer foot opacity)"
assert_eq "$(dimmer foot opacity_inactive)" "1.000" "and the unfocused prop is back too, so its titlebar is solid"
