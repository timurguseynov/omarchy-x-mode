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

# The runner needs the paths too: the queue of scenarios and the lock its report
# lines are printed under both live in NEST_ROOT. Each worker computes its own
# again with its slot.
nest_paths
NEST_QUEUE="$NEST_ROOT/queue"
NEST_QUEUE_AT="$NEST_ROOT/queue.at"
NEST_QUEUE_LOCK="$NEST_ROOT/queue.lock"

# Keep a newly mapped nest from taking the user's focus or clicks, and park it
# on NEST_WORKSPACE when one is given. In shared mode there is no nest window on
# this desktop at all and the rule is not applied. The rule is removed when this
# process exits, including after a failed run.
nest_host_rule_on || { nest_host_rule_off; exit 1; }
# NEST_HOST=shared: one Hyprland of our own on a vkms card, started before the
# slots and killed with the run. In session mode this is a no-op.
nest_host_start || exit 1
trap 'nest_host_rule_off; nest_host_stop' EXIT

report() { # STATUS NAME FILE
  flock 9
  if [ "$1" = ok ]; then
    echo "  ${GREEN}ok${RESET}   $2"
  else
    echo "  ${RED}FAIL${RESET} $2${NEST_SLOT:+ (slot $NEST_SLOT)}"
  fi
  # What was actually reported, by name: the end-of-run check diffs the chosen
  # scenarios against this, so a scenario taken from the queue and then lost (a
  # worker killed, a nest that took its shell with it) cannot leave the run
  # looking green having run less than it was asked to.
  [ -n "${NEST_ROOT:-}" ] && printf '%s\n' "$2" >> "$NEST_ROOT/reported"
  [ -s "$3" ] && sed 's/^/       /' "$3"
} 9>"$NEST_ROOT/print.lock"

# A scenario that was chosen and never reported. Not a failure of the scenario
# itself -- it may never have started -- but the run did not run what it was
# asked to, so it is not green either.
report_notrun() { # NAME REASON
  flock 9
  printf '  %sNOT RUN%s %s\n' "$YELLOW" "$RESET" "$1"
  printf '%s\n' "$2" | sed 's/^/       /'
} 9>"$NEST_ROOT/print.lock"

# Hyprland reports an error the suite used to ignore in two places, and both hid a
# real one: a config that threw while parsing is in `hyprctl configerrors` (a
# missing field aborted the parse halfway and the run stayed green), and a Lua
# callback that threw while the session ran is an `[ERR] ... error in ... callback`
# line in its log (a timer that threw every tick, so a pass never ran). Neither is
# a scenario failure, so they are reported as WARN, once each, with the scenario
# they first showed up in.
report_warn() { # NAME TEXT
  flock 9
  printf '  %sWARN%s %s: hyprland reported an error\n' "$YELLOW" "$RESET" "$1"
  printf '%s\n' "$2" | sed 's/^/       /'
} 9>"$NEST_ROOT/print.lock"

