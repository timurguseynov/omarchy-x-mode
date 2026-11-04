#!/usr/bin/env bash
# The suite reports a failure once. funnel.sh is the later shrink: the failed
# names together, then each name that failed again, alone. This drives it with
# a fake nest runner, so it never starts Hyprland.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

cat > "$TMP/runner" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FUNNEL_ARGS"
if [ "$#" -gt 1 ]; then
  mode=group
  bad="${FUNNEL_GROUP_FAIL:-}"
else
  mode=solo
  bad="${FUNNEL_SOLO_FAIL:-}"
fi
for name in "$@"; do
  case " $bad " in
    *" $name "*) printf '  FAIL %s (slot 1)\n' "$name" ;;
    *) printf '  ok   %s\n' "$name" ;;
  esac
done
if [ -n "$bad" ]; then echo "== nest failed"; exit 1; fi
echo "== nest ok"
exit 0
SH
chmod +x "$TMP/runner"

cat > "$TMP/full.log" <<'LOG'
== nest
  ok   integration/kept_test
  FAIL integration/a_test (slot 1)
  FAIL integration/b_test (slot 2)
  FAIL integration/c_test
  FAIL integration/d_test (slot 0)
  FAIL integration/e_test (slot 4)
  FAIL integration/f_test (slot 3)
== nest failed
LOG

export FUNNEL_ARGS="$TMP/args"
export FUNNEL_RUNNER="$TMP/runner"
export FUNNEL_GROUP_FAIL="integration/e_test integration/f_test"
export FUNNEL_SOLO_FAIL="integration/f_test"
: > "$FUNNEL_ARGS"

set +e
bash "$HERE/funnel.sh" "$TMP/full.log" >"$TMP/out" 2>"$TMP/err"
rc=$?
set -e
[ "$rc" -eq 1 ] || fail "a solo failure must stay red (exit $rc): $(cat "$TMP/out" "$TMP/err")"
grep -q 'integration/a_test integration/b_test integration/c_test integration/d_test integration/e_test integration/f_test' "$FUNNEL_ARGS" \
  || fail "the group stage did not re-run exactly the six failures: $(cat "$FUNNEL_ARGS")"
grep -qx 'integration/e_test' "$FUNNEL_ARGS" || fail "e was not re-run alone"
grep -qx 'integration/f_test' "$FUNNEL_ARGS" || fail "f was not re-run alone"
[ "$(wc -l < "$FUNNEL_ARGS")" -eq 3 ] || fail "expected one group run and two solo runs: $(cat "$FUNNEL_ARGS")"
grep -q '^  ok   integration/e_test$' "$TMP/out" || fail "a solo pass was not cleared"
grep -q '^  FAIL integration/f_test$' "$TMP/out" || fail "the solo failure was dropped"
grep -q '^== nest failed$' "$TMP/out" || fail "the funnel did not finish with a nest failure"
# Intermediate reds stay in the stage logs, not in the receipt.
[ "$(grep -c '^  FAIL ' "$TMP/out")" -eq 1 ] || fail "the receipt counted more than the surviving failure"

# Everything that fails together can still pass alone. That is a green funnel.
export FUNNEL_SOLO_FAIL=""
: > "$FUNNEL_ARGS"
set +e
bash "$HERE/funnel.sh" "$TMP/full.log" >"$TMP/out2" 2>"$TMP/err2"
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "solo passes must make the funnel green (exit $rc): $(cat "$TMP/out2")"
grep -q '^== nest ok$' "$TMP/out2" || fail "cleared failures did not finish nest ok"
grep -q '^  FAIL ' "$TMP/out2" && fail "a cleared failure stayed in the receipt"

# A single red name is one run, not a group followed by the same solo.
printf '  FAIL integration/only_test\n== nest failed\n' > "$TMP/one.log"
export FUNNEL_GROUP_FAIL=""
export FUNNEL_SOLO_FAIL=""
: > "$FUNNEL_ARGS"
bash "$HERE/funnel.sh" "$TMP/one.log" >"$TMP/out3" 2>"$TMP/err3" || fail "one passing scenario failed: $(cat "$TMP/out3" "$TMP/err3")"
[ "$(wc -l < "$FUNNEL_ARGS")" -eq 1 ] || fail "one failure was run more than once: $(cat "$FUNNEL_ARGS")"

# No nest failures means the runner is not started.
printf '== all ok\n  ok   unit\n' > "$TMP/clean.log"
: > "$FUNNEL_ARGS"
bash "$HERE/funnel.sh" "$TMP/clean.log" >"$TMP/out4" || fail "clean log was not green"
[ ! -s "$FUNNEL_ARGS" ] || fail "a clean log still started the nest"
grep -q '^== nest ok$' "$TMP/out4" || fail "clean log did not finish nest ok"

