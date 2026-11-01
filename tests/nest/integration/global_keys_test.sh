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
# What the pack itself reports after a plan (super-ctrl.json, written next to the
# occupied list). The bind table is the nest's most contended socket -- the
# compositor, the harness's IPC proxy and the pack's own read all use it -- and
# asking it twenty times a second was starving the read it was waiting for. This
# file is the plan's output, which is what the flag is supposed to produce.
generated() {
  local f="$NEST_STATE/state/super-ctrl.json"
  [ -f "$f" ] || return 1
  python3 -c "
import json, sys
try:
    d = json.load(open('$f'))
except Exception:
    sys.exit(1)
sys.exit(0 if d.get('bound', 0) > 0 else 1)"
}

# Nothing per app: both overrides are in the options block. refresh_options is the
# panel's option path without a reload. The condition has to be a function: a
# `$(...)` in a wait_until argument is expanded once, before the wait starts.
printf '%s\n' '{"options":{"keys":{"ctrlAsSuper":true,"steal":["Q"]}},"apps":{}}' > "$SETTINGS"
# The plan reads the bind table through hyprctl on a timer -- it cannot block the
# parse on its own IPC -- and the table is several hundred lines. Asking once and
# waiting is what made this a race: measured in a nest under a full suite, the
# read has landed only after the wait was over. Asking again is what the panel and
# a reload do, so the wait is spent on the real path.
kick() { nest_ctl eval 'if x_mode and x_mode.refresh_options then x_mode.refresh_options() end' >/dev/null; }
# The plan reads the bind table with `hyprctl`, out of band, and in a nest that
# reads the same socket the harness itself serves: measured there, the read has
# landed seconds after it was asked for, sometimes tens of seconds. So the wait is
# generous and a second ask is spent before giving up -- a plan that is late is not
# a plan that refused to run (the diag below says which).
# A slow poll, not a busy one: every query goes through the same nest socket the
# pack's own `hyprctl binds` reads from, and polling it twenty times a second was
# starving the very read being waited for (the binds turned up as soon as the
# polling stopped, which is what a two-second poll spends its time allowing).
kick
wait_until 20 generated || { kick; wait_until 20 generated; }

if ! generated; then
  {
    echo "  diag: super-ctrl.json: $(cat "$NEST_STATE/state/super-ctrl.json" 2>/dev/null || echo none)"
    echo "  diag: generated binds: $(nest_ctl binds -j | python3 -c "
import json, sys
bs = json.load(sys.stdin)
print(sum(1 for b in bs if 'x-mode-super-ctrl' in (b.get('description') or '')))")"
    echo "  diag: binds.txt lines: $(wc -l < "$NEST_STATE/state/binds.txt" 2>/dev/null || echo none)"
    echo "  diag: settings: $(cat "$SETTINGS")"
    echo "  diag: binds on B: $(nest_ctl binds -j | python3 -c "
import json, sys
print([(b.get('key'), b.get('modmask'), b.get('description')) for b in json.load(sys.stdin) if b.get('key') == 'B'])")"
  } >&2
  fail "the global flag did not generate a Super-as-Ctrl bind"
fi

open_command footgcap foot -a footgcap sh -c "stty raw -echo; cat > '$CAP'"
wait_until 3 '[ -e "$CAP" ]' || fail "the capture window did not open its file"
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
