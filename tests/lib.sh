#!/usr/bin/env bash
# Shared helpers for the x-mode test suite. Source it from a test file or a
# runner; it does not run anything on its own.
#
# The nest is a nested Hyprland (a window inside the real session) running the
# repo's x-mode.lua with its own $X_MODE_STATE, so nothing here touches the live
# session or ~/.local/state.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
NEST_STATE="$TESTS_DIR/.nest"
NEST_LOG="$NEST_STATE/nest.log"
NEST_LUA="$REPO_DIR/hypr/x-mode.lua"
PLUGIN_SO="$REPO_DIR/hyprbars/hyprbars.so"
POINTER_DIR="$TESTS_DIR/pointer"
POINTER_BIN="$NEST_STATE/pointer/pointer"
SIG="${SIG:-$(cat "$TESTS_DIR/.nest/sig" 2>/dev/null || true)}"
NEST_BAR="${NEST_BAR:-1}"

RED=$'\033[31m'; GREEN=$'\033[32m'; RESET=$'\033[0m'

# --- assertions --------------------------------------------------------------

fail() { echo "${RED}FAIL${RESET}: $*" >&2; exit 1; }

assert_eq()      { [ "$1" = "$2" ] || fail "${3:-expected '$2', got '$1'}"; }
assert_ne()      { [ "$1" != "$2" ] || fail "${3:-expected anything but '$2'}"; }
assert_ge()      { [ "$1" -ge "$2" ] 2>/dev/null || fail "${3:-expected >= $2, got '$1'}"; }
assert_le()      { [ "$1" -le "$2" ] 2>/dev/null || fail "${3:-expected <= $2, got '$1'}"; }
assert_between() { [ "$1" -ge "$2" ] && [ "$1" -le "$3" ] || fail "${3:+$4}expected $2..$3, got $1"; }

# --- nest lifecycle ----------------------------------------------------------

build_plugin() {
  local headers
  headers="$(ls -d /var/cache/hyprpm/*/headersRoot 2>/dev/null | head -n1 || true)"
  [ -n "$headers" ] || fail "hyprpm headers not found (run 'hyprpm update')"
  PKG_CONFIG_PATH="$headers/share/pkgconfig" make -C "$REPO_DIR/hyprbars" all >/dev/null 2>&1 \
    || { PKG_CONFIG_PATH="$headers/share/pkgconfig" make -C "$REPO_DIR/hyprbars" all; fail "hyprbars build failed"; }
}

# The pointer injects real input through zwlr_virtual_pointer_manager_v1, so a
# test can drag a titlebar instead of calling the pack's snap function. Built
# into .nest/ so the generated protocol code stays out of the tree.
build_pointer() {
  local out="$NEST_STATE/pointer"
  command -v wayland-scanner >/dev/null || fail "wayland-scanner not found"
  pkg-config --exists wayland-client || fail "wayland-client headers not found"
  mkdir -p "$out"
  wayland-scanner client-header "$POINTER_DIR/wlr-virtual-pointer-unstable-v1.xml" \
    "$out/wlr-virtual-pointer-unstable-v1-client-protocol.h"
  wayland-scanner private-code "$POINTER_DIR/wlr-virtual-pointer-unstable-v1.xml" \
    "$out/wlr-virtual-pointer-unstable-v1-protocol.c"
  # shellcheck disable=SC2046 - pkg-config output is a flag list on purpose
  cc -O2 -Wall -Wextra -I"$out" -o "$POINTER_BIN" "$POINTER_DIR/pointer.c" \
    "$out/wlr-virtual-pointer-unstable-v1-protocol.c" $(pkg-config --cflags --libs wayland-client) \
    || fail "pointer build failed"
}

nest_start() {
  build_plugin
  build_pointer
  nest_stop
  # Start from a clean state dir: a run that fails midway can leave settings.json
  # behind, and the next run would inherit it.
  rm -rf "$NEST_STATE/state" "$NEST_STATE/home"
  mkdir -p "$NEST_STATE/state" "$NEST_STATE/home"

  setsid env \
    HOME="$NEST_STATE/home" \
    X_MODE_LUA="$NEST_LUA" \
    X_MODE_STATE="$NEST_STATE/state" \
    Hyprland -c "$TESTS_DIR/nest.lua" > "$NEST_LOG" 2>&1 < /dev/null &
  local pid=$! i
  for i in $(seq 1 60); do
    SIG="$(hyprctl instances 2>/dev/null | awk -v pid="$pid" '
      /^instance / { n = $2; sub(/:$/, "", n) }
      /pid:/ { if ($2 == pid) print n }')"
    [ -n "$SIG" ] && break
    sleep 0.2
  done
  [ -n "$SIG" ] || { tail -20 "$NEST_LOG" >&2; fail "nest did not come up"; }
  echo "$SIG" > "$NEST_STATE/sig"

  # The config parses before the plugin exists, so its plugin:* keys are unknown
  # on the first pass. Load the plugin and reload once; the second parse is clean.
  nest_ctl plugin load "$PLUGIN_SO" >/dev/null
  nest_ctl reload >/dev/null

  nest_place_window "$pid"

  [ "$NEST_BAR" = 1 ] && nest_bar_start
  return 0
}

