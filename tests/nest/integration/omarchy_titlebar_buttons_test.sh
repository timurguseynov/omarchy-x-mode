#!/usr/bin/env bash
# Omarchy's floating titlebar buttons close, maximize and minimize by a shell
# command that names the window as %WINDOW%. The pack runs that command, and
# the placeholder has to be the window's address: left as written, hyprctl is
# asked for a window that does not exist and none of the three does anything.
# Maximize has a second catch: the pack used to drop Hyprland's maximized mode
# on every window, so her fullscreen button set the mode and lost it at once.
. "$(dirname "$0")/../../lib.sh"

APP=omarchybtns
APP2=omarchybtns2
SCRIPT="$REPO_DIR/hypr/x-mode/xmode"

xmode() {
  timeout 15 env WAYLAND_DISPLAY="$(nest_display)" XDG_RUNTIME_DIR="$NEST_RUNTIME" \
    HYPRLAND_INSTANCE_SIGNATURE="$SIG" XDG_STATE_HOME="$NEST_STATE/home/.local/state" \
    "$SCRIPT" "$@" 2>/dev/null
}

# Her buttons are on the right of a 30px bar, added close, then fullscreen,
# then minimize. Padding 10, gap 8, size 20: the centres are 28, 56 and 84px
# in from the right edge, and 15px above the window box.
click_button() { # close|full|min
  local inset
  case "$1" in
    close) inset=28 ;;
    full) inset=56 ;;
    min) inset=84 ;;
    *) fail "no such titlebar button: $1" ;;
  esac
  local xy
  xy="$(nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$2' and c.get('mapped') and not c.get('hidden'):
        x, y = c['at']
        w, _ = c['size']
        print(int(x) + int(w) - $inset, int(y) - 15)
        break
")"
  [ -n "$xy" ] || fail "no window to click ($2)"
  pointer_click $xy
}

field() { # class key
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$1' and c.get('mapped'):
        print(c.get('$2'))
        break
"
}

open_command "$APP" alacritty --class "$APP"
settle
xmode set 1 floating
settle
assert_eq "$(field "$APP" floating)" True "the window is floating, where her buttons are drawn"

# Her own placement centres the window, so the titlebar can sit under the
# nest's bar. The three buttons are the rightmost part of that bar, and the
# dock covers the right edge: a click there never reaches them. Park the
# window on the left, clear of both.
nest_ctl dispatch "hl.dsp.window.resize({ x = 520, y = 360, relative = false, window = 'class:$APP' })" >/dev/null
nest_ctl dispatch "hl.dsp.window.move({ x = 40, y = 160, relative = false, window = 'class:$APP' })" >/dev/null
settle

click_button full "$APP"
settle
assert_ne "$(field "$APP" fullscreen)" 0 "the fullscreen button maximizes the window (got $(field "$APP" fullscreen))"

click_button full "$APP"
settle
assert_eq "$(field "$APP" fullscreen)" 0 "the fullscreen button restores the window"

click_button min "$APP"
settle
name="$(nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$APP' and c.get('mapped'):
        print((c.get('workspace') or {}).get('name', ''))
        break
")"
assert_eq "$name" "special:minimized" "the minimize button parks the window (workspace $name)"

open_command "$APP2" alacritty --class "$APP2"
settle
nest_ctl dispatch "hl.dsp.window.resize({ x = 520, y = 360, relative = false, window = 'class:$APP2' })" >/dev/null
nest_ctl dispatch "hl.dsp.window.move({ x = 40, y = 160, relative = false, window = 'class:$APP2' })" >/dev/null
settle
click_button close "$APP2"
settle
gone="$(nest_ctl clients -j | python3 -c "
import json, sys
print('yes' if any(c['class'] == '$APP2' and c.get('mapped') for c in json.load(sys.stdin)) else 'no')
")"
assert_eq "$gone" no "the close button closes the window"
