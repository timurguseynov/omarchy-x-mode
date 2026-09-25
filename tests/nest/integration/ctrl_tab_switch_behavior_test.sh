#!/usr/bin/env bash
# Ctrl+1..9 switch to that tab of the group, and only once the option is on. The
# bind table is checked elsewhere; this is the behaviour: Ctrl+3 makes the third
# tab current.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_STATE/state/settings.json"

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
sleep 0.8

open_window foot 4
nest_ctl dispatch "hl.dsp.focus({ window = 'class:foot' })" >/dev/null
sleep 0.3

key ctrl+3
sleep 0.4
assert_eq "$(active_tab_index foot)" 2 "Ctrl+3 makes the third tab current"

key ctrl+1
sleep 0.4
assert_eq "$(active_tab_index foot)" 0 "Ctrl+1 goes back to the first tab"
