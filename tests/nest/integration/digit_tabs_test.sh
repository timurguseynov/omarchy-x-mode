#!/usr/bin/env bash
# Cmd+1..9 switch the pack's tabs for an app that is not being handed Ctrl+digit.
#
# The digits are only free when the workspaces are somewhere else: with the
# workspace keys on F1..F10 their binds are released, and the pack takes the
# digits itself -- Ctrl+digit for an app that has the flag, the pack's own tab for
# one that does not. Omarchy's own digit binds are written by keycode, so the nest
# plants one of those (the 3 key) the way Omarchy writes it; the pack has to
# leave the digit alone while it is still Omarchy's.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"

open_window foot
open_window foot 2
open_window foot 3
assert_eq "$(group_size foot)" 3 "three windows share the group"

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
assert_eq "$(active_tab_index foot)" 0 "the first tab is current to begin with"

# Off: the digit belongs to Omarchy's workspace keys, so it is the app's.
key super+3
sleep 0.4
assert_eq "$(active_tab_index foot)" 0 "Cmd+3 leaves the tabs alone while the workspace key owns it"

# With the workspaces on the F keys the digit is the pack's, and for an app that
# is not being handed Ctrl+3 it switches the pack's tab.
printf '%s\n' '{"options":{"workspacesOnFkeys":true},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
wait_until 5 [ "$(bind_count 3 64)" = 1 ] || fail "the digit did not become the pack's after the reload"

key super+3
wait_until 3 [ "$(active_tab_index foot)" = 2 ] || fail "Cmd+3 did not switch to the third tab"
assert_eq "$(active_tab_index foot)" 2 "Cmd+3 switches the pack's tab when the digit is free"

# An app that is handed Ctrl+3 keeps it: that is what the flag is for, and the
# tab must not move out from under the app.
printf '%s\n' '{"options":{"workspacesOnFkeys":true},"apps":{"foot":{"ctrlAsSuper":true},"footcapa":{"ctrlAsSuper":true},"footcapb":{"ctrlAsSuper":true}}}' > "$SETTINGS"
refresh_apps
sleep 0.6

key super+1
sleep 0.4
assert_eq "$(active_tab_index foot)" 2 "Cmd+1 is Ctrl+1 for the flagged app, not a tab switch"

# And what the app is handed is the chord itself, not merely something that is
# not a tab switch: one window is given a physical Ctrl+3, another the digit, and
# the bytes have to match. Two windows, because the `cat` of a capture keeps the
# file it opened -- a second measurement has to open its own. `stty raw -echo`
# keeps the pty from editing the line.
CAPA="$NEST_STATE/digit-tabs-a.out"
CAPB="$NEST_STATE/digit-tabs-b.out"
received() { od -An -v -tx1 "$1" 2>/dev/null | tr -s ' \n' ' ' | sed 's/^ //;s/ $//'; }
rm -f "$CAPA" "$CAPB"

open_command footcapa foot -a footcapa sh -c "stty raw -echo; cat > '$CAPA'"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:footcapa' })" >/dev/null
sleep 0.3
key ctrl+3
sleep 0.5
base="$(received "$CAPA")"
assert_ne "$base" "" "a physical Ctrl+3 hands the terminal something"

open_command footcapb foot -a footcapb sh -c "stty raw -echo; cat > '$CAPB'"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:footcapb' })" >/dev/null
sleep 0.3
key super+3
sleep 0.5
assert_eq "$(received "$CAPB")" "$base" "Cmd+3 hands the app the bytes Ctrl+3 does"
