#!/usr/bin/env bash
# The one link in Super-as-Ctrl that no scenario checked: does the key actually
# arrive at the client as Ctrl+key? The map can be installed (ctrl_as_super_test),
# the hold-repeat can work (super_ctrl_hold_test), and the press can still reach the
# app as a bare Super chord -- which every app ignores -- or not at all.
#
# The app is a pty dumping what it receives, like the text-chord scenarios, so the
# assertion is on the bytes the client got, not on the pack's own report.
. "$(dirname "$0")/../../lib.sh"

CAP="$NEST_STATE/ctrl-as-super.out"

# The flag is per app; a terminal would otherwise get readline chords instead.
printf '%s\n' '{"options":{"keys":{"ctrlAsSuper":true}},"apps":{"foot":{"ctrlAsSuper":true,"chrome":true}}}' > "$NEST_SETTINGS"
nest_ctl eval 'if x_mode and x_mode.refresh_options then x_mode.refresh_options() end' >/dev/null
wait_until 8 '[ "$(bind_count_desc x-mode-super-ctrl 64)" -gt 0 ]' ||
  fail "no Super-as-Ctrl binds to press (super-ctrl.json: $(cat "$NEST_STATE/state/super-ctrl.json" 2>/dev/null || echo none), flag: $(cat "$NEST_SETTINGS"))"

received() { od -An -v -tx1 "$CAP" 2>/dev/null | tr -s ' \n' ' ' | sed 's/^ //;s/ $//'; }

rm -f "$CAP"
open_command footcap foot -a footcap sh -c "stty raw -echo; cat > '$CAP'"
nest_ctl dispatch "hl.dsp.focus({ window = 'class:footcap' })" >/dev/null
settle

# The reconciliation has to agree with the real table, not just with a synthetically
# built one: a parser that reads `hyprctl binds` wrongly would look "degraded"
# forever and rebuild the map every five seconds, which shows up here as churn.
state_of() {
  python3 -c "
import json
try:
    print(json.load(open('$NEST_STATE/state/super-ctrl.json')).get('state', 'none'))
except Exception:
    print('none')"
}
wait_until 20 '[ "$(state_of)" = "verified" ]' ||
  fail "the reconciliation never agreed with the live table (state: $(state_of), file: $(cat "$NEST_STATE/state/super-ctrl.json" 2>/dev/null))"

key super+r
sleep 0.5

got="$(received)"
# Ctrl+R is 0x12, exactly once: a bare "r" (0x72) would mean the Super chord went
# through untouched, nothing at all would mean the key was swallowed, and two 0x12
# would mean the map was installed twice.
r12="$(printf '%s' "$got" | tr ' ' '\n' | grep -cx '12' || true)"
case " $got " in
  *" 72 "*) fail "the client received a bare 'r': the Super chord was not translated (bytes: '$got')" ;;
  *) ;;
esac
assert_eq "$r12" 1 "the client receives Ctrl+R exactly once (bytes: '$got')"
case " $got " in
  *" 72 "*) fail "the client received a bare 'r': the Super chord was not translated (bytes: '$got')" ;;
  *) ;;
esac
