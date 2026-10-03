#!/usr/bin/env bash
# Shared helpers for the x-mode test suite. Source it from a test file or a
# runner; it does not run anything on its own.
#
# The nest is a nested Hyprland (a window inside the real session) running the
# repo's x-mode.lua with its own $X_MODE_STATE, so nothing here touches the live
# session's files. The runtime touch is a window rule plus a 1px layer that
# keeps covered nests presenting; both are removed when the run ends.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$TESTS_DIR/.." && pwd)"
# Paths that depend on which nest this process talks to. A parallel run gives
# each worker its own slot; the built pointer, keyboard and nestq stay shared.
nest_paths() {
  NEST_SLOT="${NEST_SLOT:-0}"
  NEST_ROOT="$TESTS_DIR/.nest"
  # The runtime directory has to be SHORT. A unix socket path is 107 bytes plus
  # a NUL, and Hyprland puts two sockets in it:
  #   $XDG_RUNTIME_DIR/hypr/<40hex>_<time>_<rand>/.socket2.sock
  # The event socket is the longer one. Quickshell (the dock) connects to it;
  # a path that does not fit is a missing socket, and the dock then has no
  # windows to click. /tmp/xmn-<slot> leaves about 16 bytes of spare for a
  # longer signature. The old /tmp/x-mode-nest-runtime-<slot> was one byte over
  # and the menu tests never saw a layer.
  #
  # A private runtime is also what keeps a test out of the live session. The
  # pack's Lua writes the switcher and snap-preview command files into
  # $XDG_RUNTIME_DIR, and the shell of the running session reads those same
  # paths: with the real runtime directory, a keypress or a drag in the nest
  # would flash an overlay on the desktop the user is sitting in front of.
  NEST_RUNTIME="/tmp/xmn-$NEST_SLOT"
  NEST_STATE="$NEST_ROOT/slot-$NEST_SLOT"
  NEST_IPC_SOCK="/tmp/x-mode-nest-ipc-$NEST_SLOT"
  NEST_LOG="$NEST_STATE/nest.log"
  NESTQ="$NEST_ROOT/nestq"
  POINTER_BIN="$NEST_ROOT/pointer/pointer"
  KEYBOARD_BIN="$NEST_ROOT/keyboard/keyboard"
  SIG="${SIG:-$(cat "$NEST_STATE/sig" 2>/dev/null || true)}"
  DOCK_RUNTIME="$NEST_RUNTIME"
  DOCK_CFG="$NEST_STATE/dock"
  DOCK_LOG="$NEST_STATE/dock.log"
  NEST_DIRTY="$NEST_STATE/config-dirty"
  # The panel's settings live in the user's config dir (the pack's own directory
  # and the state dir are both removed on uninstall), so the nest writes them
  # into its throwaway HOME.
  NEST_SETTINGS="$NEST_STATE/home/.config/hypr/x-mode.json"
}
NEST_LUA="$REPO_DIR/hypr/x-mode/x-mode.lua"
PLUGIN_SO="$REPO_DIR/hyprbars/hyprbars.so"
POINTER_DIR="$TESTS_DIR/pointer"
KEYBOARD_DIR="$TESTS_DIR/keyboard"
NEST_BAR="${NEST_BAR:-1}"
nest_paths

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
build_nestq() {
  cc -O2 -Wall -Wextra -o "$NESTQ" "$TESTS_DIR/nestq.c" || fail "nestq build failed"
}

build_pointer() {
  local out="$NEST_ROOT/pointer"
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

# The keyboard sends a keymap built from the system rules and presses libinput
# codes, so Hyprland's bind matching resolves the same keysyms it would for a real
# keyboard. Built into .nest/ like the pointer.
build_keyboard() {
  local out="$NEST_ROOT/keyboard"
  command -v wayland-scanner >/dev/null || fail "wayland-scanner not found"
  pkg-config --exists wayland-client || fail "wayland-client headers not found"
  pkg-config --exists xkbcommon || fail "xkbcommon headers not found"
  mkdir -p "$out"
  wayland-scanner client-header "$KEYBOARD_DIR/virtual-keyboard-unstable-v1.xml" \
    "$out/virtual-keyboard-unstable-v1-client-protocol.h"
  wayland-scanner private-code "$KEYBOARD_DIR/virtual-keyboard-unstable-v1.xml" \
    "$out/virtual-keyboard-unstable-v1-protocol.c"
  # shellcheck disable=SC2046 - pkg-config output is a flag list on purpose
  cc -O2 -Wall -Wextra -I"$out" -o "$KEYBOARD_BIN" "$KEYBOARD_DIR/keyboard.c" \
    "$out/virtual-keyboard-unstable-v1-protocol.c" \
    $(pkg-config --cflags --libs wayland-client xkbcommon) \
    || fail "keyboard build failed"
}

# The nest is a toplevel on the host. Without this rule the host focuses it on
# map and again whenever the nested compositor asks to be activated, which is
# every time a window inside it takes focus. no_initial_focus covers the map,
# and focus_on_activate covers those requests. no_focus is not set: it also
# rejects a click on the titlebar, so the keyboard stays on Chrome or Zed.
# The rule is runtime-only: it is not written into the user's config, and the
# runner drops it when the run ends. Same name on every slot, so several nests
# share one rule.
#
# pin keeps each nest above the rest of the desktop. A covered window on the
# current workspace is not drawn, and the unfocused-render timer skips any
# window whose workspace is visible, so that timer never unlocks a nest
# something else has covered. The bar and the clients inside then never
# commit, and the nest looks like it did not start. Same-app grouping already
# skips class aquamarine and Hyprland. The pin dies with the window.
#
# NEST_WORKSPACE is a workspace id. Empty leaves the nests on the workspace
# the run started on, pinned. A number maps every nest there and drops the
# pin: a pinned window is drawn on every workspace, so it would still sit on
# the one in view. The string is "N silent" so the view stays put. A named
# rule keeps an effect it was given before, so the empty case sends "unset",
# which is what clears a workspace stored by an earlier run. The workspace
# has to be the one on screen: Hyprland suspends a window whose workspace is
# not visible, and a suspended nest stops committing.
#
# The nest is not lowered. A covered window on the current workspace is not
# drawn, so it gets no frame callback: Hyprland's unfocused-render timer skips
# any window whose workspace is visible, and that timer is the only path that
# also unlocks the client's buffer. A 1px overlay committing 10 times a second
# is only a backstop for a nest something else has covered. The layer is
# removed with the rule.
#
# The toplevel's class is the wayland backend's app id, "aquamarine", not
# "Hyprland". A rule on the wrong class never matches, so the nest takes focus
# every time a window inside it does. The second name covers a build that
# still calls the toplevel Hyprland. Each update sends the whole rule: a
# partial one replaces the rest.
nest_host_rule() { # true|false — render_unfocused
  local render="${1:-false}" cls name pin=true ws_rule="unset"
  if [ -n "${NEST_WORKSPACE:-}" ]; then
    case "$NEST_WORKSPACE" in
      *[!0-9]*|0)
        echo "NEST_WORKSPACE wants a workspace number, got '${NEST_WORKSPACE}'" >&2
        return 1
        ;;
    esac
    pin=false
    ws_rule="${NEST_WORKSPACE} silent"
  fi
  for cls in aquamarine Hyprland; do
    case "$cls" in
      aquamarine) name="x-mode-nest" ;;
      *) name="x-mode-nest-hl" ;;
    esac
    hyprctl eval "hl.window_rule({
      name = \"${name}\",
      match = { class = \"${cls}\" },
      float = true,
      size = \"900 1000\",
      move = \"40 40\",
      pin = ${pin},
      workspace = \"${ws_rule}\",
      no_initial_focus = true,
      focus_on_activate = false,
      render_unfocused = ${render},
    })" >/dev/null || return 1
  done
}

