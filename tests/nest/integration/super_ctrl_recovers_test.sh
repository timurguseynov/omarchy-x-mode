#!/usr/bin/env bash
# The Super-as-Ctrl binds are made at runtime, so a config reload throws them away
# and the replan is asynchronous: hyprctl writes the bind table to a file, a timer
# picks it up. If that read never lands -- a busy machine, a second reload -- the
# map stays empty for the rest of the session and Cmd+Z stops reaching every app,
# with nothing to show for it. The pack has to notice and try again by itself.
#
# The failure is injected where it happens: the snapshot's destination is a
# directory, so nothing can land there and the read never becomes an answer.
# A directory rather than a blocked temporary path, because the temporary paths
# carry the generation of the attempt that owns them.
. "$(dirname "$0")/../../lib.sh"

STATE="$NEST_STATE/state"
TABLE="$STATE/binds.txt"

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

printf '%s\n' '{"options":{"keys":{"ctrlAsSuper":true}},"apps":{}}' > "$NEST_SETTINGS"
nest_ctl eval 'if x_mode and x_mode.refresh_options then x_mode.refresh_options() end' >/dev/null
wait_until 8 '[ "$(generated_all)" -gt 0 ]' || fail "no Super-as-Ctrl binds to begin with"

# Block the write: the reload empties the bind table, and the snapshot that would
# refill it cannot land, because its destination is not a file.
rm -rf "$TABLE"
mkdir -p "$TABLE"
nest_ctl reload >/dev/null
sleep 1.5
assert_eq "$(generated_all)" 0 "the reload with a blocked read leaves no binds"

# The read works again; the trigger is an event the pack already sees.
rm -rf "$TABLE"
open_window foot
wait_until 15 '[ "$(generated_all)" -gt 0 ]' || fail "the Super-as-Ctrl map never came back by itself"
