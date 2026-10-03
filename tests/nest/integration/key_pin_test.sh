#!/usr/bin/env bash
# A card can pin one app against the desktop: a replacement that is on for every
# app can be off for one, and the other way round.
#
# The case that asked for it: the pack's tabs own Cmd+1..0 everywhere, but an editor
# wants them as its own Ctrl+1..6. So the global flags are on, that app's card says
# Always on for Super-as-Ctrl and Always off for the digits, and the physical
# Ctrl+3 has to reach it too -- which means the Ctrl-tabs row is on globally as well
# and pinned off for the same class. Another class, with no card at all, keeps
# following the desktop and still switches tabs.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"
CAP="$NEST_STATE/key-pin.out"
received() { od -An -v -tx1 "$1" 2>/dev/null | tr -s ' \n' ' ' | sed 's/^ //;s/ $//'; }

# Three windows of a class with no card: the tab side of the contract.
open_window foot
open_window foot 2
open_window foot 3
nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3

printf '%s\n' '{"options":{"workspacesOnFkeys":true,"keys":{"digitTabs":true,"ctrlTabSwitch":true}},"apps":{"footzed":{"ctrlAsSuper":true,"digitTabs":false,"ctrlTabSwitch":false}}}' > "$SETTINGS"
nest_ctl reload >/dev/null
wait_until 5 '[ "$(bind_count 3 64)" = 1 ]' || fail "the digits did not become the pack's after the reload"

# The class with no card follows the desktop: Cmd+3 switches the pack's tab.
nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3
key super+3
wait_until 3 '[ "$(active_tab_index foot)" = 2 ]' || fail "the unpinned class did not switch tabs on Cmd+3"
assert_eq "$(active_tab_index foot)" 2 "an app with no card still follows the desktop"

# The pinned one: the digit never becomes a tab, and Super-as-Ctrl hands it over.
open_command footzed foot -a footzed sh -c "stty raw -echo; cat > '$CAP'"
wait_until 3 '[ -e "$CAP" ]' || fail "the pinned window did not open its capture file"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:footzed' })" >/dev/null
sleep 0.3

# Ctrl+3 is what it should receive, and the Ctrl-tabs row is pinned off for it, so
# the physical key reaches it too.
key ctrl+3
sleep 0.4
base="$(received "$CAP")"
assert_ne "$base" "" "a physical Ctrl+3 reaches the pinned app"

key super+3
sleep 0.5
assert_eq "$(received "$CAP")" "$base $base" "Cmd+3 reaches it as the same chord, twice"
