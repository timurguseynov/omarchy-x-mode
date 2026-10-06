#!/usr/bin/env bash
# The dock's distance from the screen edge is half of general:gaps_out, and it is
# re-read when Hyprland reports configreloaded. Editing the gaps used to leave the
# dock at the old distance until the shell was restarted.
#
# The gap change has to come through a reload: `hyprctl keyword` is not written to
# the config file, so the reload that emits configreloaded would put the old value
# back. The No gaps toggle is the real path for this (settings file, then reload).
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"

dock_start
dock_settle

read -r x1 y1 w1 h1 <<<"$(dock_box)"
assert_ge "$(gaps_out)" 1 "gaps are on to begin with"

printf '%s\n' '{"options":{"noGaps":true},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
# Leave the socket alone for a moment. The dock re-reads general:gaps_out
# with its own hyprctl, and a poll that starts immediately keeps that read
# queued until this wait is already over.
sleep 1.5
dock_x_ge() { local x; read -r x _ <<<"$(dock_box)"; [ "$x" -ge "$1" ]; }
# The dock re-reads the gaps for about six seconds after the reload. This
# wait has to outlast that, or a late read is reported as the dock not moving.
for _ in $(seq 1 32); do
  dock_x_ge $((x1 + 3)) && break
  sleep 0.25
done

read -r x2 _ _ _ <<<"$(dock_box)"
assert_ge "$x2" $((x1 + 3)) "with the gaps gone the dock moves to the edge"
assert_eq "$(dock_box | awk '{print $4}')" "$h1" "the dock keeps its height"

printf '%s\n' '{"options":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 1.5
dock_x_is() { local x; read -r x _ <<<"$(dock_box)"; [ "$x" = "$1" ]; }
for _ in $(seq 1 32); do
  dock_x_is "$x1" && break
  sleep 0.25
done

read -r x3 _ _ _ <<<"$(dock_box)"
assert_eq "$x3" "$x1" "the dock moves back when the gaps return"

dock_stop
