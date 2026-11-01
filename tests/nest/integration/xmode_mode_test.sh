#!/usr/bin/env bash
# xmode is a workspace mode, not a property of the whole desktop. On a workspace
# in xmode the pack owns the window: it floats, it places, it tabs. Every other
# mode belongs to Omarchy -- dwindle and scrolling tile, floating is Omarchy's own
# floating with its own titlebars -- and the pack steps aside there instead of
# floating everything the way it used to.
#
# The nest starts with xmode as the default mode (tests/nest.lua), so the first
# half of this checks the pack's own desktop, and switching the workspace to
# dwindle has to take the pack's floating away from it.
#
# Its own app id, not `foot`: a scenario that runs after one which leaves foot
# windows behind must not be counted into that class, or the check below reads a
# window this scenario never opened. alacritty takes the app id by --class, and it
# stays up in a nest that has already run a scenario -- `foot --app-id=...` exited
# within a few hundred ms there, which this scenario then saw as "no window".
. "$(dirname "$0")/../../lib.sh"

APP=xmodeprobe

# What the pack put the window in: a client on an xmode workspace floats, and one
# on a tiled workspace does not.
floating() { # CLASS
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$1' and c['mapped'] and not c['hidden']:
        print('yes' if c['floating'] else 'no')
        break"
}

diagnose() {
  {
    echo "  diag: clients:"
    nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    print('   ', c['class'], c['at'], c['size'], 'floating', c['floating'], 'mapped', c['mapped'],
          'hidden', c['hidden'], 'grouped', len(c.get('grouped') or []), 'tags', c.get('tags'))
"
    echo "  diag: mode files:"
    ls -1 "$NEST_STATE/home/.local/state/omarchy/workspace-layouts/" 2>&1 | sed 's/^/    /'
    echo "  diag: the pack says workspace 1 = $(pack_mode 1)"
  } >&2
}

# What the pack itself thinks: asked through a file, because hyprctl eval only
# answers "ok".
pack_mode() { # WORKSPACE
  local out="/tmp/xmode-diag-$$"
  rm -f "$out"
  nest_ctl eval "if x_mode and x_mode.mode then hl.exec_cmd(\"sh -c 'echo \" .. tostring(x_mode.mode($1)) .. \" > $out'\") end" >/dev/null
  for _ in $(seq 1 20); do
    [ -f "$out" ] && break
    sleep 0.05
  done
  cat "$out" 2>/dev/null
  rm -f "$out"
}

extent="$(pointer_extent)"
mw="${extent%x*}"
wide=$((mw * 9 / 10))

open_command "$APP" alacritty --class "$APP"
settle
# Two questions, two messages: the window existing is the fixture's, floating is the
# pack's. Told apart here, a failure names the half it belongs to instead of
# blaming the mode for a probe that never opened.
assert_eq "$(count_class "$APP")" 1 "the probe window is open"
[ "$(floating "$APP")" = yes ] || diagnose
assert_eq "$(floating "$APP")" yes "on an xmode workspace the window floats"

# The same workspace in dwindle: Omarchy tiles, so the window fills the width and
# is not floating.
nest_ctl eval 'o.workspace_mode({ workspace = "1", mode = "dwindle" })' >/dev/null
settle
nest_ctl dispatch "hl.dsp.window.close({ window = 'class:$APP' })" >/dev/null
settle
open_command "$APP" alacritty --class "$APP"
settle
[ "$(floating "$APP")" = no ] || diagnose
assert_eq "$(floating "$APP")" no "on a dwindle workspace the pack leaves the window tiled"
read -r _ aty w _ _ <<<"$(win_geom "$APP")"
assert_ge "$w" "$wide" "the tiled window fills the work area"
# No titlebar there: the pack's chrome is drawn only for the windows it claimed,
# so the tiled window's box starts at the top bar's edge and not a bar height
# below it (24px of chrome would put this at about 58).
assert_le "$aty" 45 "the dwindle workspace gets no titlebar (window at y=$aty)"

# Back to xmode: the pack claims the workspace again. The window that is there is
# already open, so this is the load path as well -- Omarchy tiled it, the pack
# has to float it.
nest_ctl eval 'o.workspace_mode({ workspace = "1", mode = "xmode" })' >/dev/null
settle
assert_eq "$(floating "$APP")" yes "switching back to xmode floats the open window"

# The tiling keys are the pack's only here. Super+Alt+Left is the pack's snap on
# an xmode workspace and Omarchy's "move into the group on the left" everywhere
# else, so the same key has to do two different things.
key super+alt+left
wait_still "$APP"
read -r _ _ snapped _ _ <<<"$(win_geom "$APP")"
assert_le "$snapped" "$((mw * 6 / 10))" "in xmode Super+Alt+Left snaps to a half"

nest_ctl eval 'o.workspace_mode({ workspace = "1", mode = "dwindle" })' >/dev/null
settle
read -r _ _ tiled _ _ <<<"$(win_geom "$APP")"
key super+alt+left
sleep 0.4
read -r _ _ after _ _ <<<"$(win_geom "$APP")"
assert_eq "$after" "$tiled" "on a dwindle workspace that key is Omarchy's, not the pack's snap"
