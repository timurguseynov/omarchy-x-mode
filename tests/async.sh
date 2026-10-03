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
  elif grep -qaE "^== (all ok|nest failed)" "$log"; then
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
  printf 'ok: %s  FAIL: %s\n' "$(grep -ac $'\033\[32mok' "$log")" "$(grep -ac FAIL "$log")"
  grep -a "FAIL" "$log" | head -5
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
    nohup env NEST_JOBS=5 NEST_WORKSPACE=5 "$@" > "$log" 2>&1 &
    echo "$!" > "$log.pid"
    # The run reports itself when it ends: `<log>.status` with the same text
    # `status` prints, plus the log path. A watcher can take it from there (the
    # pi extension .pi/extensions/test-status.ts turns it into a message), and
    # nobody has to poll the run.
    (
      pid="$(cat "$log.pid")"
      while kill -0 "$pid" 2>/dev/null; do sleep 2; done
      { printf 'log: %s\n' "$log"; status_text "$label" "$log"; } > "$log.status"
    ) &
    printf 'started %s (pid %s) -> %s\n' "$label" "$(cat "$log.pid")" "$log"
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
