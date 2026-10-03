#!/usr/bin/env bash
# The macOS capture keys. Cmd+Shift+3/4 and Ctrl+Shift+Cmd+3/4 are screenshots,
# Cmd+Shift+5 the recording key, Cmd+Shift+6 the OCR region read; each runs the
# Omarchy capture command with the mode the Mac key means. The one that writes a
# file is pressed for real -- the command, the freeze picker and grim all have to
# work for the file to appear -- and the rest are pinned by their bind.
#
# Cmd+Shift+3..6 are also Omarchy's window moves, written by keycode, and a bind
# matches on its own spelling: left behind, the keycode form would move the
# window as well as take the screenshot. The nest plants them.
. "$(dirname "$0")/../../lib.sh"

# Super is 64, Control 4, Shift 1: Shift+Cmd is 65, Ctrl+Shift+Cmd is 69.
has_bind() { # KEY MODMASK DESCRIPTION
  nest_ctl binds -j | python3 -c "
import json, sys
n = 0
for b in json.load(sys.stdin):
    if b.get('key') == '$1' and int(b.get('modmask') or 0) == int('$2') and (b.get('description') or '') == '$3':
        n += 1
print(n)"
}

assert_eq "$(has_bind 3 65 "Screenshot the screen")" 1 "Cmd+Shift+3 is a full-screen shot"
assert_eq "$(has_bind 3 69 "Screenshot the screen to clipboard")" 1 "Ctrl+Shift+Cmd+3 copies it"
assert_eq "$(has_bind 4 65 "Screenshot a region")" 1 "Cmd+Shift+4 is a region"
assert_eq "$(has_bind 4 69 "Screenshot a region to clipboard")" 1 "Ctrl+Shift+Cmd+4 copies it"
assert_eq "$(has_bind 5 65 "Screen recording")" 1 "Cmd+Shift+5 is the recording key"
assert_eq "$(has_bind 6 65 "Capture text from a region")" 1 "Cmd+Shift+6 reads the text of a region"

for digit in 3 4 5 6; do
  assert_eq "$(bind_count_desc_exact "Move window to workspace $digit" 65)" 0 "Cmd+Shift+$digit no longer moves the window"
done

SHOTS="$NEST_STATE/home/Pictures"
shots() { find "$SHOTS" -name 'screenshot-*.png' 2>/dev/null | wc -l; }
newest() { find "$SHOTS" -name 'screenshot-*.png' 2>/dev/null | sort | tail -1; }
clear_shots() { rm -f "$SHOTS"/screenshot-*.png; }
wait_shot() { # how many
  for _ in $(seq 1 60); do
    [ "$(shots)" -ge "$1" ] && return 0
    sleep 0.2
  done
}

# grim writes physical pixels while the selection is logical.
mon="$(nest_ctl monitors -j | python3 -c "import json,sys;m=json.load(sys.stdin)[0];s=m.get('scale') or 1;print(int(m['width']/s), int(m['height']/s), int(s))")"
read -r mon_w mon_h scale <<<"$mon"

clear_shots
key super+shift+3
wait_shot 1
assert_ge "$(shots)" 1 "Cmd+Shift+3 saves a screenshot file"

# The plain keys take Omarchy's default processing, which is the branch that
# notifies and offers the editor -- and copies the shot. That copy is what makes
# the branch checkable here: a notification has no shell to reach in the nest.
clip="$(WAYLAND_DISPLAY="$(nest_display)" timeout 5 wl-paste -t image/png 2>/dev/null | head -c 8 | od -An -tx1 | tr -d ' \n')"
assert_eq "$clip" "89504e470d0a1a0a" "Cmd+Shift+3 takes the branch that also copies and notifies"

# Cmd+Shift+4 is the drag: a quarter of the monitor dragged out of its middle
# has to come back as that, scaled. Slurp's rectangle covers both the press and
# the release pixel, so it is one wider and taller than the distance dragged.
clear_shots
x0=$((mon_w / 4))
y0=$((mon_h / 4))
x1=$((mon_w / 2))
y1=$((mon_h / 2))
key super+shift+4
sleep 1.2
pointer_drag "$x0" "$y0" "$x1" "$y1"
wait_shot 1
assert_ge "$(shots)" 1 "Cmd+Shift+4 saves the dragged region"
got="$(magick identify -format '%wx%h' "$(newest)" 2>/dev/null)"
expect_w=$(((x1 - x0 + 1) * scale))
expect_h=$(((y1 - y0 + 1) * scale))
printf '  note: dragged %sx%s logical, shot is %s, monitor %sx%s scale %s\n' "$((x1 - x0))" "$((y1 - y0))" "$got" "$mon_w" "$mon_h" "$scale"
assert_between "${got%x*}" "$((expect_w - 1))" "$((expect_w + 1))" "the region width is what was dragged"
assert_between "${got#*x}" "$((expect_h - 1))" "$((expect_h + 1))" "the region height is what was dragged"

# A picker left open would hold the nest's layer surface for the next scenario.
pkill -x slurp 2>/dev/null || true
