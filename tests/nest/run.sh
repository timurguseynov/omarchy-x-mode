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
# is once. Selecting one scenario still skips the other nests.
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

# Keep a newly mapped nest from taking focus, and pin it so the host does not
# fold every nest into one tab group. A hidden tab is not drawn, and a click
# on it leaves the keyboard on Chrome or Zed. The rule and the 1px tick are
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
for s in $(seq 0 $((JOBS - 1))); do
  # A second apart. Mapping several nests in the same instant makes the
  # host configure one of them as 0x0, and that nest's output never comes up.
  [ "$s" -gt 0 ] && sleep 1
  # shellcheck disable=SC2086 - the slot list is a list of test paths
  worker "$s" ${slots[$s]} &
  pids+=($!)
done
for pid in "${pids[@]}"; do
  wait "$pid" || fail=1
done
exit "$fail"