# One pixel, above every window, committing 10 times a second. It does not
# take keyboard focus and it does not reserve space. The speck sits in the
# bottom-right corner for the length of the run.
nest_host_tick_start() {
  local cfg="$NEST_ROOT/host-tick" i
  mkdir -p "$cfg"
  cat > "$cfg/shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Wayland

ShellRoot {
  Variants {
    model: Quickshell.screens
    delegate: Component {
      PanelWindow {
        required property var modelData
        screen: modelData
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        focusable: false
        aboveWindows: true
        anchors { bottom: true; right: true }
        implicitWidth: 1
        implicitHeight: 1
        color: "transparent"
        WlrLayershell.namespace: "x-mode-nest-tick"

        Rectangle {
          id: pix
          width: 1
          height: 1
          color: "#000000"
        }

        Timer {
          interval: 100
          running: true
          repeat: true
          onTriggered: pix.color = pix.color == "#000000" ? "#010101" : "#000000"
        }
      }
    }
  }
}
QML
  setsid qs -p "$cfg" > "$NEST_ROOT/host-tick.log" 2>&1 < /dev/null &
  echo $! > "$NEST_ROOT/host-tick.pid"
  for i in $(seq 1 30); do
    hyprctl layers -j 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin) or {}
for out in data.values():
    for layers in ((out or {}).get("levels") or {}).values():
        for layer in layers or []:
            if layer.get("namespace") == "x-mode-nest-tick":
                raise SystemExit(0)
raise SystemExit(1)' && return 0
    sleep 0.1
  done
  echo "host tick did not map" >&2
  sed 's/^/       /' "$NEST_ROOT/host-tick.log" >&2
  return 1
}

nest_host_tick_stop() {
  local pid=""
  [ -f "$NEST_ROOT/host-tick.pid" ] && pid="$(cat "$NEST_ROOT/host-tick.pid")"
  if [ -n "$pid" ]; then
    kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
  fi
  rm -f "$NEST_ROOT/host-tick.pid"
}

nest_host_rule_on() {
  nest_host_rule true || return 1
  nest_host_tick_start
}

nest_host_rule_off() {
  nest_host_tick_stop
  hyprctl eval 'hl.window_rule({ name = "x-mode-nest", enabled = false })' >/dev/null 2>&1 || true
  hyprctl eval 'hl.window_rule({ name = "x-mode-nest-hl", enabled = false })' >/dev/null 2>&1 || true
}

