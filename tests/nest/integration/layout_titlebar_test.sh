#!/usr/bin/env bash
# Clicking the workspace number in the top bar runs Omarchy's layout toggle, not
# Super+L. From an xmode workspace that walks dwindle, then scrolling, then
# floating. Floating is hers: the window stays floating, and it grows her titlebar.
#
# Two things used to go wrong together. Her titlebars module loads a second
# hyprbars (titlebars.so) the moment a workspace starts floating, and that load
# reloads the whole config, so the mode the click just set does not stay put.
# And the pack's own plugin, which is already the hyprbars she is configuring,
# only draws a bar for the xmode tag, so her floating windows get no titlebar
# while the reload rearranges everything else.
. "$(dirname "$0")/../../lib.sh"

APP=layoutbar

toggle() {
  timeout 20 env WAYLAND_DISPLAY="$(nest_display)" XDG_RUNTIME_DIR="$NEST_RUNTIME" \
    HYPRLAND_INSTANCE_SIGNATURE="$SIG" XDG_STATE_HOME="$NEST_STATE/home/.local/state" \
    omarchy-hyprland-workspace-layout-toggle >/dev/null 2>&1
}

# What the pack itself thinks. hyprctl eval only answers "ok".
pack_mode() {
  local out="/tmp/xmode-layout-bar-$$"
  rm -f "$out"
  nest_ctl eval "if x_mode and x_mode.mode then hl.exec_cmd(\"sh -c 'echo \" .. tostring(x_mode.mode(1)) .. \" > $out'\") end" >/dev/null
  local _
  for _ in $(seq 1 30); do
    [ -f "$out" ] && break
    sleep 0.05
  done
  cat "$out" 2>/dev/null
  rm -f "$out"
}

floating() {
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$1' and c['mapped'] and not c['hidden']:
        print('yes' if c['floating'] else 'no')
        break"
}

tags_of() {
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$1' and c['mapped'] and not c['hidden']:
        print(' '.join(c.get('tags') or []))
        break"
}

plugins() { nest_ctl plugin list; }

diagnose() {
  {
    echo "  diag: mode=$(pack_mode) floating=$(floating "$APP") height=$(bar_height)"
    echo "  diag: tags=$(tags_of "$APP")"
    echo "  diag: plugins:"
    plugins | sed 's/^/    /'
    echo "  diag: clients:"
    nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    print('   ', c['class'], c['at'], 'floating', c['floating'], 'tags', c.get('tags'))
"
  } >&2
}

eq() {
  [ "$1" = "$2" ] || { diagnose; fail "${3:-expected '$2', got '$1'}"; }
}

# The band directly above the window box, where a titlebar is drawn, against the
# same pixels with the window parked out of the way. A missing bar leaves the
# wallpaper, so the two crops match.
titlebar_diff() {
  local shots="$NEST_STATE/shots-layout-bar"
  mkdir -p "$shots"
  local scale
  scale="$(nest_ctl monitors -j | python3 -c "import json,sys;print(int(json.load(sys.stdin)[0]['scale']))")"
  local extent mw mh
  extent="$(pointer_extent)"
  mw="${extent%x*}"
  mh="${extent#*x}"

  nest_ctl dispatch "hl.dsp.window.move({ x = $((mw - 30)), y = $((mh - 30)), relative = false, window = 'class:$APP' })" >/dev/null
  settle
  nest_screenshot "$shots/empty.png"

  nest_ctl dispatch "hl.dsp.window.move({ x = 80, y = 220, relative = false, window = 'class:$APP' })" >/dev/null
  settle
  nest_screenshot "$shots/bar.png"

  local x y w
  read -r x y w _ _ <<<"$(win_geom "$APP")"
  [ -n "$w" ] || { echo 0; return; }
  # Where the bar actually is: above the box the compositor settled on, which is
  # not always the coordinate the move asked for.
  local top=$((y - 36))
  [ "$top" -lt 0 ] && top=0
  local band_h=$((36 * scale))
  local bw=$((w * scale))
  local bx=$((x * scale))
  local by=$((top * scale))
  magick "$shots/empty.png" -crop "${bw}x${band_h}+${bx}+${by}" +repage "$shots/empty_band.png"
  magick "$shots/bar.png" -crop "${bw}x${band_h}+${bx}+${by}" +repage "$shots/bar_band.png"
  image_diff "$shots/empty_band.png" "$shots/bar_band.png"
}

open_command "$APP" alacritty --class "$APP"
settle
eq "$(floating "$APP")" yes "the probe starts floating on xmode"

# The bar's click. Three presses: xmode -> dwindle -> scrolling -> floating.
toggle || { diagnose; fail "the layout toggle did not run"; }
settle
eq "$(pack_mode)" dwindle "the first click leaves xmode for dwindle"

toggle || { diagnose; fail "the layout toggle did not run"; }
settle
eq "$(pack_mode)" scrolling "the second click reaches scrolling"

toggle || { diagnose; fail "the layout toggle did not run"; }
settle
eq "$(pack_mode)" floating "the third click reaches floating"
eq "$(floating "$APP")" yes "on Omarchy's floating layout the window stays floating"

# A load of titlebars.so reloads the config a moment later and puts the workspace
# back to whatever the files said at that instant. The click has to still be
# there after that.
sleep 1.2
eq "$(pack_mode)" floating "floating survives the moment a second titlebar plugin would reload"
eq "$(floating "$APP")" yes "the window is still floating after that"

if plugins | grep -q 'omarchy-hyprland-titlebars'; then
  diagnose
  fail "Omarchy's titlebars.so was loaded next to the pack's hyprbars"
fi
eq "$(bar_height)" 28 "her titlebar setup does not restyle the pack's bars (height $(bar_height))"

diff="$(titlebar_diff)"
[ "${diff:-0}" -ge 500 ] 2>/dev/null || { diagnose; fail "a floating workspace grows a titlebar above the window (band diff ${diff:-0})"; }

# A window that opens afterwards is hers too. The pack's catch-all float rule
# used to hand it straight back to tiling, so the titlebar had nothing to sit on.
open_command layoutbar2 alacritty --class layoutbar2
settle
eq "$(floating layoutbar2)" yes "a window opened on the floating workspace stays floating"
