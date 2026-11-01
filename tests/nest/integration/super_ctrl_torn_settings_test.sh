#!/usr/bin/env bash
# A settings file is written by truncating it first, so a read can catch half of
# one. Reading that as "Super as Ctrl is off" used to be harmless only because
# nothing acted on it -- then the plan started dropping the installed binds before
# it looked at the flags, and a torn read in the middle of a panel write took the
# whole map away: Cmd+Z stopped reaching every app, and super-ctrl.json still
# reported the last good plan because only a successful plan rewrote it.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"

generated_all() {
  nest_ctl binds -j | python3 -c "
import json, sys
n = 0
for b in json.load(sys.stdin):
    d = (b.get('description') or '')
    if d.startswith('x-mode-super-ctrl') and int(b.get('modmask') or 0) in (64, 65):
        n += 1
print(n)"
}

printf '%s\n' '{"options":{"keys":{"ctrlAsSuper":true}},"apps":{}}' > "$SETTINGS"
nest_ctl eval 'if x_mode and x_mode.refresh_options then x_mode.refresh_options() end' >/dev/null
wait_until 8 '[ "$(generated_all)" -gt 0 ]' || fail "no Super-as-Ctrl binds to begin with"
before="$(generated_all)"

# Half a settings file, the shape a reader can land on: the flags are not there,
# and neither is a closing brace.
printf '%s' '{"options":{"keys":{"ctrlAsSuper":tr' > "$SETTINGS"
nest_ctl eval 'if x_mode and x_mode.refresh_options then x_mode.refresh_options() end' >/dev/null
sleep 1
after="$(generated_all)"
assert_eq "$after" "$before" "a torn read must not take the Super-as-Ctrl map away"

# And the real thing still works: turning it off does drop them.
printf '%s\n' '{"options":{"keys":{"ctrlAsSuper":false}},"apps":{}}' > "$SETTINGS"
nest_ctl eval 'if x_mode and x_mode.refresh_options then x_mode.refresh_options() end' >/dev/null
wait_until 6 '[ "$(generated_all)" = 0 ]' || fail "turning it off left $(generated_all) binds"