nest_start() {
  nest_paths
  if [ "${NEST_SKIP_BUILD:-0}" != 1 ]; then
    build_plugin
    build_pointer
    build_keyboard
    build_nestq
  fi
  [ -x "$NESTQ" ] || fail "nestq is missing (build failed)"
  nest_stop
  # The nest is a Wayland client of the host, so its own WAYLAND_DISPLAY has to be
  # absolute once XDG_RUNTIME_DIR points elsewhere.
  local host_socket="${WAYLAND_DISPLAY:-wayland-1}"
  case "$host_socket" in /*) ;; *) host_socket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$host_socket" ;; esac
  rm -rf "$NEST_RUNTIME"
  mkdir -p "$NEST_RUNTIME" "$NEST_ROOT"
  # Start from a clean state dir: a run that fails midway can leave settings.json
  # behind, and the next run would inherit it.
  rm -rf "$NEST_STATE/state" "$NEST_STATE/home"
  mkdir -p "$NEST_STATE/state" "$NEST_STATE/home" "$(dirname "$NEST_SETTINGS")"

  # setsid makes this pid the process-group leader, so nest_stop can kill the
  # nest without the pattern match that would also kill every other slot.
  setsid env \
    HOME="$NEST_STATE/home" \
    WAYLAND_DISPLAY="$host_socket" \
    XDG_RUNTIME_DIR="$NEST_RUNTIME" \
    X_MODE_LUA="$NEST_LUA" \
    X_MODE_STATE="$NEST_STATE/state" \
    Hyprland -c "$TESTS_DIR/nest.lua" > "$NEST_LOG" 2>&1 < /dev/null &
  local pid=$! i
  echo "$pid" > "$NEST_STATE/pid"
  for i in $(seq 1 60); do
    SIG="$(XDG_RUNTIME_DIR="$NEST_RUNTIME" hyprctl instances 2>/dev/null | awk -v pid="$pid" '
      /^instance / { n = $2; sub(/:$/, "", n) }
      /pid:/ { if ($2 == pid) print n }')"
    [ -n "$SIG" ] && break
    sleep 0.2
  done
  [ -n "$SIG" ] || { tail -20 "$NEST_LOG" >&2; fail "nest did not come up"; }
  echo "$SIG" > "$NEST_STATE/sig"
  nest_ipc_start

  # The config parses before the plugin exists, so its plugin:* keys are unknown
  # on the first pass. Load the plugin and reload once; the second parse is clean.
  nest_ctl plugin load "$PLUGIN_SO" >/dev/null
  nest_ctl reload >/dev/null

  nest_place_window "$pid"

  if [ "$NEST_BAR" = 1 ]; then
    nest_bar_start || return 1
  fi
  return 0
}

# The output can report a reserved top before this bar exists (anything >= 24
# used to satisfy the old check). Geometry is then computed against that
# phantom, and a later real bar stacks on top of it. Ready means the layer
# itself is up and the reserved top is its 24px, nothing else.
nest_bar_ready() {
  nest_ctl layers -j 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin) or {}
except Exception:
    raise SystemExit(1)
for out in data.values():
    for layers in ((out or {}).get("levels") or {}).values():
        for layer in layers or []:
            if layer.get("namespace") == "x-mode-nest-bar" and int(layer.get("h") or 0) == 24:
                raise SystemExit(0)
raise SystemExit(1)' && [ "$(bar_top 2>/dev/null)" = 24 ]
}

# The output shows up after the wayland socket. A bar started before that
# binds no screen and never maps, and the reserved top stays whatever the
# output reported on the way up.
#
# The size, and not "wide enough": the backend offers 1280x720 first, the host
# rejects that mode, and until its own configure lands hyprctl still reports that
# wide monitor -- which a width threshold accepts. What is waited for is a size
# that stops changing instead; see nest_bar_spawn.
nest_output_size() {
  nest_ctl monitors -j 2>/dev/null | python3 -c '
import json, sys
try:
    mons = json.load(sys.stdin) or []
except Exception:
    raise SystemExit(1)
if not mons:
    raise SystemExit(1)
m = mons[0]
print("%dx%d" % (int(m.get("width") or 0), int(m.get("height") or 0)))
'
}

nest_bar_spawn() {
  local disp i
  disp="$(nest_display)"
  # qs falls back to the host display if this socket is not there yet, and a
  # bar on the host is not the nest's reserved top.
  for i in $(seq 1 50); do
    [ -S "$disp" ] && break
    sleep 0.05
  done
  [ -S "$disp" ] || return 1
  # The first configure is 0x0. The backend answers with 1280x720, the host
  # rejects that mode, and for a moment hyprctl still reports a wide monitor.
  # qs started on that blip binds no real screen, and "wide enough" is true of
  # the rejected mode as well -- so what is waited for is one non-zero size that
  # holds. Eighth tenths of a second is a configure cycle on a loaded host.
  local ready=0 streak=0 size="" held=""
  for i in $(seq 1 100); do
    size="$(nest_output_size 2>/dev/null || true)"
    if [ -n "$size" ] && [ "$size" != "0x0" ] && [ "$size" = "$held" ]; then
      streak=$((streak + 1))
      if [ "$streak" -ge 8 ]; then
        ready=1
        break
      fi
    else
      streak=0
    fi
    held="$size"
    sleep 0.1
  done
  [ "$ready" = 1 ] || return 1
  sleep 0.2
  env WAYLAND_DISPLAY="$disp" \
    XDG_RUNTIME_DIR="$NEST_RUNTIME" \
    QT_QPA_PLATFORM=wayland \
    setsid qs -p "$TESTS_DIR/bar.qml" \
    > "$NEST_STATE/bar.log" 2>&1 < /dev/null &
  echo $! > "$NEST_STATE/bar.pid"
}

nest_bar_start() {
  local attempt _
  # The first shell sometimes connects before the nest has an output, or
  # the host drops that wayland client while several nests are mapping.
  # A later try has the output, and a shell that already bound a placeholder
  # is thrown away rather than waited on.
  for attempt in 1 2 3 4; do
    nest_bar_spawn || {
      sleep 0.3
      continue
    }
    for _ in $(seq 1 40); do
      nest_bar_ready && return 0
      sleep 0.1
    done
    nest_bar_stop
  done
  # return, do not exit. fail() ends the worker, so the caller's
  # "start the nest again" never runs and one missed bar drops the slot.
  # The output is printed with it: an empty reserved top says the nest has no
  # output at all, '0' that it has one and the bar reserved nothing on it, and
  # a width that is not the settled one says the bar bound the mode the host
  # had not accepted yet.
  echo "bar reserved '$(bar_top 2>/dev/null)' with the output '$(nest_output_size 2>/dev/null || echo none)'" >&2
  sed 's/^/       /' "$NEST_STATE/bar.log" >&2
  echo "the nest bar did not reserve the top" >&2
  return 1
}

nest_bar_stop() {
  [ -f "$NEST_STATE/bar.pid" ] && kill "$(cat "$NEST_STATE/bar.pid")" 2>/dev/null || true
  rm -f "$NEST_STATE/bar.pid"
  sleep 0.3
}

nest_stop() {
  nest_bar_stop
  nest_ipc_stop
  local pid=""
  [ -f "$NEST_STATE/pid" ] && pid="$(cat "$NEST_STATE/pid")"
  if [ -n "$pid" ]; then
    # The group, not just the leader: Hyprland's children go with it. A negative
    # pid is the process group setsid created.
    kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    local i
    for i in $(seq 1 25); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.05
    done
  fi
  rm -f "$NEST_STATE/pid"
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
  local w="address:$addr" x y
  # Stagger so each titlebar sticks out of the pile. A click then hits the
  # nest it is aimed at. Nothing here moves keyboard focus: handing it back
  # to whoever was active when the run started is what sent a titlebar click
  # to Chrome or Zed while the other nests were still mapping. The host rule
  # pins the window, so a later focus does not cover it and stop its frames.
  x=$((40 + ${NEST_SLOT:-0} * 36))
  y=$((40 + ${NEST_SLOT:-0} * 36))
  # The host rule already floats and sizes. These dispatches are the fallback
  # when that rule did not match, and they must not raise the window:
  # alter_zorder top is what pulled it over the desktop on every run.
  hyprctl dispatch "hl.dsp.window.float({ action = \"enable\", window = \"$w\" })" >/dev/null 2>&1 || true
  # The first configure the host sends can be 0x0 while it is busy mapping
  # several nests. The wayland backend then commits a fallback size, the host
  # rejects that mode, and the nest never gets an output. Keep resizing until
  # the window is actually the box the rule asked for.
  local sz=""
  for i in $(seq 1 15); do
    hyprctl dispatch "hl.dsp.window.resize({ x = 900, y = 1000, relative = false, window = \"$w\" })" >/dev/null 2>&1 || true
    hyprctl dispatch "hl.dsp.window.move({ x = $x, y = $y, relative = false, window = \"$w\" })" >/dev/null 2>&1 || true
    sz="$(hyprctl clients -j 2>/dev/null | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c.get('pid') == $pid:
        s = c.get('size') or [0, 0]
        print(int(s[0]), int(s[1]))
        break
" || true)"
    [ "$sz" = "900 1000" ] && break
    sleep 0.1
  done
  # Leave it where map put it, above the other windows. alter_zorder bottom
  # covers the nest, and a covered window on the current workspace gets no
  # frame callbacks: the dock, the menu and the bar then never commit.
  # no_initial_focus is what keeps the map from taking the keyboard.
}

# What the current scenario changed in the live config. A plugin option is read
# back by the pack on every event, so only a reload puts it back; a named window
# rule can be switched off on its own. Everything else a scenario does (windows,
# the workspace, settings.json) nest_clean undoes without one, and reloading
# every time reparsed the whole config between all 105 scenarios.
# A scenario runs in its own process, so a variable it set is gone by the time
# nest_clean runs in the runner. The file survives. A line of "reload" means the
# scenario reparsed the config or set a plugin option, and both are read back
# live, so only another reload restores them. A "rule <name>" line is a named
# window rule to switch off, which does not need a reload.
nest_ctl() {
  case "$*" in
    *"reload"* | *"hl.config"*) printf 'reload\n' >> "$NEST_DIRTY" ;;
    *"hl.window_rule"*)
      local rule
      rule="$(printf '%s' "$*" | sed -n "s/.*name = '\([^']*\)'.*/\1/p")"
      [ -n "$rule" ] && printf 'rule %s\n' "$rule" >> "$NEST_DIRTY"
      ;;
  esac
  nest_hyprctl "$@"
}

