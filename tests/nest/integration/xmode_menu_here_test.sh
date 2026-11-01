#!/usr/bin/env bash
# The Workspace Layout menu's X Mode row used to set only the default. A
# workspace that already had its own mode (the one on screen, after a cycle)
# stayed there, so the checkmark moved and the titlebar did not. `xmode here`
# is that row's other half: the workspace that is showing becomes xmode.
. "$(dirname "$0")/../../lib.sh"

APP=xmenu
SCRIPT="$REPO_DIR/hypr/x-mode/xmode"

xmode() {
  timeout 15 env WAYLAND_DISPLAY="$(nest_display)" XDG_RUNTIME_DIR="$NEST_RUNTIME" \
    HYPRLAND_INSTANCE_SIGNATURE="$SIG" XDG_STATE_HOME="$NEST_STATE/home/.local/state" \
    "$SCRIPT" "$@" 2>/dev/null
}

pack_mode() {
  local out="/tmp/xmode-menu-$$"
  rm -f "$out"
  nest_ctl eval "if x_mode and x_mode.mode then hl.exec_cmd(\"sh -c 'echo \" .. tostring(x_mode.mode(1)) .. \" > $out'\") end" >/dev/null
  for _ in $(seq 1 20); do
    [ -f "$out" ] && break
    sleep 0.05
  done
  cat "$out" 2>/dev/null
  rm -f "$out"
}

tagged() {
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$APP' and c['mapped'] and not c['hidden']:
        tags = [str(t) for t in (c.get('tags') or [])]
        print('yes' if any(t == 'xmode-workspace' or t == 'xmode-workspace*' for t in tags) else 'no')
        break"
}

open_command "$APP" alacritty --class "$APP"
settle
xmode set 1 floating
settle
assert_eq "$(pack_mode)" floating "the workspace is on floating, with a mode of its own"

# What the menu row used to do by itself. The default moves; this workspace does not.
xmode default xmode
settle
assert_eq "$(pack_mode)" floating "setting the default to xmode leaves a workspace that has its own mode"

xmode here || fail "xmode here is the menu row that switches the workspace on screen"
settle
assert_eq "$(pack_mode)" xmode "the menu row puts the workspace on screen into xmode"
assert_eq "$(tagged "$APP")" yes "and the titlebar tag comes with it"
