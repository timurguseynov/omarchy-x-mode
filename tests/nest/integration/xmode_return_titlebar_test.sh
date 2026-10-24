#!/usr/bin/env bash
# Leaving xmode and coming back is a different path from the first load. The
# mode file and the bar glyph follow the script either way; the dock and the
# titlebar have to come back with them. Coming from Omarchy's floating mode is
# the sharp case: she has her own tags and she sets the workspace layout to
# whatever name she was given, including "xmode", which is not a layout.
. "$(dirname "$0")/../../lib.sh"

APP=xreturn
SCRIPT="$REPO_DIR/hypr/x-mode/xmode"
MODE_FILE="$NEST_RUNTIME/omarchy-x-mode.workspace"

xmode() {
  timeout 15 env WAYLAND_DISPLAY="$(nest_display)" XDG_RUNTIME_DIR="$NEST_RUNTIME" \
    HYPRLAND_INSTANCE_SIGNATURE="$SIG" XDG_STATE_HOME="$NEST_STATE/home/.local/state" \
    "$SCRIPT" "$@" 2>/dev/null
}

pack_mode() {
  local out="/tmp/xmode-return-$$"
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

floating() {
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$APP' and c['mapped'] and not c['hidden']:
        print('yes' if c['floating'] else 'no')
        break"
}

tiled_layout() {
  nest_ctl workspaces -j | python3 -c "
import json, sys
for w in json.load(sys.stdin):
    if w.get('id') == 1:
        print(w.get('tiledLayout') or '')
        break"
}

dock_visible() { [ -n "$(dock_layer_box x-mode-dock 2>/dev/null)" ]; }
dock_gone() { [ -z "$(dock_layer_box x-mode-dock 2>/dev/null)" ]; }

dock_start
open_command "$APP" alacritty --class "$APP"
settle
assert_eq "$(count_class "$APP")" 1 "the probe window is open"
wait_until 5 'dock_visible' || fail "the dock is not shown on the starting xmode workspace"

xmode set 1 floating
settle
assert_eq "$(pack_mode)" floating "the workspace leaves xmode for floating"
wait_until 10 'dock_gone' || fail "the dock stays up on floating (mode file: $(cat "$MODE_FILE" 2>/dev/null))"

xmode set 1 xmode
settle
assert_eq "$(pack_mode)" xmode "the workspace comes back to xmode"
assert_eq "$(cat "$MODE_FILE" 2>/dev/null | awk '{print $2}')" xmode \
  "the dock's mode file comes back to xmode"
assert_eq "$(floating "$APP")" yes "the window is floating again"
assert_eq "$(tagged "$APP")" yes "the window has the pack's titlebar tag again"
assert_eq "$(tiled_layout)" dwindle "xmode does not stick Hyprland with a layout named xmode (got '$(tiled_layout)')"
wait_until 10 'dock_visible' || fail "the dock did not come back with xmode (mode file: $(cat "$MODE_FILE" 2>/dev/null))"

dock_stop