# The request socket is one command per connection, so a long-lived python
# opens it per call and nestq is the thin client. hyprctl from the shell paid
# a process start every time; this does not.
nest_ipc_start() {
  [ -n "$SIG" ] || return 1
  # The worker owns the server. A scenario is a child process and must not
  # start a second one: binding unlinks the socket the worker is serving.
  if [ -S "$NEST_IPC_SOCK" ] && "$NESTQ" "$NEST_IPC_SOCK" active class >/dev/null 2>&1; then
    return 0
  fi
  python3 -u "$TESTS_DIR/ipc.py" "$NEST_IPC_SOCK" "$NEST_RUNTIME/hypr/$SIG/.socket.sock" \
    > "$NEST_STATE/ipc.log" 2>&1 &
  NEST_IPC_PID=$!
  echo "$NEST_IPC_PID" > "$NEST_STATE/ipc.pid"
  local i
  for i in $(seq 1 50); do
    [ -S "$NEST_IPC_SOCK" ] && return 0
    sleep 0.02
  done
  return 1
}

nest_ipc_stop() {
  local pid="${NEST_IPC_PID:-}"
  [ -z "$pid" ] && [ -f "$NEST_STATE/ipc.pid" ] && pid="$(cat "$NEST_STATE/ipc.pid")"
  [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  NEST_IPC_PID=""
  rm -f "$NEST_STATE/ipc.pid" "$NEST_IPC_SOCK"
}

nest_query() { # words...  -> body on stdout
  nest_ipc_start || fail "nest ipc did not come up"
  "$NESTQ" "$NEST_IPC_SOCK" "$@"
}

nest_hyprctl() { nest_query "$@"; }

# Absolute path to the nest's Wayland socket. The nest's runtime directory is not
# the test's, so a bare socket name would point a client at the live session.
# The name does not change for the life of the nest, so it is read once.
nest_display() { printf '%s/%s' "$NEST_RUNTIME" "$(nest_socket)"; }

nest_socket() {
  if [ -z "${NEST_WL:-}" ]; then
    NEST_WL="$(cat "$NEST_STATE/wl" 2>/dev/null || true)"
  fi
  if [ -z "$NEST_WL" ]; then
    NEST_WL="$(XDG_RUNTIME_DIR="$NEST_RUNTIME" hyprctl instances 2>/dev/null | python3 -c "
import sys, re
for b in sys.stdin.read().split('instance ')[1:]:
    if '$SIG' in b:
        print(re.search(r'wl socket: (\S+)', b).group(1)); break
")"
    [ -n "$NEST_WL" ] && printf '%s' "$NEST_WL" > "$NEST_STATE/wl"
  fi
  printf '%s' "$NEST_WL"
}

# Close every window in the nest, so each test starts from nothing.
nest_clean() {
  local addrs a
  addrs="$(nest_query addrs)"
  for a in $addrs; do
    nest_ctl dispatch "hl.dsp.window.close({ window = 'address:$a' })" >/dev/null 2>&1 || true
  done
  # Settings are written by the panel, and by the tests that drive it. Reset them
  # so a test that fails midway cannot change how the next one lays out windows.
  printf '%s\n' '{"options":{},"apps":{}}' > "$NEST_SETTINGS"
  # x-mode's on/off file and the one-shot arrange marker: a scenario that turns
  # X Mode off (or arranges) must not leave the next one off.
  rm -f "$NEST_STATE/state/enabled" "$NEST_STATE/state/arrange"
  # The dock's pinned list lives in the dock's HOME, which outlives a single
  # scenario, so it has to be cleared too or the next dock test starts with
  # someone else's icons. Desktop entries written there are cleared for the same
  # reason: a leftover single-instance entry changes the dock's menu for the
  # class it names, which shifts the rows the menu tests click on.
  rm -f "$NEST_STATE/home/.config/omarchy/x-mode-dock.json"
  rm -rf "$NEST_STATE/home/.local/share/applications"
  # Back to the first workspace: a scenario that switches away (the dock menu one
  # does) would otherwise decide where the next one opens its windows, and two
  # same-app windows that land on one space group instead of staying apart.
  nest_ctl dispatch "hl.dsp.focus({ workspace = \"1\" })" >/dev/null 2>&1 || true
  # A scenario that reparsed the config (or set a plugin option, which is read
  # back live) leaves the next one with that config, because the file it wrote is
  # wiped above but the running config is not. Reparse once to put it back. A
  # named window rule needs no reparse: switching it off is the removal.
  if [ -f "$NEST_DIRTY" ] && grep -q '^reload$' "$NEST_DIRTY"; then
    nest_hyprctl reload >/dev/null 2>&1 || true
    sleep 0.4
  elif [ -f "$NEST_DIRTY" ]; then
    local rule
    while read -r rule; do
      [ -n "$rule" ] && nest_hyprctl eval "hl.window_rule({ name = '$rule', enabled = false })" >/dev/null 2>&1 || true
    done < <(sed -n 's/^rule //p' "$NEST_DIRTY")
  fi
  rm -f "$NEST_DIRTY"
  # App chrome rules live in the running config, not only in the file just
  # reset. refresh_apps_off drops them from the empty file, so a scenario that
  # turned chrome off does not leave that rule for the next one, and a reload
  # is not required to do it.
  nest_hyprctl eval 'if x_mode and x_mode.refresh_apps_off then x_mode.refresh_apps_off() end' >/dev/null 2>&1 || true
}

# The panel's path for an app-list change: write settings.json, then this.
# Options (no gaps, ctrl-tab) still go through a reload, because the dock reads
# its margin on configreloaded and this call does not emit that.
refresh_apps() {
  nest_ctl eval 'if x_mode and x_mode.refresh_apps_off then x_mode.refresh_apps_off() end' >/dev/null
}

# Poll until a command succeeds. The command is the condition the next assert
# checks, so the wait ends when the compositor has landed instead of after a
# fixed pause.
wait_until() { # SECONDS COMMAND...
  local secs="$1" i
  shift
  for i in $(seq 1 $((secs * 20))); do
    "$@" && return 0
    sleep 0.05
  done
  return 1
}

# The join retry is 200ms and the chrome absorb is 120ms. A box that holds
# still after that is done moving. The 2s open watch scenarios used to outlast
# is gone: geometry is the plugin's, and it runs inside updateWindow.
wait_still() { # CLASS
  local cls="$1" i geom prev=""
  for i in $(seq 1 20); do
    geom="$(win_geom "$cls" 2>/dev/null || true)"
    if [ "$i" -ge 6 ] && [ -n "$geom" ] && [ "$geom" = "$prev" ]; then
      return 0
    fi
    prev="$geom"
    sleep 0.05
  done
  return 0
}

# Short timers only: join retry, chrome absorb, the 300ms tiled-float pass.
# The arrange timer is 600ms and the scenarios that wait for it keep an
# explicit sleep.
settle() { sleep 0.32; }

# --- windows -----------------------------------------------------------------

open_window() { # CLASS [COUNT]
  local cls="$1" want="${2:-1}" i got
  env WAYLAND_DISPLAY="$(nest_display)" setsid "$cls" >/dev/null 2>&1 < /dev/null &
  # Wait until the window is mapped and has a box, not merely listed. A fixed
  # pause after the count would sleep the same half second on every call, and a
  # step that reads the geometry right after would otherwise race the map.
  for i in $(seq 1 80); do
    got="$(nest_query count "$cls")"
    # Whether the window joins a group is the scenario's to check. Waiting for it
    # here made a scenario that asserts "these do not group" wait for a join
    # that never comes.
    [ "$got" -ge "$want" ] 2>/dev/null && return 0
    sleep 0.1
  done
  fail "window '$cls' did not appear"
}

# Open a window by running a command, for windows that need arguments (a zenity
# dialog, for instance). Waits for CLASS to appear, like open_window.
open_command() { # CLASS COMMAND...
  local cls="$1"
  shift
  local want i
  want=$(( $(count_class "$cls") + 1 ))
  env WAYLAND_DISPLAY="$(nest_display)" setsid "$@" >/dev/null 2>&1 < /dev/null &
  for i in $(seq 1 60); do
    [ "$(count_class "$cls")" -ge "$want" ] && return 0
    sleep 0.1
  done
  fail "command did not open another '$cls' window: $*"
}

# Wait until CLASS has COUNT windows, up to TIMEOUT seconds (10 by default). A
# launch that goes through gtk-launch can take a while on a cold start, and a
# fixed short wait turns that into a flaky test.
wait_for_count() { # CLASS COUNT [TIMEOUT]
  local cls="$1" want="$2" timeout="${3:-10}" i
  for i in $(seq 1 $((timeout * 10))); do
    [ "$(count_class "$cls")" -ge "$want" ] && return 0
    sleep 0.1
  done
  fail "waited ${timeout}s for $want '$cls' windows, saw $(count_class "$cls")"
}

count_class() { nest_query count_listed "$1"; }

# "atx aty w h grouped"
win_geom() { nest_query geom "$1"; }

bar_height() { nest_query option plugin:hyprbars:bar_height 2; }
tab_height() { nest_query option plugin:hyprbars:tab_height 2; }

# Top of the titlebar: at.y minus the chrome (titlebar, plus the tabbar when
# grouped). The heights come from the plugin's own options, so a config that
# changes them does not leave this measuring a bar that is no longer there.
# At/above the bar means it went under it.
visual_top() { # CLASS
  local bh th
  bh="$(bar_height)"
  th="$(tab_height)"
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$1' and c['mapped']:
        grp = len(c.get('grouped') or [])
        print(c['at'][1] - ($bh + ($th if grp else 0)))
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

active_class() { nest_query active class; }

# Id of the workspace the user is looking at.
viewed_workspace() { nest_query active workspace; }

active_address() { nest_query active address; }

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

# How many binds Hyprland has for a key and modifier mask. Mod1 is 8, Control
# is 4, Mod4 (Super) is 64. A modified keybind cannot be driven from a test
# (see the README), so the bind table is where those contracts are pinned.
bind_count() { # KEY MODMASK
  nest_ctl binds -j | python3 -c "
import json, sys
key, mods = '$1', int('$2')
print(sum(1 for b in json.load(sys.stdin) if b.get('key') == key and int(b.get('modmask') or 0) == mods))"
}

# Same, matched on the description. A bind made with a raw keycode (`CTRL +
# code:10`) reports an empty key, so the description is the only handle on it.
bind_count_desc() { # TEXT MODMASK
  nest_ctl binds -j | python3 -c "
import json, sys
text, mods = '$1'.lower(), int('$2')
print(sum(1 for b in json.load(sys.stdin)
          if text in (b.get('description') or '').lower() and int(b.get('modmask') or 0) == mods))"
}

# The whole description, not a substring of it: "Start of line" is inside
# "Delete to start of line" and "B" is inside "BACKSPACE", so a scenario that
# counts a label has to say which one it means.
bind_count_desc_exact() { # TEXT MODMASK
  nest_ctl binds -j | python3 -c "
import json, sys
text, mods = '$1'.lower(), int('$2')
print(sum(1 for b in json.load(sys.stdin)
          if (b.get('description') or '').lower() == text and int(b.get('modmask') or 0) == mods))"
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

bar_top() { nest_query reserved_top; }

# --- dock ---------------------------------------------------------------------
# The dock is a Quickshell layer surface in the nest, so it needs a Quickshell of
# its own (the same trick as nest/qml_test.sh) and the pointer tool reaches its
# icons, because both talk to the nest.
#
# The dock runs with the nest's runtime directory, which is where the plugin's
# state file, the switcher's command file and the nest's Hyprland socket all are.
# WAYLAND_DISPLAY is the absolute path to the nest socket, which wayland accepts.
DOCK_RUNTIME="$NEST_RUNTIME"
DOCK_CFG="$NEST_STATE/dock"
DOCK_LOG="$NEST_STATE/dock.log"
DOCK_ICON=26
DOCK_PAD=7
DOCK_SPACING=6

dock_start() {
  [ -d /usr/share/omarchy/shell/Commons ] || fail "Omarchy shell modules not found (needed for qs.Commons)"
  command -v qs >/dev/null || fail "quickshell (qs) not found"
  dock_stop
  rm -rf "$DOCK_CFG"
  mkdir -p "$DOCK_CFG" "$NEST_STATE/home/.config/omarchy"
  # qs.* resolve from the config folder, so Omarchy's modules have to be there.
  ln -s /usr/share/omarchy/shell/Commons "$DOCK_CFG/Commons"
  ln -s /usr/share/omarchy/shell/Ui "$DOCK_CFG/Ui"
  mkdir -p "$DOCK_RUNTIME"
  echo on > "$DOCK_RUNTIME/omarchy-x-mode.state"
  cat > "$DOCK_CFG/shell.qml" <<QML
import Quickshell
import "file:$REPO_DIR/quickshell/x-mode" as X

ShellRoot {
  X.Dock {}
}
QML
  env HOME="$NEST_STATE/home" \
    XDG_RUNTIME_DIR="$DOCK_RUNTIME" \
    WAYLAND_DISPLAY="$DOCK_RUNTIME/$(nest_socket)" \
    HYPRLAND_INSTANCE_SIGNATURE="$SIG" QT_QPA_PLATFORM=wayland \
    setsid qs -p "$DOCK_CFG" > "$DOCK_LOG" 2>&1 < /dev/null &
  echo $! > "$NEST_STATE/dock.pid"
  local i
  for i in $(seq 1 60); do
    dock_box >/dev/null 2>&1 && return 0
    sleep 0.25
  done
  sed 's/^/       /' "$DOCK_LOG" >&2
  fail "the dock never created its layer in the nest"
}

dock_stop() {
  [ -f "$NEST_STATE/dock.pid" ] && kill "$(cat "$NEST_STATE/dock.pid")" 2>/dev/null || true
  rm -f "$NEST_STATE/dock.pid"
  # The pack reads the dock's width off its layer and keeps the last one it saw,
  # so a dock that has gone still leaves the snap inset at the card width. Put it
  # back, or the next scenario's right half stops short of where it should.
  if [ -n "$SIG" ]; then
    nest_hyprctl eval "hl.config({ plugin = { hyprbars = { x_mode_dock_inset = 45 } } })" >/dev/null 2>&1 || true
  fi
}

dock_box() { # "X Y W H" of the dock's layer surface
  dock_layer_box x-mode-dock
}

# The order the card is actually showing: one class per line in the file the
# dock writes when its published list changes, as one line for assertions.
dock_order() {
  tr '\n' ' ' < "$DOCK_RUNTIME/omarchy-x-mode.dock-order" 2>/dev/null | sed 's/ *$//'
}

# Wait for the card to show this order. The box says how many icons there are
# and not which, so a pin of an app that is already running leaves it alone and
# the order is the only thing that moves.
dock_wait_order() { # "class class ..."
  wait_until 5 [ "$(dock_order)" = "$1" ]
}

dock_layer_box() { # NAMESPACE
  nest_ctl layers -j | python3 -c "
import json, sys
for output in (json.load(sys.stdin) or {}).values():
    levels = (output or {}).get('levels') or {}
    for key in sorted(levels):
        for layer in levels[key] or []:
            if layer.get('namespace') == '$1':
                print(layer['x'], layer['y'], layer['w'], layer['h'])
                raise SystemExit
raise SystemExit(1)"
}

# Middle of icon INDEX in the dock column. The card is iconSize + 2*pad wide,
# the column is centred in it, and the icons stack with DOCK_SPACING between
# them, so the first icon's centre is pad + iconSize/2 from the card's top.
#
# This only holds while the column is one block of icons: with both pinned and
# running apps there is a 1px separator between them, and everything after it is
# one separator plus two spacings lower.
dock_icon_point() { # INDEX
  local x y w h
  read -r x y w h <<<"$(dock_box)"
  python3 -c "print($x + $w // 2, $y + $DOCK_PAD + $DOCK_ICON // 2 + $1 * ($DOCK_ICON + $DOCK_SPACING))"
}

# Wait for the dock to pick up the current window list. It re-queries 120ms
# after the last Hyprland event and resizes its layer to the new icon column,
# so the layer box changing is the signal, and a second identical read means the
# rebuild has landed. A fixed second would sleep the same whether the dock had
# already caught up or not.
# Height of the card the dock should be showing for the windows and pins that
# exist right now. A box that is merely stable can still be the previous
# column (one icon, height 40) when the second window's event is late, and
# the click then hits the wrong app. The card is padding plus one icon per
# pinned class and per other running class, with a 1px separator when both
# sections exist.
dock_expect_h() {
  nest_ctl clients -j | PIN="$(dock_pinned_file)" python3 -c '
import json, os, sys
clients = json.load(sys.stdin)
pinned = []
path = os.environ.get("PIN") or ""
if path and os.path.exists(path):
    try:
        pinned = json.load(open(path))
    except Exception:
        pinned = []
if not isinstance(pinned, list):
    pinned = []
seen = []
for c in clients:
    if not c.get("mapped") or c.get("hidden"):
        continue
    cls = c.get("class") or ""
    if cls and cls not in seen:
        seen.append(cls)
pin = []
for cls in pinned:
    if isinstance(cls, str) and cls not in pin:
        pin.append(cls)
running = [cls for cls in seen if cls not in pin]
kp, kr = len(pin), len(running)
pad, icon, sp = 14, 26, 6
if kp == 0 and kr == 0:
    print(40)
elif kp == 0:
    print(pad + kr * icon + (kr - 1) * sp)
elif kr == 0:
    print(pad + kp * icon + (kp - 1) * sp)
else:
    pinned_box = kp * icon + (kp - 1) * sp
    print(pad + pinned_box + sp + 1 + sp + kr * icon + (kr - 1) * sp)
'
}

dock_settle() {
  local want prev="" cur i stable=0 h
  # The wanted height is recomputed as windows come and go during the wait.
  # A value taken once at the start is the list from before the dock has
  # caught up, and the card then settles on a height we refuse to accept.
  # The dock learns about those windows through its own hyprctl, on the same
  # socket these queries use. Hammering it every 100ms keeps that hyprctl
  # queued, so the card stays on the previous column. A short yield, then a
  # slower poll, leaves the socket free for the dock.
  sleep 0.2
  for i in $(seq 1 32); do
    [ $((i % 4)) -eq 1 ] && want="$(dock_expect_h)"
    cur="$(dock_box 2>/dev/null || true)"
    h="${cur##* }"
    if [ -n "$cur" ] && [ -n "$want" ] && [ "$cur" = "$prev" ] && [ "$h" = "$want" ]; then
      stable=$((stable + 1))
      [ "$stable" -ge 2 ] && return 0
    else
      stable=0
    fi
    prev="$cur"
    sleep 0.25
  done
  fail "the dock did not settle (wanted height ${want:-?}, last '${cur:-none}')"
}

# The dock's pinned list. HOME is the nest's for the dock process, so writing
# this file is how a test pins without going through the menu. The dock watches
# the file, so no restart is needed.
dock_pinned_file() { printf '%s/.config/omarchy/x-mode-dock.json' "$NEST_STATE/home"; }
dock_pin() {
  local before="" before_order="" cur cur_order i
  # A dock that is not running reads the file at startup, so there is nothing
  # to wait for. One that is running rebuilds when the file changes; the card
  # changing is that rebuild -- and the card's *order* counts as changing too,
  # because pinning an app that is already running leaves the number of icons
  # and so the height alone.
  before="$(dock_box 2>/dev/null || true)"
  before_order="$(dock_order)"
  mkdir -p "$(dirname "$(dock_pinned_file)")"
  printf '%s\n' "$1" > "$(dock_pinned_file)"
  [ -n "$before" ] || return 0
  # A 100ms poll keeps the nest's command socket busy while the dock is
  # trying to commit the new card. The slower gap is the same wait.
  for i in $(seq 1 16); do
    cur="$(dock_box 2>/dev/null || true)"
    cur_order="$(dock_order)"
    if [ -n "$cur" ] && { [ "$cur" != "$before" ] || [ "$cur_order" != "$before_order" ]; }; then
      dock_settle
      return 0
    fi
    sleep 0.25
  done
  dock_settle
}

# Middle of a row in the dock's context menu. ROWS is the row-height list the test
# expects (26 for a row, 7 for a separator), so the click documents the structure
# it is aiming at. The card is 240 wide and sits left of the dock, aligned with
# the icon it was opened from.
dock_menu_row_point() { # ICON_INDEX ROW_INDEX "26 7 26 ..."
  local dx dy _ _
  read -r dx dy _ _ <<<"$(dock_box)"
  # The menu is a layer of its own and is not up in the same breath as the
  # click. Its width is the screen the card is placed against; the point is
  # meaningless until that width exists.
  local screen_w i
  # A 50ms poll keeps the nest's socket busy, and the menu's own commit then
  # waits behind it. A wider gap lets the layer finish mapping before the click.
  for i in $(seq 1 20); do
    screen_w="$(dock_layer_box x-mode-dock-menu 2>/dev/null | awk '{print $3}')"
    [ -n "$screen_w" ] && [ "$screen_w" -ge 100 ] && break
    screen_w=""
    sleep 0.25
  done
  [ -n "$screen_w" ] || fail "the dock menu did not open"
  python3 -c "
rows = [int(x) for x in '$3'.split()]
idx = $2
screen_w, dock_x, dock_y = $screen_w, $dx, $dy
gaps_out = 5           # Style.gapsOut: half of general:gaps_out
card_w, card_h, pad = 240, 12, 7
card_x = screen_w - gaps_out - 40 - card_w - gaps_out * 2
card_y = dock_y + $1 * 32            # aligned with the icon, minus the pad
offset = 6
for i in range(idx):
    offset += rows[i] + 2
print(card_x + card_w // 2, card_y + offset + rows[idx] // 2)
"
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
  WAYLAND_DISPLAY="$(nest_display)" X_MODE_POINTER_EXTENT="$(pointer_extent)" \
    "$POINTER_BIN" "$@"
}

pointer_move() { pointer move "$1" "$2"; }
pointer_click() { pointer click "$1" "$2" "${3:-left}"; }
pointer_drag() { pointer drag "$1" "$2" "$3" "$4" "${5:-left}"; }
pointer_press() { pointer button "${1:-left}" press; }
pointer_release() { pointer button "${1:-left}" release; }

# --- screenshots --------------------------------------------------------------
# What a scenario cannot ask Hyprland about, because it is only pixels: whether a
# titlebar, a tab or the snap preview was actually drawn. grim talks to the nest,
# so the picture is of the nested compositor and not of the desktop the user is
# sitting in front of.
# grim blocks until the nest presents a frame. A covered nest presents one when
# the host rule is applied while grim is already waiting; a frame that lands
# before grim subscribes is missed, and another does not follow. The attempt
# is capped so a missed poke fails the test instead of hanging the run. The
# rule stays rendering: turning it off here is what left every later layer
# commit in that nest uncommitted.
nest_screenshot() { # FILE
  local attempt gpid
  for attempt in 1 2 3 4; do
    env WAYLAND_DISPLAY="$(nest_display)" timeout 4 grim "$1" >/dev/null 2>&1 &
    gpid=$!
    sleep 0.2
    nest_host_rule true
    if wait "$gpid"; then
      nest_host_lower
      return 0
    fi
  done
  nest_host_lower
  fail "grim could not capture the nest"
}

# Used to push every nest under the other windows after a screenshot. That
# covers them, and a covered window on this workspace never gets a frame, so
# the dock inside stops committing. A titlebar click then hits whatever is
# painted on top of those pixels, which is Chrome or Zed. Leave the stacking
# alone: the nests stay where they mapped, and only a click focuses one.
nest_host_lower() {
  :
}

# Number of pixels that differ between two shots. magick prints the count
# followed by the normalised value in brackets, so only the leading number is
# taken.
image_diff() { # FILE_A FILE_B
  local out
  out="$(magick compare -metric AE "$1" "$2" null: 2>&1 || true)"
  # Only the leading count: with alpha the number can come out fractional, and the
  # normalised value follows in brackets.
  printf '%s' "$out" | sed -n 's/^\([0-9][0-9]*\).*/\1/p' 
}

# --- keyboard ----------------------------------------------------------------
# Press a chord in the nest, e.g. key super+alt+left, key alt+tab, key o. Only
# chords are needed: a single name is a chord of one.
key() {
  WAYLAND_DISPLAY="$(nest_display)" "$KEYBOARD_BIN" "$@"
}

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

# Middle of a window's titlebar: the bar occupies bar_height above the window box.
titlebar_point() { # CLASS -> "X Y"
  local bh
  bh="$(bar_height)"
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$1' and c['mapped']:
        print(c['at'][0] + c['size'][0] // 2, c['at'][1] - $bh // 2)
        break"
}

gaps_out() { nest_query option general:gaps_out 4; }

border_size() { nest_query option general:border_size 2; }
