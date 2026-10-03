#!/usr/bin/env bash
# Ctrl+1..9 switch to that tab of the group, and only once the option is on. The
# bind table is checked elsewhere; this is the behaviour: Ctrl+3 makes the third
# tab current.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"

open_window foot
open_window foot 2
open_window foot 3
assert_eq "$(group_size foot)" 3 "three windows share the group"

nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3

# Off by default: the key is free.
key ctrl+3
sleep 0.4
assert_eq "$(bind_count_desc 'Switch to tab 3' 4)" 0 "the option is off to begin with"

printf '%s\n' '{"options":{"ctrlTabSwitch":true},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
# A reload re-parses the config and the option applier creates the binds after
# it returns, so the press waits for the bind rather than for a second.
wait_until 5 "[ \"$(bind_count_desc 'Switch to tab 3' 4)\" = 1 ]" || fail "the Ctrl+1..9 binds did not land after the reload"

open_window foot 4
nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3

key ctrl+3
wait_until 3 '[ "$(active_tab_index foot)" = 2 ]' || fail "Ctrl+3 did not make the third tab current"
assert_eq "$(active_tab_index foot)" 2 "Ctrl+3 makes the third tab current"

key ctrl+1
wait_until 3 '[ "$(active_tab_index foot)" = 0 ]' || fail "Ctrl+1 did not go back to the first tab"
assert_eq "$(active_tab_index foot)" 0 "Ctrl+1 goes back to the first tab"
