#!/usr/bin/env bash
# Start one nested Hyprland and run nest scenarios against it.
#
#   run.sh                  every scenario
#   run.sh pointer          scenarios whose name contains "pointer"
#   run.sh snap group       several at once
#   run.sh integration/no_gaps_keeps_border
#
# nest_clean() runs between files, so a single scenario is as isolated as it is
# in a full run. NEST_JOBS (default 1) is how many nests run at once; the build
# is once. Selecting one scenario still skips the other nests. Extra nests on
# this machine drop dock events, which is why the default is one.
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

# One nest per worker. Raising NEST_JOBS runs several nests side by side. On
# this machine a second and third nest drop dock events, so the default is one
# and a parallel run is opt-in.
JOBS="${NEST_JOBS:-1}"
[ "$JOBS" -gt "${#chosen[@]}" ] && JOBS="${#chosen[@]}"
[ "$JOBS" -ge 1 ] || JOBS=1

build_plugin
build_pointer
build_keyboard
build_nestq
export NEST_SKIP_BUILD=1

# Remember who was focused and keep the nest toplevel from taking over. The
# rule is removed when this process exits, including after a failed run.
export NEST_HOST_FOCUS="$(nest_host_focus)"
nest_host_rule_on
trap 'nest_host_rule_off' EXIT

report() { # STATUS NAME FILE
  flock 9
  if [ "$1" = ok ]; then
    echo "  ${GREEN}ok${RESET}   $2"
  else
    echo "  ${RED}FAIL${RESET} $2"
  fi
  [ -s "$3" ] && sed 's/^/       /' "$3"
} 9>"$NEST_ROOT/print.lock"

worker() { # SLOT TEST...
  export NEST_SLOT="$1"
  shift
  SIG=""
  nest_paths
  # nest_bar_start fails with exit, which skips the nest_stop below and leaves
  # the compositor mapped on the host. The trap covers that path too.
  trap 'dock_stop; nest_stop' EXIT
  nest_start || return 1
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
  # A short stagger so three compositors do not map on the host in one instant.
  # That burst is what dropped a bar and pulled the nest forward.
  [ "$s" -gt 0 ] && sleep 0.4
  # shellcheck disable=SC2086 - the slot list is a list of test paths
  worker "$s" ${slots[$s]} &
  pids+=($!)
done
for pid in "${pids[@]}"; do
  wait "$pid" || fail=1
done
exit "$fail"