nest_bar_start() {
  env WAYLAND_DISPLAY="$(nest_socket)" setsid qs -p "$TESTS_DIR/bar.qml" \
    > "$NEST_STATE/bar.log" 2>&1 < /dev/null &
  echo $! > "$NEST_STATE/bar.pid"
  # Wait for the bar to reserve the top instead of a fixed sleep: the geometry
  # tests are meaningless until the nest reports a reserved top.
  for _ in $(seq 1 40); do
    [ "$(bar_top 2>/dev/null)" -ge 24 ] 2>/dev/null && return 0
    sleep 0.25
  done
  return 0
}

nest_bar_stop() {
  [ -f "$NEST_STATE/bar.pid" ] && kill "$(cat "$NEST_STATE/bar.pid")" 2>/dev/null || true
  rm -f "$NEST_STATE/bar.pid"
  sleep 0.3
}

nest_stop() {
  nest_bar_stop
  pkill -f "Hyprland -c $TESTS_DIR/nest.lua" 2>/dev/null || true
  sleep 0.5
}

# The nest is a toplevel on the host and the host layout can put it off-screen.
nest_place_window() {
  local pid="$1" addr="" i
  for i in $(seq 1 25); do
    addr="$(hyprctl clients -j 2>/dev/null | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c.get('pid') == $pid:
        print(c['address']); break
" || true)"
    [ -n "$addr" ] && break
    sleep 0.2
  done
  [ -n "$addr" ] || return 0
  local w="address:$addr"
  hyprctl dispatch "hl.dsp.window.float({ action = \"enable\", window = \"$w\" })" >/dev/null 2>&1 || true
  hyprctl dispatch "hl.dsp.window.resize({ x = 900, y = 1000, relative = false, window = \"$w\" })" >/dev/null 2>&1 || true
  hyprctl dispatch "hl.dsp.window.move({ x = 40, y = 40, relative = false, window = \"$w\" })" >/dev/null 2>&1 || true
  hyprctl dispatch "hl.dsp.window.alter_zorder({ mode = \"top\", window = \"$w\" })" >/dev/null 2>&1 || true
}

nest_ctl() { hyprctl -i "$SIG" "$@"; }

nest_socket() {
  hyprctl instances 2>/dev/null | python3 -c "
import sys, re
for b in sys.stdin.read().split('instance ')[1:]:
    if '$SIG' in b:
        print(re.search(r'wl socket: (\S+)', b).group(1)); break
"
}

# Close every window in the nest, so each test starts from nothing.
nest_clean() {
  local addrs a
  addrs="$(nest_ctl clients -j | python3 -c "
import json, sys
print(' '.join(c['address'] for c in json.load(sys.stdin)))")"
  for a in $addrs; do
    nest_ctl dispatch "hl.dsp.window.close({ window = 'address:$a' })" >/dev/null 2>&1 || true
  done
  # Settings are written by the panel, and by the tests that drive it. Reset them
  # so a test that fails midway cannot change how the next one lays out windows.
  printf '%s\n' '{"options":{},"apps":{}}' > "$NEST_STATE/state/settings.json"
  nest_ctl reload >/dev/null 2>&1 || true
  sleep 0.4
}

# --- windows -----------------------------------------------------------------

open_window() { # CLASS [COUNT]
  local cls="$1" want="${2:-1}" i
  env WAYLAND_DISPLAY="$(nest_socket)" setsid "$cls" >/dev/null 2>&1 < /dev/null &
  for i in $(seq 1 40); do
    [ "$(count_class "$cls")" -ge "$want" ] && { sleep 0.5; return 0; }
    sleep 0.1
  done
  fail "window '$cls' did not appear"
}

count_class() {
  nest_ctl clients -j | python3 -c "
import json, sys
print(sum(1 for c in json.load(sys.stdin) if c['class'] == '$1' and not c['hidden']))"
}

