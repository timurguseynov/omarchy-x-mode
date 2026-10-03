#!/usr/bin/env bash
# The main panel can force a keyboard replacement on for every app.
#
# The flag lives in options.keys, not in any app entry, so the handlers have to
# treat every class as having it -- including one that has never been configured.
# The card shows such a row as set and locked, and this drives the engine half:
# the generated Super-as-Ctrl binds must exist with no per-app flag anywhere, and
# a globally stolen occupied key must reach an unflagged app as Ctrl+key.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"
CAP="$NEST_STATE/global-keys.out"
received() { od -An -v -tx1 "$1" 2>/dev/null | tr -s ' \n' ' ' | sed 's/^ //;s/ $//'; }
generated() { [ "$(bind_count_desc 'x-mode-super-ctrl T' 64)" = 1 ]; }

# Nothing per app: both overrides are in the options block. refresh_options is the
# panel's option path without a reload. The condition has to be a function: a
# `$(...)` in a wait_until argument is expanded once, before the wait starts.
printf '%s\n' '{"options":{"keys":{"ctrlAsSuper":true,"steal":["Q"]}},"apps":{}}' > "$SETTINGS"
nest_ctl eval 'if x_mode and x_mode.refresh_options then x_mode.refresh_options() end' >/dev/null
wait_until 5 generated || fail "the global flag did not generate a Super-as-Ctrl bind"

open_command footgcap foot -a footgcap sh -c "stty raw -echo; cat > '$CAP'"
wait_until 3 [ -e "$CAP" ] || fail "the capture window did not open its file"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:footgcap' })" >/dev/null
sleep 0.3

# Ctrl+T is 0x14. The file accumulates, so each press checks what it added.
key ctrl+t
sleep 0.4
assert_eq "$(received "$CAP")" "14" "a physical Ctrl+T hands the terminal 0x14"

key super+t
sleep 0.5
assert_eq "$(received "$CAP")" "14 14" "a global Ctrl-works-as-Ctrl hands the app the chord"

key super+q
sleep 0.5
assert_eq "$(received "$CAP")" "14 14 11" "a globally stolen Super+Q goes over as Ctrl+Q"
assert_eq "$(count_class footgcap)" 1 "and the app is not closed by it"
