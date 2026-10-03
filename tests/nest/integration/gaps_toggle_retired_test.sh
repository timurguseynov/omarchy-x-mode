#!/usr/bin/env bash
# Omarchy's own gaps toggle is retired by the pack, once per load.
#
# Its state is a file in a directory Omarchy sources on every load, so a desktop
# that ever pressed Ctrl+Shift+Backspace has gaps_out, gaps_in and the border
# zeroed for good: only removing the file brings them back, and the pack is the one
# that owns gaps now. The pack removes it at load -- the same thing the toggle's own
# "off" does -- and reloads once so the values it had already zeroed come back.
#
# The nest sources that directory the way Omarchy does, so a planted file has its
# real effect here rather than being a file nobody reads.
. "$(dirname "$0")/../../lib.sh"

TOGGLE_DIR="$NEST_STATE/home/.local/state/omarchy/toggles/hypr"
TOGGLE="$TOGGLE_DIR/window-no-gaps.lua"
SOURCE="/usr/share/omarchy/default/hypr/toggles/window-no-gaps.lua"
# The file is sourced on every load, so leaving it behind would decide the next
# scenario's gaps too -- including if this one fails halfway.
trap 'rm -f "$TOGGLE"' EXIT

open_window foot
sleep 0.3
base_out="$(gaps_out)"
[ "$base_out" != 0 ] || fail "the nest started with no gaps; the assertions below would prove nothing"

plant() {
  mkdir -p "$TOGGLE_DIR"
  cp "$SOURCE" "$TOGGLE"
}

# The desktop's own state: switched on the way its key does, and it zeroes the gaps.
plant
nest_ctl reload >/dev/null
wait_until 5 '[ "$(gaps_out)" = 0 ]' || fail "the planted gaps toggle did not zero the gaps"

# The pack notices and retires it: the file goes, and the reload it schedules puts
# the desktop's own gaps back.
wait_until 5 '[ ! -e "$TOGGLE" ]' || fail "the pack left Omarchy's gaps toggle in place"
wait_until 10 '[ "$(gaps_out)" = "$base_out" ]' || fail "the gaps did not come back after the toggle was retired (gaps_out $(gaps_out))"

# And the same when x-mode is switched back on from the panel: that is the panel
# writing the flag and reloading, so the load has to do it there too.
plant
printf '%s\n' 'off' > "$NEST_STATE/state/enabled"
nest_ctl reload >/dev/null
wait_until 5 '[ "$(gaps_out)" = 0 ]' || fail "with x-mode off the planted toggle did not zero the gaps"
printf '%s\n' 'on' > "$NEST_STATE/state/enabled"
nest_ctl reload >/dev/null
wait_until 5 '[ ! -e "$TOGGLE" ]' || fail "switching x-mode back on left the gaps toggle in place"
wait_until 10 '[ "$(gaps_out)" = "$base_out" ]' || fail "the gaps did not come back after switching x-mode on (gaps_out $(gaps_out))"
rm -f "$NEST_STATE/state/enabled"