# auto.sh keeps the suite's own FAIL lines out of the receipt and shrinks them.
cat > "$TMP/suite" <<'SH'
#!/usr/bin/env bash
printf '  FAIL integration/a_test\n== nest failed\n'
exit 1
SH
chmod +x "$TMP/suite"
export XMODE_TEST_LOG="$TMP/auto-receipt"
export AUTO_SUITE="$TMP/suite"
export FUNNEL_GROUP_FAIL=""
export FUNNEL_SOLO_FAIL=""
: > "$FUNNEL_ARGS"
bash "$HERE/auto.sh" >"$TMP/auto.out" || fail "auto did not turn a solo pass into a green receipt: $(cat "$TMP/auto.out")"
grep -q '^  FAIL ' "$TMP/auto.out" && fail "the suite failure leaked into the auto receipt"
grep -q '^== nest ok$' "$TMP/auto.out" || fail "auto did not finish nest ok"
grep -q 'suite log:' "$TMP/auto.out" || fail "auto hid where the original red log went"
grep -q '^  FAIL integration/a_test$' "$XMODE_TEST_LOG.suite" || fail "the original failure was not kept"

# A red suite that names no scenario is not a nest pass.
cat > "$TMP/lint-suite" <<'SH'
#!/usr/bin/env bash
printf '== lint failed\n'
exit 1
SH
chmod +x "$TMP/lint-suite"
export AUTO_SUITE="$TMP/lint-suite"
set +e
bash "$HERE/auto.sh" >"$TMP/lint.out"
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "a lint failure became a green auto run: $(cat "$TMP/lint.out")"
grep -q '^== nest ok$' "$TMP/lint.out" && fail "a lint failure was reported as nest ok"
grep -q '^== all ok$' "$TMP/lint.out" && fail "a lint failure was reported as all ok"

# WARN and NOT RUN are not cleared by the absence of a FAIL line.
printf '  WARN integration/x_test: hyprland reported an error\n== nest failed\n' > "$TMP/warn.log"
: > "$FUNNEL_ARGS"
set +e
bash "$HERE/funnel.sh" "$TMP/warn.log" >"$TMP/warn.out"
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "a Hyprland warning became a green funnel"
grep -q '^== nest ok$' "$TMP/warn.out" && fail "a warning was reported as nest ok: $(cat "$TMP/warn.out")"
[ ! -s "$FUNNEL_ARGS" ] || fail "a warning started a nest rerun"

printf '  NOT RUN integration/missing_test\n== nest failed\n' > "$TMP/missing.log"
cat > "$TMP/notrun-runner" <<'SH'
#!/usr/bin/env bash
printf '  NOT RUN %s\n' "$1"
echo "== nest failed"
exit 1
SH
chmod +x "$TMP/notrun-runner"
export FUNNEL_RUNNER="$TMP/notrun-runner"
set +e
bash "$HERE/funnel.sh" "$TMP/missing.log" >"$TMP/missing.out"
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "NOT RUN was treated as a pass: $(cat "$TMP/missing.out")"
grep -q '^== nest ok$' "$TMP/missing.out" && fail "NOT RUN finished nest ok"
grep -qE '^  (FAIL|NOT RUN) integration/missing_test$' "$TMP/missing.out" || fail "NOT RUN disappeared from the receipt: $(cat "$TMP/missing.out")"

# A later ok does not erase a warning from the original run.
printf '  FAIL integration/only_test\n  WARN integration/only_test: hyprland reported an error\n== nest failed\n' > "$TMP/warn-fail.log"
export FUNNEL_RUNNER="$TMP/runner"
export FUNNEL_SOLO_FAIL=""
set +e
bash "$HERE/funnel.sh" "$TMP/warn-fail.log" >"$TMP/warn-fail.out"
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "a passing rerun cleared a Hyprland warning"
grep -q 'hyprland reported an error' "$TMP/warn-fail.out" || fail "the warning was dropped: $(cat "$TMP/warn-fail.out")"

# The nest runner colors its verdict. A pass hidden by those codes is not a failure.
cat > "$TMP/color-runner" <<'SH'
#!/usr/bin/env bash
printf '  \033[32mok\033[0m   %s\n' "$1"
echo '== nest ok'
SH
chmod +x "$TMP/color-runner"
printf '  FAIL integration/colored_test\n== nest failed\n' > "$TMP/color.log"
export FUNNEL_RUNNER="$TMP/color-runner"
bash "$HERE/funnel.sh" "$TMP/color.log" >"$TMP/color.out" || fail "a colored nest ok was counted as a failure: $(cat "$TMP/color.out")"
grep -q '^  ok   integration/colored_test$' "$TMP/color.out" || fail "the colored pass was not cleared: $(cat "$TMP/color.out")"
grep -q '^== nest ok$' "$TMP/color.out" || fail "a colored pass did not finish nest ok"

echo "  ok   funnel_shrinks_failures_without_hiding_the_original_log"
