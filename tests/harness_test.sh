#!/usr/bin/env bash
# The wait helpers have to actually wait.
#
# A condition handed in as text -- the documented form -- has to be evaluated on
# every poll. `wait_until 5 [ "$(f)" = 1 ]` is the trap: the caller's shell expands
# the substitution once, before the first check, so the wait is a single check, and
# a compositor step that took a moment longer looks like a flake instead of a wait
# that ran out. Functions and quoted text both evaluate per poll; this pins that,
# and that a condition which never holds still gives up on time.
#
# A plain shell: it sources lib.sh for the helpers and needs no nest.
. "$(dirname "$0")/lib.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
MARK="$TMP/mark"

# Something that arrives late, the way a compositor step does.
( sleep 0.6; : > "$MARK" ) &
writer=$!

wait_until 3 '[ -e "$MARK" ]' || { kill "$writer" 2>/dev/null; fail "wait_until did not wait for a file that appeared after 0.6s"; }
wait "$writer" 2>/dev/null || true

# The same thing with a function, which is the shorter spelling scenarios use.
late() { [ -e "$MARK" ]; }
wait_until 3 late || fail "wait_until did not wait for a function condition that became true"

# A condition that never holds must fail, and only after the time it was asked for.
start=$(date +%s%N)
if wait_until 1 '[ -e "$TMP/never" ]'; then
  fail "wait_until reported success for a condition that never holds"
fi
elapsed_ms=$(( ($(date +%s%N) - start) / 1000000 ))
[ "$elapsed_ms" -ge 900 ] || fail "wait_until gave up after ${elapsed_ms}ms instead of the second it was asked for"

echo "  ok   wait_until re-evaluates its condition, and gives up on time"
