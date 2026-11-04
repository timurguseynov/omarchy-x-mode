#!/usr/bin/env bash
# Shrink a finished nest log the way the agent used to do by hand.
#
#   bash tests/funnel.sh /run/user/1000/xmode-test-suite.log
#
# The suite itself still runs every scenario once. This reads that log and:
#   1. re-runs every FAIL name together;
#   2. leaves a name that passes there alone;
#   3. re-runs each name that fails again, by itself, once.
# A single failed name is run once, not twice. The receipt printed here is only
# the final disposition, so a failure that later passed is not counted twice.
# The original log is not rewritten. Stage output is kept beside this run.
# A source that failed without a scenario FAIL line is left red: nothing is
# re-run and it is not reported as nest ok. NOT RUN is re-run, but only an ok
# line clears a name. A Hyprland warning is copied through and keeps the run red.
# FUNNEL_RUNNER replaces tests/nest/run.sh in the shrink test.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
log="${1:-}"
[ -n "$log" ] && [ -f "$log" ] || { echo "usage: tests/funnel.sh <finished-log>" >&2; exit 2; }
grep -qaE '^== ' "$log" || { echo "log has no finished summary: $log" >&2; exit 2; }

export NEST_JOBS=5 NEST_WORKSPACE=5
stage="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/xmode-funnel.XXXXXX")"
printf 'funnel from: %s\n' "$log"
printf 'funnel stages: %s\n' "$stage"

mapfile -t parsed < <(python3 - "$log" <<'PY'
import re, sys
strip = re.compile(r'\x1b\[[0-9;]*m')
fail = re.compile(r'^  FAIL +(\S+)(?: +\(slot \d+\))?$')
missing = re.compile(r'^  NOT RUN +(\S+)(?: +\(slot \d+\))?$')
seen, warns = [], []
summary = ''
for raw in open(sys.argv[1], errors='replace'):
    line = strip.sub('', raw).rstrip('\n')
    if line.startswith('== '):
        summary = line
    hit = fail.match(line) or missing.match(line)
    if hit and hit.group(1) not in seen:
        if not re.fullmatch(r'[A-Za-z0-9_./-]+', hit.group(1)):
            raise SystemExit('unsafe scenario name: ' + hit.group(1))
        seen.append(hit.group(1))
        print(('FAIL' if fail.match(line) else 'NOTRUN') + '\t' + hit.group(1))
    elif 'hyprland reported an error' in line:
        warns.append(line)
        print('WARN\t' + line)
if summary in ('== all ok', '== nest ok') and not seen and not warns:
    print('CLEAN')
PY
) || exit 2
names=()
warnings=()
clean=0
for row in "${parsed[@]}"; do
  kind="${row%%$'\t'*}"
  rest="${row#*$'\t'}"
  case "$kind" in
    FAIL|NOTRUN) names+=("$rest") ;;
    WARN) warnings+=("$rest") ;;
    CLEAN) clean=1 ;;
  esac
done

if [ "${#names[@]}" -eq 0 ]; then
  if [ "$clean" -eq 1 ]; then
    echo "  ok   no_failed_scenarios"
    echo "== nest ok"
    exit 0
  fi
  printf 'funnel: source failed without a scenario line to re-run\n'
  printf '%s\n' "${warnings[@]}"
  echo "== nest failed"
  exit 1
fi

run_names() { # outfile name...
  local out="$1"
  shift
  if [ -n "${FUNNEL_RUNNER:-}" ]; then
    "$FUNNEL_RUNNER" "$@" >"$out" 2>&1
  else
    bash "$HERE/nest/run.sh" "$@" >"$out" 2>&1
  fi
}

passed() { grep -qE "^  ok +${1}( |$)" "$2"; }
declare -A left
if [ "${#names[@]}" -eq 1 ]; then
  printf 'funnel solo: %s\n' "${names[0]}"
  out="$stage/solo-${names[0]//\//_}"
  run_names "$out" "${names[0]}" || true
  passed "${names[0]}" "$out" || left["${names[0]}"]=1
else
  printf 'funnel group: %s\n' "${#names[@]}"
  run_names "$stage/group" "${names[@]}" || true
  for name in "${names[@]}"; do
    passed "$name" "$stage/group" || left["$name"]=1
  done
  for name in "${names[@]}"; do
    [ -n "${left[$name]:-}" ] || continue
    printf 'funnel solo: %s\n' "$name"
    out="$stage/solo-${name//\//_}"
    run_names "$out" "$name" || true
    if passed "$name" "$out"; then
      unset "left[$name]"
    else
      left["$name"]=1
    fi
  done
fi

red=0
for name in "${names[@]}"; do
  if [ -n "${left[$name]:-}" ]; then
    printf '  FAIL %s\n' "$name"
    red=1
  else
    printf '  ok   %s\n' "$name"
  fi
done
if [ "${#warnings[@]}" -gt 0 ]; then
  printf '%s\n' "${warnings[@]}"
  red=1
fi
if [ "$red" -eq 0 ]; then
  echo "== nest ok"
  exit 0
fi
echo "== nest failed"
exit 1
