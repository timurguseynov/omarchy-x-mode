#!/usr/bin/env bash
# "Ctrl+C as Ctrl+Shift+C": for an app that hosts a terminal the physical Ctrl+C
# goes in shifted, and the app's own Ctrl+Shift+C binding decides what that means
# (in Zed's keymap: the interrupt), while Super+C keeps arriving as Ctrl+C
# through Omarchy's universal clipboard and copies.
#
# The bind is global, so the other half matters just as much: an app without the
# flag has to keep getting plain Ctrl+C. The shell below leaves a file when it
# takes SIGINT, so a missing file would mean the key never arrived.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"
MARKER="$NEST_STATE/ctrl-c-int"

ours() { bind_count_desc "Shift Ctrl+C" 4; }

printf '%s\n' '{"options":{},"apps":{}}' > "$SETTINGS"
refresh_apps
sleep 0.4
assert_eq "$(ours)" 0 "off: the pack binds nothing"

printf '%s\n' '{"options":{},"apps":{"kitty":{"ctrlCShift":true}}}' > "$SETTINGS"
refresh_apps
sleep 0.4
assert_eq "$(ours)" 1 "on: the pack takes Ctrl+C"

rm -f "$MARKER"
open_command foot foot sh -c "trap 'touch $MARKER' INT; while true; do sleep 1; done"
sleep 0.6
key ctrl+c
for _ in $(seq 1 20); do
  [ -f "$MARKER" ] && break
  sleep 0.1
done
assert_eq "$([ -f "$MARKER" ] && echo yes || echo no)" yes "an app without the flag still gets Ctrl+C"
