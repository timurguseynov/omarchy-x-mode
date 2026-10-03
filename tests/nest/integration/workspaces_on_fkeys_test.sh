#!/usr/bin/env bash
# "Workspaces on F1..F10" moves the workspace keys off Super+1..0 and onto
# Super+F1..F10. Off is Omarchy's layout: Super+1..0 on the workspaces. The nest
# does not load Omarchy's config, so its workspace binds (written by keycode,
# code:10 is workspace 1) are planted here.
#
# The freed digit is the pack's own key, not a generated one: it hands Ctrl+digit
# to an app that asked for it and switches the pack's own tab for one that did
# not (integration/digit_tabs_test drives both halves).
. "$(dirname "$0")/../../lib.sh"

SETTINGS="$NEST_SETTINGS"

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

# The freed digit is bound once, by the pack: the generator must not also plan it
# or one press would run both.
assert_eq "$(bind_count_desc_exact "Tab 3, or Ctrl+3 for the app" 64)" 1 "the freed digit is the pack's own key"
assert_eq "$(bind_count 3 64)" 1 "and it is the only bind on the key"
assert_eq "$(bind_count_desc 'x-mode-super-ctrl 3' 64)" 0 "the generator leaves it alone"