nest_errors() {
  {
    # A config that threw while parsing (a missing field aborted the parse halfway
    # and the run stayed green).
    nest_ctl configerrors 2>/dev/null
    # A Lua callback that threw while the session ran -- a timer that fires every
    # tick, a keybind, an event handler -- which Hyprland logs as
    # `ERR from <module> ]: [Lua] error in timer callback: ...`. The pattern stays
    # on Lua and callback lines so the backend's own ERR noise (aquamarine) is not
    # reported as the pack's fault.
    grep -ahE '\[Lua\]|error in .*callback' \
      "$NEST_LOG" "$NEST_RUNTIME"/hypr/*/hyprland.log 2>/dev/null
  } | sed '/^[[:space:]]*$/d'
}

# The scenarios come off one queue instead of being split into a list per slot.
# A slot whose nest will not come up returns without having reached the rest of
# its scenarios; with the queue they stay where they are and the next worker to
# ask for one takes them.
queue_fill() {
  : > "$NEST_QUEUE"
  for t in "${chosen[@]}"; do
    printf '%s\n' "$t" >> "$NEST_QUEUE"
  done
  printf '0\n' > "$NEST_QUEUE_AT"
}

next_test() { # prints the next scenario, non-zero when the queue is empty
  local at total
  exec 8>"$NEST_QUEUE_LOCK"
  flock 8
  total="$(wc -l < "$NEST_QUEUE")"
  at="$(cat "$NEST_QUEUE_AT" 2>/dev/null || echo 0)"
  if [ "$at" -ge "$total" ]; then
    flock -u 8
    exec 8>&-
    return 1
  fi
  at=$((at + 1))
  printf '%s\n' "$at" > "$NEST_QUEUE_AT"
  flock -u 8
  exec 8>&-
  sed -n "${at}p" "$NEST_QUEUE"
}

worker() { # SLOT
  export NEST_SLOT="$1"
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
  # Starting it again is a new compositor. The first attempt returns instead of
  # exiting, which is what lets this second start happen; a second miss is this
  # slot's to lose, and it is told apart from a failing scenario by the status:
  # 2 is "no nest", so the runner starts the slot again for the queue.
  if ! nest_start; then
    echo "nest bar missed on slot $NEST_SLOT, starting again" >&2
    nest_stop
    sleep 0.5
    nest_start || return 2
  fi
  local t name out rc=0 errors_seen check_errors
  # Anything the nest already reports at startup -- the first parse happens before
  # the plugin exists, so its plugin:* keys are unknown then -- is the baseline:
  # it is not news, and it is not a scenario's fault.
  errors_seen="$(mktemp)"
  nest_errors >> "$errors_seen"
  check_errors() { # NAME
    local errs line
    errs="$(nest_errors)"
    [ -n "$errs" ] || return 0
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      grep -Fqx -- "$line" "$errors_seen" && continue
      printf '%s\n' "$line" >> "$errors_seen"
      report_warn "$1" "$line"
    done <<<"$errs"
  }
  while t="$(next_test)"; do
    name="$(name_of "$t")"
    nest_clean
    out="$(mktemp)"
    retry="$(mktemp)"
    if bash "$t" >"$out" 2>&1; then
      report ok "$name" "$out"
    else
      # What the nest looked like when it failed, before nest_clean takes it
      # apart. A bare "FAIL: <assertion>" is all a red run says otherwise.
      nest_dump >> "$out" 2>&1
      # One more pass on the same nest: three of them drop the occasional dock
      # event, and this is that event arriving. The first pass is kept either
      # way -- a flake that passes here is still a flake, and its dump is the
      # only record of what it looked like.
      nest_clean
      if bash "$t" >"$retry" 2>&1; then
        { echo "(first pass failed, this one passed; what it saw then:)"
          # "FAIL" is what the run's counters and its list of failing scenarios
          # match on: a flake that passed must not show up in either.
          sed -e 's/^/  /' -e 's/FAIL/failed/' "$out"; } >> "$retry"
        report ok "$name" "$retry"
      else
        # The retry's assertion, and the first pass under it: that one carries
        # the nest dump, which is the point of keeping it.
        { echo "(first pass, and what the nest looked like then:)"; sed 's/^/  /' "$out"; } >> "$retry"
        report fail "$name" "$retry"
        rc=1
      fi
    fi
    check_errors "$name"
    rm -f "$out" "$retry"
  done
  rm -f "$errors_seen"
  dock_stop
  nest_stop
  return "$rc"
}

# One process per slot, outliving the workers in it: a worker that could not
# bring its nest up returns, and this starts it again so the queue keeps moving.
slot_runner() { # SLOT
  local tries=0 rc
  while :; do
    worker "$1"
    rc=$?
    case $rc in
      2)
        tries=$((tries + 1))
        if [ "$tries" -ge 3 ]; then
          # Not a failure by itself: the scenarios this slot did not reach stay
          # in the queue for the others, and whatever is left at the end is what
          # the run reports. This is only here so the operator can see it.
          echo "slot $1 gave up after $tries nests" >&2
          return 0
        fi
        # The bar that did not reserve is the nest's output not being registered
        # yet (`bar reserved '0' with the output '0x0'`). Retrying straight away
        # runs into the same state, so each retry waits longer than the last.
        sleep $((tries * 3))
        ;;
      *) return "$rc" ;;
    esac
  done
}

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
  nest_host_stop
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

queue_fill
# Reported scenarios, by name, for the end-of-run diff (see report()).
: > "$NEST_ROOT/reported"

for s in $(seq 0 $((JOBS - 1))); do
  # A second apart. Mapping several nests in the same instant makes the
  # host configure one of them as 0x0, and that nest's output never comes up.
  [ "$s" -gt 0 ] && sleep 1
  set -m
  slot_runner "$s" &
  set +m
  pids+=($!)
done
for pid in "${pids[@]}"; do
  wait "$pid" || fail=1
done

# The host outlives every scenario, so it goes now (the trap covers a run that
# stopped early).
nest_host_stop

# Anything chosen that was never reported: a slot whose nest would not come up
# leaves scenarios behind, and a scenario can also be taken from the queue and
# lost with the worker that held it. The diff is against what was *reported*, not
# against how far the queue counter got, because the counter moves when a
# scenario is taken and says nothing about whether it ran. A run that did not run
# what it was asked to is not green, and it names what is missing.
for t in "${chosen[@]}"; do
  name="$(name_of "$t")"
  grep -Fqx -- "$name" "$NEST_ROOT/reported" && continue
  report_notrun "$name" "never reported: the nest on its slot did not come up, or it was lost with the worker"
  fail=1
done
rm -f "$NEST_ROOT/reported"

# The scenarios' own lines say what ran. This is the one line that says whether
# the layer came out clean, for a run started on its own -- the suite above
# prints its own summary, and until now a nest run just stopped talking.
if [ "$fail" = 0 ]; then
  echo "== nest ok"
else
  echo "== nest failed"
fi
exit "$fail"
