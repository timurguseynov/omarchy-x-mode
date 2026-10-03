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

case "${1:-}" in
  run)
    label="${2:-}" && shift 2 || true
    if [ -z "$label" ] || [ $# -eq 0 ]; then
      usage
      exit 2
    fi
    log="$LOG_DIR/xmode-test-$label.log"
    : > "$log"
    nohup env NEST_JOBS=5 NEST_WORKSPACE=5 "$@" > "$log" 2>&1 &
    echo "$!" > "$log.pid"
    printf 'started %s (pid %s) -> %s\n' "$label" "$!" "$log"
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
    ;;
  *)
    usage
    exit 2
    ;;
esac
