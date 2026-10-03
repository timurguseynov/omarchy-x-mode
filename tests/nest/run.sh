#!/usr/bin/env bash
# Start one nested Hyprland and run nest scenarios against it.
#
#   run.sh                  every scenario
#   run.sh pointer          scenarios whose name contains "pointer"
#   run.sh snap group       several at once
#   run.sh integration/no_gaps_keeps_border
#
# nest_clean() runs between files, so a single scenario is as isolated as it is
# in a full run. NEST_JOBS (default 3) is how many nests run at once; the build
# is once. NEST_WORKSPACE, when set to a number, maps those windows on that
# workspace and leaves the view where it is. Selecting one scenario still
# skips the other nests.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib.sh"

all=()
for t in "$HERE"/*_test.sh "$HERE"/integration/*_test.sh; do
  [ -e "$t" ] || continue
  all+=("$t")
done

name_of() {
  local t="$1" name
  name="$(basename "$t" .sh)"
  case "$t" in "$HERE"/integration/*) name="integration/$name" ;; esac
  printf '%s' "$name"
}

chosen=()
if [ "$#" -gt 0 ]; then
  for want in "$@"; do
    found=0
    for t in "${all[@]}"; do
      name="$(name_of "$t")"
      case "$name" in
        *"$want"*) found=1
          # Keep the order of `all` and never run a file twice.
          case " ${chosen[*]} " in *" $t "*) ;; *) chosen+=("$t") ;; esac
          ;;
      esac
    done
    [ "$found" = 1 ] || { echo "no nest test matches '$want'" >&2; exit 2; }
  done
else
  chosen=("${all[@]}")
fi

[ "${#chosen[@]}" -gt 0 ] || { echo "no nest tests found in $HERE" >&2; exit 2; }

# One nest per worker. The dock follows Hyprland's event socket, so the nests
# do not have to take turns on hyprctl for the client list. NEST_JOBS=1 is the
# single-nest run.
JOBS="${NEST_JOBS:-3}"
[ "$JOBS" -gt "${#chosen[@]}" ] && JOBS="${#chosen[@]}"
[ "$JOBS" -ge 1 ] || JOBS=1

build_plugin
build_pointer
build_keyboard
build_nestq
export NEST_SKIP_BUILD=1

# Keep a newly mapped nest from taking focus, and pin it so a later focus
# does not cover it. NEST_WORKSPACE drops the pin and maps the nests on that
# workspace instead. A covered nest on this workspace gets no frames, so its
# bar and clients never commit. The rule and the 1px tick are
# removed when this process exits, including after a failed run. A click on a
# nest's titlebar focuses that nest. Placing another nest does not hand focus
# back.
nest_host_rule_on || { nest_host_rule_off; exit 1; }
trap 'nest_host_rule_off' EXIT

report() { # STATUS NAME FILE
  flock 9
  if [ "$1" = ok ]; then
    echo "  ${GREEN}ok${RESET}   $2"
  else
    echo "  ${RED}FAIL${RESET} $2 (slot $NEST_SLOT)"
  fi
  [ -s "$3" ] && sed 's/^/       /' "$3"
} 9>"$NEST_ROOT/print.lock"

worker() { # SLOT TEST...
  export NEST_SLOT="$1"
  shift
  SIG=""
  nest_paths
  # The runner gives each worker a process group of its own (job control around
  # the fork), which is what lets one kill take this worker and its scenarios.
  # Job control itself is turned back off here: with it on, the shell puts every
  # background job in a group of its own, and the `setsid` the nest, the bar and
  # the dock are started with then has to fork, which changes how they come up.
  set +m
  # A missed bar used to exit the worker, so the retry below never ran and
  # the compositor stayed up. The trap still covers a real exit.
  trap 'dock_stop; nest_stop' EXIT
  # A nest whose bar never reserves has no geometry the scenarios can trust.
  # Starting it again is a new compositor. The first attempt returns instead
  # of exiting, which is what lets this second start happen.
  if ! nest_start; then
    echo "nest bar missed on slot $NEST_SLOT, starting again" >&2
    nest_stop
    sleep 0.5
    nest_start || return 1
  fi
  local t name out rc=0
  for t in "$@"; do
    name="$(name_of "$t")"
    nest_clean
    out="$(mktemp)"
    if bash "$t" >"$out" 2>&1; then
      report ok "$name" "$out"
    else
      # Three nests on this machine drop the occasional dock event. A second
      # pass on the same nest is that event arriving; a real failure fails
      # again. The first output is discarded so the report is the one that
      # still failed.
      nest_clean
      if bash "$t" >"$out" 2>&1; then
        report ok "$name" "$out"
      else
        report fail "$name" "$out"
        rc=1
      fi
    fi
    rm -f "$out"
  done
  dock_stop
  nest_stop
  return "$rc"
}

# Round-robin, so one worker does not draw every dock scenario.
slots=()
for i in $(seq 0 $((JOBS - 1))); do
  slots[$i]=""
done
i=0
for t in "${chosen[@]}"; do
  s=$((i % JOBS))
  slots[$s]="${slots[$s]} $t"
  i=$((i + 1))
done

fail=0
pids=()

# Ctrl+C has to take the nests with it. The nests are in sessions of their own
# (setsid), so the terminal's signal never reaches them, and the workers are
# asynchronous jobs: a run stopped in the terminal otherwise leaves the
# compositors on screen and the workers printing into a terminal nobody is
# reading. Job control is what lets one kill take a worker, its scenario and
# everything the scenario started; it also stops the shell from ignoring SIGINT
# in the worker, which it does for asynchronous jobs when job control is off.
abort() {
  trap - INT TERM HUP
  local pid f s
  for pid in ${pids[@]:+"${pids[@]}"}; do
    kill -- "-$pid" 2>/dev/null || true
  done
  sleep 0.5
  for pid in ${pids[@]:+"${pids[@]}"}; do
    kill -9 -- "-$pid" 2>/dev/null || true
  done
  # A worker killed before its own trap ran leaves its files behind, and the
  # nest is what a person is looking at when the run stops, so it is killed
  # from here too.
  for s in $(seq 0 $((JOBS - 1))); do
    NEST_SLOT="$s"
    nest_paths
    for f in "$NEST_STATE/pid" "$NEST_STATE/dock.pid" "$NEST_STATE/bar.pid" "$NEST_STATE/ipc.pid"; do
      [ -f "$f" ] || continue
      pid="$(cat "$f" 2>/dev/null)" || continue
      [ -n "$pid" ] || continue
      kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    done
  done
  exit 130
}
trap abort INT TERM HUP

for s in $(seq 0 $((JOBS - 1))); do
  # A second apart. Mapping several nests in the same instant makes the
  # host configure one of them as 0x0, and that nest's output never comes up.
  [ "$s" -gt 0 ] && sleep 1
  # shellcheck disable=SC2086 - the slot list is a list of test paths
  set -m
  worker "$s" ${slots[$s]} &
  set +m
  pids+=($!)
done
for pid in "${pids[@]}"; do
  wait "$pid" || fail=1
done
exit "$fail"
