#!/usr/bin/env bash
# Start one nested Hyprland and run nest scenarios against it.
#
#   run.sh                  every scenario
#   run.sh pointer          scenarios whose name contains "pointer"
#   run.sh snap group       several at once
#   run.sh integration/no_gaps_keeps_border
#
# One nest serves the whole run and nest_clean() runs between files, so a single
# scenario is as isolated as it is in a full run. The nest itself is the fixed
# cost (build, start Hyprland, load the plugin, wait for the bar), so selecting
# one scenario buys a focused report more than it buys wall time.
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

nest_start
trap 'dock_stop; nest_stop' EXIT

fail=0
for t in "${chosen[@]}"; do
  name="$(name_of "$t")"
  nest_clean
  if out="$(bash "$t" 2>&1)"; then
    echo "  ${GREEN}ok${RESET}   $name"
  else
    echo "  ${RED}FAIL${RESET} $name"
    printf '%s\n' "$out" | sed 's/^/       /'
    fail=1
  fi
done
exit "$fail"
