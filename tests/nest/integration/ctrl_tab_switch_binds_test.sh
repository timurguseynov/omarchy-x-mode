#!/usr/bin/env bash
# Ctrl+1..9 switches group tabs, and it is off by default: the panel writes the
# option and reloads. Control's modifier mask is 4.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_STATE/state/settings.json"

assert_eq "$(bind_count_desc 'Switch to tab 1' 4)" 0 "Ctrl+1 is unbound by default"
assert_eq "$(bind_count_desc 'Switch to tab 9' 4)" 0 "Ctrl+9 is unbound by default"

printf '%s\n' '{"options":{"ctrlTabSwitch":true},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6

assert_ge "$(bind_count_desc 'Switch to tab 1' 4)" 1 "Ctrl+1 is bound once the option is on"
assert_ge "$(bind_count_desc 'Switch to tab 9' 4)" 1 "Ctrl+9 is bound once the option is on"

printf '%s\n' '{"options":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
sleep 0.6
