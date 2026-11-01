#!/usr/bin/env bash
# The Super-as-Ctrl binds are made at runtime, so a config reload throws them away
# and the replan is asynchronous: hyprctl writes the bind table to a file, a timer
# picks it up. If that read never lands -- a busy machine, a second reload -- the
# map stays empty for the rest of the session and Cmd+Z stops reaching every app,
# with nothing to show for it. The pack has to notice and try again by itself.
#
# The failure is injected where it happens: the exec cannot write its temporary
# file (a directory is in the way), and the table on disk is empty, so the read is
# not an answer.
. "$(dirname "$0")/../../lib.sh"

STATE="$NEST_STATE/state"
TABLE="$STATE/binds.txt"
TMP="$STATE/binds.txt.tmp"

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

# Block the write and leave an empty table: the reload empties the bind table, and
# the read that would refill it cannot land.
rm -rf "$TMP"
mkdir -p "$TMP"
: > "$TABLE"
nest_ctl reload >/dev/null
sleep 1.5
assert_eq "$(generated_all)" 0 "the reload with a blocked read leaves no binds"

# The read works again; the trigger is an event the pack already sees.
rmdir "$TMP"
open_window foot
wait_until 15 '[ "$(generated_all)" -gt 0 ]' || fail "the Super-as-Ctrl map never came back by itself"