# "atx aty w h grouped"
win_geom() {
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$1' and c['mapped']:
        print(c['at'][0], c['at'][1], c['size'][0], c['size'][1], len(c.get('grouped') or []))
        break"
}

# Top of the titlebar: at.y minus the chrome (titlebar, plus the tabbar when
# grouped). At/above the bar means it went under it.
visual_top() { # CLASS [CHROME if not the default]
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$1' and c['mapped']:
        grp = len(c.get('grouped') or [])
        print(c['at'][1] - (28 + (24 if grp else 0)))
        break"
}

group_size() { # CLASS
  nest_ctl clients -j | python3 -c "
import json, sys
n = 0
for c in json.load(sys.stdin):
    if c['class'] == '$1' and c['mapped']:
        n = max(n, len(c.get('grouped') or []))
print(n)"
}

active_class() {
  nest_ctl activewindow -j | python3 -c "
import json, sys
d = json.load(sys.stdin) or {}
print(d.get('class') or '')"
}

active_address() {
  nest_ctl activewindow -j | python3 -c "
import json, sys
d = json.load(sys.stdin) or {}
print(d.get('address') or '')"
}

bar_height() { nest_ctl getoption plugin:hyprbars:bar_height | head -1 | awk '{print $2}'; }
tab_height() { nest_ctl getoption plugin:hyprbars:tab_height | head -1 | awk '{print $2}'; }

# Set a plugin:hyprbars:* option at runtime. `hyprctl keyword` refuses plugin
# values ('non-legacy parsers'), so it has to go through the Lua config.
plugin_option() { # NAME LUA_VALUE
  nest_ctl eval "hl.config({ plugin = { hyprbars = { $1 = $2 } } })" >/dev/null
  sleep 0.3
}

# Tab geometry, from CHyprBar::tabAt(): the tabbar is the band directly above
# the window box and one tabbar tall, the + button owns the last 34px of the
# width, and the rest is split evenly between the tabs. A tab's close button is
# the last 24px of that tab.
tab_point() { # CLASS INDEX TABS -> "X Y", the middle of that tab
  _tab_xy "$1" "$2" "$3" "mid"
}

tab_close_point() { # CLASS INDEX TABS -> "X Y", the close button of that tab
  _tab_xy "$1" "$2" "$3" "close"
}

_tab_xy() {
  local bx by bw
  read -r bx by bw _ _ <<<"$(visible_geom "$1")"
  # int(), not round(): the close button is the last 24px of the tab, so a point
  # rounded up past the tab's edge belongs to the next tab.
  python3 -c "
import math
bx, by, bw, i, n, th, where = $bx, $by, $bw, $2, $3, $(tab_height), '$4'
tabw = (bw - 34) / n
x = bx + i * tabw + (tabw - 12 if where == 'close' else tabw / 2)
print(math.floor(x), math.floor(by - th / 2))"
}

plus_point() { # CLASS -> "X Y", the + button on the tabbar
  local bx by bw
  read -r bx by bw _ _ <<<"$(visible_geom "$1")"
  python3 -c "print(round($bx + $bw - 17), round($by - $(tab_height) / 2))"
}

# Index of the current tab, in tab order. Taken from the active window: both
# members of a group report hidden:false in hyprctl, so "the visible one" is not
# something this can lean on.
active_tab_index() { # CLASS
  local addr
  addr="$(active_address)"
  local order
  order="$(group_order "$1")"
  python3 -c "
addr, order = '$addr', '$order'.split()
print(order.index(addr) if addr in order else 0)"
}

# The group's member addresses, in tab order, as one line.
group_order() { # CLASS
  nest_ctl clients -j | python3 -c "
import json, sys
best = []
for c in json.load(sys.stdin):
    if c['class'] == '$1' and c['mapped']:
        members = c.get('grouped') or []
        if len(members) > len(best):
            best = members
print(' '.join(best))"
}

# Like win_geom, but skips the hidden tabs of a group: an inactive tab stays
# mapped, and its box is not the one on screen, so win_geom can report a window
# nobody can see.
visible_geom() { # CLASS
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$1' and c['mapped'] and not c['hidden']:
        print(c['at'][0], c['at'][1], c['size'][0], c['size'][1], len(c.get('grouped') or []))
        break"
}

# Switch a group to tab INDEX (1-based), the dispatcher the pack's Ctrl+N uses.
group_tab() { # INDEX CLASS
  nest_ctl dispatch "hl.dsp.group.active({ index = $1, window = 'class:$2' })" >/dev/null
  sleep 0.2
}

