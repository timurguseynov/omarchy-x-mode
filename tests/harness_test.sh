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

# A finished run's status file names the pi session that started it, so another
# agent (Goose, a second pi session) does not wake up for it. A run with no
# session id -- a terminal, Goose -- stays unstamped, and a watcher that only
# accepts its own id ignores that file.
ASYNC="$TESTS_DIR/async.sh"
LOG="$TMP/xmode-test-harness.log"
printf '%s\n' '== nest ok' > "$LOG"
printf '%s\n' none > "$LOG.pid"

PI_SESSION_ID=pi-session-one bash "$ASYNC" watch harness "$LOG"
assert_eq "$(head -n1 "$LOG.status")" "session: pi-session-one" \
  "a run started from a pi session stamps the status file with that session"
grep -q '^log: ' "$LOG.status" || fail "the stamped status file still has the log path"

unset PI_SESSION_ID
bash "$ASYNC" watch harness "$LOG"
assert_eq "$(head -n1 "$LOG.status" | grep -c '^session: ')" 0 \
  "a run with no session id does not stamp the status file"
grep -q '^log: ' "$LOG.status" || fail "an unstamped status file still has the log path"

echo "  ok   async.sh stamps a status file only when a pi session started the run"

# The installer must never write over, or delete, a .so Hyprland has loaded.
# Hyprland maps the plugin into its own address space and runs its code in place,
# so the file has to be gone from the compositor's memory before it is touched:
# a plain `./uninstall.sh && ./install.sh` used to delete the loaded .so with the
# pack's Lua still calling into it, and the next focus change segfaulted the
# compositor and took the whole session down (coredump 1419, 2026-10-24).
#
# Checked by reading the scripts, not by running them: the failure is a dead
# compositor, and an assertion cannot outlive it. What is pinned is the order
# the incident broke -- unwire, reload, unload, then copy or remove.
INSTALL="$REPO_DIR/install.sh"
BUILD="$REPO_DIR/hyprbars/build.sh"

# build.sh produces the artifact in the repo; only install.sh places it, and it
# never names the installed directory or $HOME.
if grep -qE '^[^#]*(DEST=|\$\{?HOME)' "$BUILD"; then
  fail "hyprbars/build.sh writes into the installed plugin directory: it would write over a loaded .so"
fi
grep -qE '^\s*install -m644 .*hyprbars\.so.*\$HYPRBARS_SO' "$INSTALL" \
  || fail "install.sh no longer copies the plugin into place"

line_of() { # PATTERN FILE
  grep -nE -- "$1" "$2" | head -n1 | cut -d: -f1
}

# do_uninstall: the sentinel comes out and Hyprland reloads before the plugin is
# unloaded, and the shell plugins (whose layer surfaces walk the input path into
# the pack's Lua) go last.
uninstall_block="$TMP/do_uninstall.sh"
sed -n '/^do_uninstall() {/,/^}/p' "$INSTALL" > "$uninstall_block"
unwire=$(line_of 'sentinel_remove "\$HYPR/hyprland\.lua"' "$uninstall_block")
reload=$(line_of 'hyprctl reload' "$uninstall_block")
unload=$(line_of 'hyprctl plugin unload "\$HYPRBARS_SO"' "$uninstall_block")
shells=$(line_of 'plugin_remove "\$id"' "$uninstall_block")
for v in unwire reload unload shells; do
  [ -n "${!v}" ] || fail "do_uninstall lost its $v step"
done
[ "$unwire" -lt "$reload" ] || fail "do_uninstall reloads before it unwires the pack: the Lua state still points into the plugin"
[ "$reload" -lt "$unload" ] || fail "do_uninstall unloads the plugin before reloading without the pack"
[ "$unload" -lt "$shells" ] || fail "do_uninstall removes the shell plugins before the plugin is unloaded"

# do_install: the copy happens after the unload, never over a mapped file.
install_block="$TMP/do_install.sh"
sed -n '/^do_install() {/,/^}/p' "$INSTALL" > "$install_block"
load_unload=$(line_of 'hyprctl plugin unload "\$HYPRBARS_SO"' "$install_block")
copy=$(line_of 'install -m644 .*\$HYPRBARS_SO' "$install_block")
[ -n "$load_unload" ] || fail "do_install no longer unloads the old plugin"
[ -n "$copy" ] || fail "do_install no longer copies the plugin into place"
[ "$load_unload" -lt "$copy" ] || fail "do_install copies the plugin over a loaded .so"

echo "  ok   the installer unloads the plugin before it copies or removes the .so"
