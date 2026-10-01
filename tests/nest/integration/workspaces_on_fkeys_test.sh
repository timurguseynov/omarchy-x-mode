#!/usr/bin/env bash
# "Workspaces on F1..F10" moves the workspace keys off Super+1..0 and onto
# Super+F1..F10, which frees the digits for "Super works as Ctrl" to take. Off is
# Omarchy's layout: Super+1..0 on the workspaces. The nest does not load
# Omarchy's config, so its workspace binds (written by keycode, code:10 is
# workspace 1) are planted here.
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"

generated_for() { # KEY
  nest_ctl binds -j | python3 -c "
import json, sys
want = ('x-mode-super-ctrl ' + '$1').lower()
print(sum(1 for b in json.load(sys.stdin)
          if (b.get('description') or '').lower() == want and int(b.get('modmask') or 0) == 64))"
}

open_window kitty

for i in 1 2 3; do
  nest_ctl eval "hl.bind('SUPER + code:$((i + 9))', hl.dsp.focus({ workspace = '$i' }))" >/dev/null
done

assert_eq "$(viewed_workspace)" 1 "start on the first workspace"
key super+2
settle
assert_eq "$(viewed_workspace)" 2 "off: Super+2 switches workspace"

printf '%s\n' '{"options":{"workspacesOnFkeys":true},"apps":{"kitty":{"ctrlAsSuper":true}}}' > "$SETTINGS"
# The panel's option path reloads the config; refresh_options is the same code
# without losing the binds planted above, so the unbind is what gets exercised.
nest_ctl eval 'if x_mode and x_mode.refresh_options then x_mode.refresh_options() end' >/dev/null

key super+3
settle
assert_eq "$(viewed_workspace)" 2 "on: the digit no longer switches workspace"

key super+f3
settle
assert_eq "$(viewed_workspace)" 3 "on: Super+F3 switches to workspace 3"

# And the freed digit is what the app gets: the map now plans Ctrl+3 for kitty.
refresh_apps
for _ in $(seq 1 25); do
  [ "$(generated_for 3)" = 1 ] && break
  sleep 0.2
done
assert_eq "$(generated_for 3)" 1 "the freed digit is mapped for the app"
