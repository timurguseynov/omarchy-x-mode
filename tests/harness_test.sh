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
grep -qE '^\s*install -m644 .*hyprbars\.so.*"\$HYPRBARS_SO" ' "$INSTALL" \
  || fail "install.sh no longer copies the plugin into place"
# A second file that is swapped in at the next login never gets loaded into the
# session that just installed. The loaded plugin is released, then the same path
# is written. Deleting a leftover from an older install is not staging one.
if grep -qE 'install .*"\$HYPRBARS_SO\.new"' "$INSTALL"; then
  fail "install.sh still stages the plugin as .new instead of unloading it"
fi
if grep -q 'windows_open' "$INSTALL"; then
  fail "install.sh still skips the unload while windows are open"
fi

line_of() { # PATTERN FILE
  grep -nE -- "$1" "$2" | head -n1 | cut -d: -f1
}

# Install releases the plugin in one call: unwire, reload, bars off, unload.
# Uninstall has to tile in between the reload and the unload, so those two
# halves are their own functions and release_hyprbars is just both, in order.
unwire_block="$TMP/unwire_pack.sh"
sed -n '/^unwire_pack() {/,/^}/p' "$INSTALL" > "$unwire_block"
unwire=$(line_of 'sentinel_remove "\$HYPR/hyprland\.lua"' "$unwire_block")
reload=$(line_of 'hyprctl reload' "$unwire_block")
[ -n "$unwire" ] && [ -n "$reload" ] || fail "unwire_pack lost a step"
[ "$unwire" -lt "$reload" ] || fail "unwire_pack reloads before it unwires the pack"

unload_block="$TMP/unload_hyprbars.sh"
sed -n '/^unload_hyprbars() {/,/^}/p' "$INSTALL" > "$unload_block"
bars=$(line_of 'hyprbars = \{ enabled = false \}' "$unload_block")
unload=$(line_of 'hyprctl plugin unload "\$HYPRBARS_SO"' "$unload_block")
[ -n "$bars" ] && [ -n "$unload" ] || fail "unload_hyprbars lost a step"
[ "$bars" -lt "$unload" ] || fail "unload_hyprbars unloads hyprbars while its bars are still on the windows"
# plugin list only prints the name. Omarchy's titlebars.so is also "hyprbars",
# so an install that only unloads the pack path stops and never wires the pack.
grep -q 'mapped_hyprbars' "$unload_block" || fail "unload_hyprbars does not unload a hyprbars that is mapped under another path"

release_block="$TMP/release_hyprbars.sh"
sed -n '/^release_hyprbars() {/,/^}/p' "$INSTALL" > "$release_block"
rel_unwire=$(line_of 'unwire_pack' "$release_block")
rel_unload=$(line_of 'unload_hyprbars' "$release_block")
[ -n "$rel_unwire" ] && [ -n "$rel_unload" ] || fail "release_hyprbars no longer unwires then unloads"
[ "$rel_unwire" -lt "$rel_unload" ] || fail "release_hyprbars unloads before the pack's Lua is gone"

# A terminal left open across a logout keeps the previous compositor's
# signature. hyprctl then talks to a dead socket, the plugin looks unloaded,
# and the script deletes the .so the live session still has mapped. The
# signature is corrected before any hyprctl, and the shell restart inherits it
# instead of waiting out its deadline against a compositor that is not there.
fix_block="$TMP/fix_hypr_instance.sh"
sed -n '/^fix_hypr_instance() {/,/^}/p' "$INSTALL" > "$fix_block"
grep -q '\.socket\.sock' "$fix_block" || fail "fix_hypr_instance does not check that the signature's socket exists"
grep -q 'HYPRLAND_INSTANCE_SIGNATURE' "$fix_block" || fail "fix_hypr_instance does not retarget the signature"

uninstall_block="$TMP/do_uninstall.sh"
sed -n '/^do_uninstall() {/,/^}/p' "$INSTALL" > "$uninstall_block"
fix_u=$(line_of 'fix_hypr_instance' "$uninstall_block")
unwire_u=$(line_of 'unwire_pack' "$uninstall_block")
restore_u=$(line_of 'restoring window state' "$uninstall_block")
unload_u=$(line_of 'unload_hyprbars' "$uninstall_block")
shells=$(line_of 'plugin_remove "\$id"' "$uninstall_block")
for v in fix_u unwire_u restore_u unload_u shells; do
  [ -n "${!v}" ] || fail "do_uninstall lost its $v step"
done
# Tiling after the unload is what hung: float-disable walks the decorations of
# a plugin that is already gone, and that hyprctl dispatch never returns.
[ "$fix_u" -lt "$unwire_u" ] || fail "do_uninstall talks to Hyprland before correcting a dead signature"
[ "$unwire_u" -lt "$restore_u" ] || fail "do_uninstall tiles windows before the pack's Lua is gone, so the float rule puts them straight back"
[ "$restore_u" -lt "$unload_u" ] || fail "do_uninstall unloads hyprbars before the windows are tiled"
[ "$unload_u" -lt "$shells" ] || fail "do_uninstall removes the shell plugins before hyprbars is unloaded"

install_block="$TMP/do_install.sh"
sed -n '/^do_install() {/,/^}/p' "$INSTALL" > "$install_block"
fix_i=$(line_of 'fix_hypr_instance' "$install_block")
release_i=$(line_of 'release_hyprbars' "$install_block")
[ -n "$fix_i" ] || fail "do_install does not correct a dead Hyprland signature"
[ "$fix_i" -lt "$release_i" ] || fail "do_install releases the plugin before correcting a dead signature"
copy=$(line_of 'install -m644 .*"\$HYPRBARS_SO" ' "$install_block")
[ -n "$release_i" ] || fail "do_install no longer releases the old plugin"
[ -n "$copy" ] || fail "do_install no longer copies the plugin into place"
[ "$release_i" -lt "$copy" ] || fail "do_install copies the plugin over a loaded .so"

echo "  ok   the installer unloads the plugin before it copies or removes the .so"