# Class of the topmost visible window. `hyprctl clients -j` is in z-order, with
# the topmost last.
topmost() {
  nest_ctl clients -j | python3 -c "
import json, sys
ws = [c for c in json.load(sys.stdin) if c['mapped'] and not c['hidden']]
print(ws[-1]['class'] if ws else '')"
}

# Snap the first floating window of CLASS to KIND (left/right/maximize/...).
snap() { # CLASS KIND
  nest_ctl eval "for _,w in ipairs(hl.get_windows()) do
    if w.class == '$1' and w.floating and not w.hidden then
      hl.plugin.hyprbars.snap({ kind = '$2', window = w }); break
    end
  end" >/dev/null
  sleep 0.3
}

bar_top() {
  nest_ctl monitors -j | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['reserved'][1])"
}

# --- pointer -----------------------------------------------------------------

# Logical monitor size: warpAbsolute normalises against it, and window geometry
# from hyprctl is logical too, so both sides of the ratio must use the same unit.
pointer_extent() {
  nest_ctl monitors -j | python3 -c "
import json, sys
monitors = json.load(sys.stdin)
m = next((x for x in monitors if x.get('focused')), monitors[0])
scale = m.get('scale') or 1
print(f\"{round(m['width'] / scale)}x{round(m['height'] / scale)}\")"
}

pointer() {
  WAYLAND_DISPLAY="$(nest_socket)" X_MODE_POINTER_EXTENT="$(pointer_extent)" \
    "$POINTER_BIN" "$@"
}

pointer_move() { pointer move "$1" "$2"; }
pointer_click() { pointer click "$1" "$2" "${3:-left}"; }
pointer_drag() { pointer drag "$1" "$2" "$3" "$4" "${5:-left}"; }
pointer_press() { pointer button "${1:-left}" press; }
pointer_release() { pointer button "${1:-left}" release; }

# A gesture that has to pause in the middle (open a window, read geometry) needs
# the button to stay down across commands. A process per command cannot do that:
# the virtual pointer dies with the process and takes the held button with it. So
# those scenarios drive one long-lived `pointer hold` instead.
#
#   pointer_begin
#   pointer_do "move 100 100"
#   pointer_do "press left"
#   ... read geometry ...
#   pointer_do "release left"
#   pointer_end
pointer_begin() {
  coproc POINTER_HOLD { pointer hold; }
  trap pointer_end EXIT
  pointer_do "sleep 0"
}

pointer_do() {
  printf '%s\n' "$1" >&"${POINTER_HOLD[1]}"
  read -r -u "${POINTER_HOLD[0]}" _ || true
}

pointer_end() {
  [ -n "${POINTER_HOLD_PID:-}" ] || return 0
  printf 'exit\n' >&"${POINTER_HOLD[1]}" 2>/dev/null || true
  wait "$POINTER_HOLD_PID" 2>/dev/null || true
  POINTER_HOLD_PID=""
}

# Grab CLASS by its titlebar and let go at (X, Y): the gesture a user makes to
# snap a window, rather than a call to the pack's snap function.
drag_to() { # CLASS X Y
  local tx ty
  read -r tx ty <<<"$(titlebar_point "$1")"
  pointer_drag "$tx" "$ty" "$2" "$3"
  sleep 0.3
}

# Park a window at a fraction of the monitor (percent), so two windows do not
# overlap and a click has one answer. Fractions, not pixels: the nest is a host
# window, so its logical size follows the host scale.
place_frac() { # CLASS FX FY FW FH
  local extent mw mh
  extent="$(pointer_extent)"
  mw="${extent%x*}"
  mh="${extent#*x}"
  nest_ctl dispatch "hl.dsp.window.move({ x = $((mw * $2 / 100)), y = $((mh * $3 / 100)), relative = false, window = 'class:$1' })" >/dev/null
  nest_ctl dispatch "hl.dsp.window.resize({ x = $((mw * $4 / 100)), y = $((mh * $5 / 100)), relative = false, window = 'class:$1' })" >/dev/null
  sleep 0.2
}

# Middle of a window's titlebar: the bar occupies the 28px above the window box.
titlebar_point() { # CLASS -> "X Y"
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$1' and c['mapped']:
        print(c['at'][0] + c['size'][0] // 2, c['at'][1] - 14)
        break"
}

gaps_out() { nest_ctl getoption general:gaps_out | head -1 | awk '{print $4}'; }

border_size() { nest_ctl getoption general:border_size | head -1 | awk '{print $2}'; }
