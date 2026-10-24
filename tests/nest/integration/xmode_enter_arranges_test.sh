#!/usr/bin/env bash
# Switching a workspace into xmode has to deal its windows the way the panel
# does when xmode is turned on: one app centred, two or more split left and
# right. The mode change used to restore whatever box each window last had, so
# they came back stacked. A window already on another xmode workspace is not
# part of this deal and must stay where it is.
. "$(dirname "$0")/../../lib.sh"

SCRIPT="$REPO_DIR/hypr/x-mode/xmode"
extent="$(pointer_extent)"
mw="${extent%x*}"
half=$((mw / 2))

xmode() {
  timeout 15 env WAYLAND_DISPLAY="$(nest_display)" XDG_RUNTIME_DIR="$NEST_RUNTIME" \
    HYPRLAND_INSTANCE_SIGNATURE="$SIG" XDG_STATE_HOME="$NEST_STATE/home/.local/state" \
    "$SCRIPT" "$@" 2>/dev/null
}

open_window foot
open_command layoutenter alacritty --class layoutenter
open_window kitty
settle
nest_ctl dispatch "hl.dsp.window.move({ workspace = \"2\", window = 'class:kitty' })" >/dev/null
sleep 0.3
nest_ctl dispatch "hl.dsp.window.move({ x = 40, y = 80, relative = false, window = 'class:kitty' })" >/dev/null
nest_ctl dispatch "hl.dsp.window.resize({ x = 320, y = 240, relative = false, window = 'class:kitty' })" >/dev/null
sleep 0.3
nest_ctl dispatch "hl.dsp.focus({ workspace = \"1\" })" >/dev/null
sleep 0.2
kept_before="$(nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == 'kitty':
        print(c['at'][0], c['at'][1], c['size'][0], c['size'][1], c['workspace']['id'])
        break")"

xmode set 1 dwindle
settle
xmode set 1 xmode
settle

read -r fx _ fw _ _ <<<"$(win_geom foot)"
read -r ax _ aw _ _ <<<"$(win_geom layoutenter)"
kept="$(nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == 'kitty':
        print(c['at'][0], c['at'][1], c['size'][0], c['size'][1], c['workspace']['id'])
        break")"

assert_le "$fw" $((half + 40)) "switching to xmode gives each app a half (foot is $fw)"
assert_le "$aw" $((half + 40)) "switching to xmode gives each app a half (the other app is $aw)"
assert_ne "$fx" "$ax" "the two apps land on different sides"
assert_eq "$kept" "$kept_before" "a window on another xmode workspace is not dealt again (got $kept)"
