#!/usr/bin/env bash
# The macOS lock key. Omarchy locks on Ctrl+Cmd+L and keeps its Calculator on
# Ctrl+Cmd+Q; macOS puts Lock Screen on Ctrl+Cmd+Q, so the pack takes that key and
# binds Omarchy's own lock command to it.
#
# Because it replaces something the user may want, it is an option and on by
# default: with it off nothing is unbound, so the reload that applies the option
# brings Omarchy's Calculator back. The nest plants that Calculator bind, so the
# scenario can tell who holds the key.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"

# Ctrl+Cmd is modmask 68 (Super 64 + Control 4).
assert_eq "$(bind_count_desc 'Lock the screen' 68)" 1 "Ctrl+Cmd+Q locks the screen"
assert_eq "$(bind_count_desc 'Calculator' 68)" 0 "and the Calculator key it took is gone"

# Off: the pack leaves the key alone and Omarchy's own binding is back.
printf '%s\n' '{"options":{"lockScreenKey":false},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
wait_until 5 "[ \"$(bind_count_desc 'Calculator' 68)\" = 1 ]" || fail "turning the lock key off did not give Omarchy its Calculator key back"
assert_eq "$(bind_count_desc 'Lock the screen' 68)" 0 "with the option off the lock key is not bound"

# And back on.
printf '%s\n' '{"options":{},"apps":{}}' > "$SETTINGS"
nest_ctl reload >/dev/null
wait_until 5 "[ \"$(bind_count_desc 'Lock the screen' 68)\" = 1 ]" || fail "turning the lock key back on did not bind it"
assert_eq "$(bind_count_desc 'Calculator' 68)" 0 "and the Calculator key is taken again"
