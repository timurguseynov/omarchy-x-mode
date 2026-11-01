#!/usr/bin/env bash
# The layout cycle, end to end: Super+L runs the pack's script, the script writes the
# same workspace-layout files Omarchy's own toggle writes, and the pack (which reads
# those files and wraps o.workspace_mode) takes the workspace over on xmode and steps
# aside on the rest.
#
# Four modes in one ring: dwindle -> scrolling -> floating -> xmode -> dwindle.
#
# The mode is read and written through the script, which is the interface the bar and
# the user have: "the mode" is the saved one (the file, then the default), the same
# rule Omarchy's own current-layout script plays by. Reading it out of the pack's Lua
# state instead was both slower and unreliable in a nest.
. "$(dirname "$0")/../../lib.sh"

SCRIPT="$REPO_DIR/hypr/x-mode/xmode"
xmode() { # ARGS...
  timeout 15 env WAYLAND_DISPLAY="$(nest_display)" XDG_RUNTIME_DIR="$NEST_RUNTIME" \
    HYPRLAND_INSTANCE_SIGNATURE="$SIG" XDG_STATE_HOME="$NEST_STATE/home/.local/state" \
    "$SCRIPT" "$@" 2>/dev/null
}
mode() { xmode current 1; }

floating() {
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == 'xmodeprobe' and c['mapped'] and not c['hidden']:
        print('yes' if c['floating'] else 'no')
        break"
}

open_command xmodeprobe alacritty --class xmodeprobe
settle
xmode set 1 dwindle
assert_eq "$(mode)" dwindle "the cycle starts from dwindle"

# A press runs exec -> the script -> o.workspace_mode, so the step is waited for
# rather than slept through. The condition is a function: a $(...) inside a
# wait_until argument is expanded once, before the wait starts.
step_mode=""
mode_is() { [ "$(mode)" = "$step_mode" ]; }
step() { # KEY EXPECTED WHAT
  key "$1"
  step_mode="$2"
  wait_until 15 mode_is || fail "$3 (mode is $(mode))"
}

step super+l scrolling "Super+L steps dwindle -> scrolling"
step super+l floating "Super+L steps scrolling -> floating"
step super+l xmode "Super+L steps floating -> xmode, the pack's own mode"
settle
assert_eq "$(floating)" yes "and the pack floats the window there"
step super+l dwindle "and wraps back to dwindle"

# The other direction walks the same ring backwards.
step super+alt+l xmode "Super+Alt+L steps back into xmode"
step super+alt+l floating "Super+Alt+L steps back to floating"

# What the bar, the current-layout script and the next login read is the saved mode.
# xmode is this nest's default, and a workspace on the default keeps no file of its
# own -- the same rule Omarchy's toggle follows, so a later change of the default
# reaches it too.
step super+l xmode "back to xmode for the saved-mode check"
assert_eq "$(xmode default)" xmode "xmode is the default here"
[ ! -f "$NEST_STATE/home/.local/state/omarchy/workspace-layouts/1.lua" ] \
  || fail "a workspace on the default layout kept a file of its own: $(cat "$NEST_STATE/home/.local/state/omarchy/workspace-layouts/1.lua")"
