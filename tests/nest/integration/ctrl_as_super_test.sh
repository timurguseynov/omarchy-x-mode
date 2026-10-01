#!/usr/bin/env bash
# "Super works as Ctrl" is generated from the desktop's own bind table: every
# Super+key nothing else uses is rebound to send the app Ctrl+key. The read is
# out of band (hyprctl writes the table, a timer picks it up), so the check waits
# for the binds to land. A key another bind already owns is left alone, and an
# app without the flag changes nothing.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_STATE/state/settings.json"

# Modmask 64 is Super alone, 65 is Super+Shift (eKeyboardModifiers). Matching on
# the whole description: a substring match would count LEFT for L, BACKSPACE for
# B.
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

generated_for() { # KEY
  nest_ctl binds -j | python3 -c "
import json, sys
want = ('x-mode-super-ctrl ' + '$1').lower()
print(sum(1 for b in json.load(sys.stdin)
          if (b.get('description') or '').lower() == want and int(b.get('modmask') or 0) == 64))"
}

has_generated() { [ "$(generated_all)" -gt 0 ]; }

# Start from off: a failed earlier attempt on this nest would leave its binds.
printf '%s\n' '{"options":{},"apps":{}}' > "$SETTINGS"
refresh_apps
sleep 0.6
assert_eq "$(generated_all)" 0 "no binds until an app asks for Super as Ctrl"

# A key some other bind already owns must be left alone. B is free in the nest
# and in Omarchy, so plant it: the plan reads the live bind table.
nest_ctl eval 'hl.bind("SUPER + B", hl.dsp.no_op())' >/dev/null

printf '%s\n' '{"options":{},"apps":{"kitty":{"ctrlAsSuper":true}}}' > "$SETTINGS"
refresh_apps
wait_until 5 has_generated || fail "Super works as Ctrl generated no binds"

assert_eq "$(generated_for L)" 1 "a free key is mapped"
assert_eq "$(generated_for W)" 0 "the pack's own Super+W is left alone"
assert_eq "$(generated_for TAB)" 0 "the pack's own Super+Tab is left alone"
assert_eq "$(generated_for B)" 0 "a key another bind already owns is left alone"

printf '%s\n' '{"options":{},"apps":{}}' > "$SETTINGS"
refresh_apps
sleep 0.6
assert_eq "$(generated_all)" 0 "turning the flag off removes the binds"
