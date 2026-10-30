#!/usr/bin/env bash
# A config reload rebuilds Hyprland's bind table, and the Super-as-Ctrl binds are
# made at runtime from Lua -- they are gone when the reload finishes, so the pack
# has to put them back on its own. When that replan does not land, ⌘Z and the rest
# silently stop reaching the app while super-ctrl.json still reports a healthy
# plan: the file is written only by a plan that ran, so a dropped-and-not-rebound
# session keeps the last good numbers.
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

# The desktop-wide flag lives in the options block, which is what refresh_options
# re-reads; refresh_apps only re-reads the app cards.
printf '%s\n' '{"options":{"keys":{"ctrlAsSuper":true}},"apps":{}}' > "$SETTINGS"
nest_ctl eval 'if x_mode and x_mode.refresh_options then x_mode.refresh_options() end' >/dev/null
wait_until 8 '[ "$(generated_all)" -gt 0 ]' || fail "no Super-as-Ctrl binds before the reload"
before="$(generated_all)"

nest_ctl reload >/dev/null
sleep 0.4
wait_until 8 '[ "$(generated_all)" -ge "$before" ]' ||
  fail "the reload left Super-as-Ctrl at $(generated_all) of $before binds"
