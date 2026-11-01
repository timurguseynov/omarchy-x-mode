#!/usr/bin/env bash
# The tabbar + still opens a window when the command file outlives the counter.
#
# The file survives a Hyprland restart; the plugin's launch counter does not. The
# dock adopts the leftover's seq at startup ("do not spawn on a leftover"), so a
# plugin counting from zero again wrote that same seq for its first +, and the
# dock's dedupe threw the click away: nothing launched, no error anywhere.
. "$(dirname "$0")/../../lib.sh"

# The leftover the next dock will adopt. 1 is what the counter would produce for
# the first click of a fresh plugin, which is the collision.
printf 'launch foot 1\n' > "$DOCK_RUNTIME/omarchy-x-mode-launch.cmd"

dock_start
open_window foot
open_window foot 2
assert_eq "$(group_size foot)" 2 "two windows share the group"

read -r px py <<<"$(plus_point foot)"
pointer_click "$px" "$py"

wait_for_count foot 3 30
assert_eq "$(count_class foot)" 3 "the + opens another window over an adopted seq"
