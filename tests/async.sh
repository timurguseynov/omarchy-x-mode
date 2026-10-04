#!/usr/bin/env bash
# Start a test run in the background, and check on it later. For an agent session:
# a tool call that waits for a run gets killed part-way, which reads as a hang and
# wastes the run, and the suite takes minutes. So the run is detached, its output
# goes to one known log per label, and the check is a short command.
#
#   tests/async.sh run suite bash tests/run.sh
#   tests/async.sh run keys  bash tests/nest/run.sh key_pin digit_tabs
#   tests/async.sh status keys
#
# The nest runs get the sanctioned NEST_JOBS=5 NEST_WORKSPACE=5. Nothing here
# changes how a run behaves; it only decides who waits for it.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SELF="$HERE/$(basename "$0")"
LOG_DIR="${XDG_RUNTIME_DIR:-/tmp}"

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

# One place that says how a run is doing, so `status` and the status file a
# finished run leaves behind cannot disagree.
status_text() { # LABEL LOG
  local label="$1" log="$2" pid state
  pid="$(cat "$log.pid" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    state="running"
  elif grep -qaE "^== (all ok|nest ok|nest failed)" "$log"; then
    state="finished"
  else
    state="done, no summary line"
  fi
  printf '%s: %s\n' "$label" "$state"
  if grep -qaE "^== " "$log"; then
    grep -aE "^== " "$log" | tail -2
  else
    tail -3 "$log"
  fi
  printf 'ok: %s  FAIL: %s  WARN: %s\n' \
    "$(grep -ac $'\033\[32mok' "$log")" \
    "$(grep -ac FAIL "$log")" \
    "$(grep -ac 'hyprland reported an error' "$log")"
  grep -a "FAIL" "$log" | head -5
  # Hyprland's own errors: a parse that died and a Lua callback that threw. They
  # are not scenario failures, and they are not visible anywhere else -- the run
  # can be green while the pack's config threw halfway.
  grep -a "hyprland reported an error" "$log" | head -5
}

case "${1:-}" in
  run)
    label="${2:-}" && shift 2 || true
    if [ -z "$label" ] || [ $# -eq 0 ]; then
      usage
      exit 2
    fi
    log="$LOG_DIR/xmode-test-$label.log"
    : > "$log"
    rm -f "$log.status"
    # Both the run and its report are detached into sessions of their own. A
    # tool call that starts a run can be aborted, and a background child of that
    # shell would die with it: the run (nohup) used to survive while the status
    # writer did not, so a finished run reported nothing. `setsid -w` keeps the
    # wrapper alive for as long as the command, which is the pid the watcher
    # waits on.
    nohup setsid -w env NEST_JOBS=5 NEST_WORKSPACE=5 "$@" > "$log" 2>&1 &
    echo "$!" > "$log.pid"
    nohup setsid -w "$SELF" watch "$label" "$log" >/dev/null 2>&1 &
    printf 'started %s (pid %s) -> %s\n' "$label" "$(cat "$log.pid")" "$log"
    ;;
  watch) # internal: wait for a run and write its status file (used by `run`)
    label="${2:-}"
    log="${3:-}"
    pid="$(cat "$log.pid" 2>/dev/null || true)"
    if [ -n "$pid" ]; then
      while kill -0 "$pid" 2>/dev/null; do sleep 2; done
    fi
    # The run reports itself when it ends: `<log>.status` with the same text
    # `status` prints, plus the log path. The pi extension
    # .pi/extensions/test-status.ts turns it into a message.
    { printf 'log: %s\n' "$log"; status_text "$label" "$log"; } > "$log.status"
    ;;
  status)
    label="${2:-}"
    if [ -z "$label" ]; then
      usage
      exit 2
    fi
    log="$LOG_DIR/xmode-test-$label.log"
    if [ ! -f "$log" ]; then
      echo "no run logged for '$label' ($log)"
      exit 2
    fi
    status_text "$label" "$log"
    ;;
  *)
    usage
    exit 2
    ;;
esac
