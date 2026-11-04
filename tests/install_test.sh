#!/usr/bin/env bash
# install.sh's bar-workspace step is the one place that rewrites a file Omarchy
# owns, and the shape of that file is not ours to assume: Omarchy 4.0.6 ships a
# different, 2 KB Workspaces.qml with none of the anchors the patch rewrites.
# A mismatch used to take the whole install down rather than skip the step --
# the `if [ $? -ne 0 ]` guard after the patch could never run under
# `set -euo pipefail`, so the script died there, before it wired hyprland.lua,
# and left the pack installed but inert. This pins both behaviours: a widget
# that does not match warns and leaves nothing behind, a widget that matches is
# patched.
#
# install.sh is sourced for the step; running it is what installs, so the step
# has to be reachable on its own.
#
# The second half pins the other half of the same promise: do_install builds the
# plugin first "so doing it before we touch any config keeps a failed build from
# leaving a half-installed pack behind". It does not: manifest_reset empties the
# install manifest at the top of do_install, and a failed build exits right after
# -- so a reinstall that dies in the build leaves installed.txt empty, and
# `uninstall.sh` then deletes nothing and reports success while the pack is
# still on disk. That is the reported failure this reproduces (see do_install).
. "$(dirname "$0")/lib.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home/.config" "$TMP/src"
export HOME="$TMP/home"
export XDG_CONFIG_HOME="$TMP/home/.config"
export XDG_STATE_HOME="$TMP/home/.local/state"

# shellcheck disable=SC1091
. "$REPO_DIR/install.sh"

PLUGINS_DIR="$TMP/plugins"
WORKSPACES_SRC="$TMP/src/Workspaces.qml"
DEST="$PLUGINS_DIR/$WORKSPACES_PLUGIN"

# 1. A widget without the anchors (the 4.0.6 shape): the step gives up, and the
#    install keeps going. Run in a subshell that has `set -e` on, because that is
#    how the installer runs it -- inside an `if` or a `||` list the failure would
#    be swallowed and the bug would not show.
printf '%s\n' 'import QtQuick' 'Item {' '  moduleName: "omarchy.workspaces"' '}' > "$WORKSPACES_SRC"
( set -e; workspaces_bar_install ) >"$TMP/out" 2>&1
status=$?
[ "$status" -eq 0 ] || fail "a widget without the anchors aborted the install (exit $status) instead of warning: $(cat "$TMP/out")"
[ -d "$DEST" ] && fail "a widget without the anchors still left $DEST behind"
grep -q "changed shape" "$TMP/out" || fail "a widget without the anchors did not say why the step was skipped: $(cat "$TMP/out")"

# 2. A widget with the anchors (the 4.5 shape): patched into the pack's copy.
#    The fixture carries the glyph block exactly as install.sh matches it -- real
#    characters, since those are what the installed widget holds.
python3 - "$WORKSPACES_SRC" <<'PY'
import sys

text = '''import QtQuick

Item {
  moduleName: "omarchy.workspaces"

  function modeGlyph(mode) {
    if (mode === "scrolling") return "\U000f0765"
    if (mode === "floating") return "\U000f0536"
    return "\U000f14fb"
  }

  var command = "omarchy-hyprland-workspace-layout-toggle"
}
'''
open(sys.argv[1], "w").write(text)
PY
( set -e; workspaces_bar_install ) >"$TMP/out2" 2>&1
status=$?
[ "$status" -eq 0 ] || fail "the step failed on a widget it can patch (exit $status): $(cat "$TMP/out2")"
[ -f "$DEST/Workspaces.qml" ] || fail "a widget with the anchors was not patched: $(cat "$TMP/out2")"
grep -qF 'moduleName: "x-mode.workspaces"' "$DEST/Workspaces.qml" || fail "the patched widget kept Omarchy's module name"
grep -qF ' next"' "$DEST/Workspaces.qml" || fail "the patched widget does not run the pack's layout cycle"
[ -f "$DEST/manifest.json" ] || fail "the patched widget has no manifest"

echo "  ok   the bar-workspace step skips a widget it cannot patch, and patches one it can"

# --- a failed hyprbars build must not take the install manifest with it -------
#
# Everything below runs do_install itself, twice. It is run in a child of this
# test, never in it: do_install exits on a failed build, and the first half above
# has already set up this process's isolated dirs. The child sources the real
# ./install.sh, and only then overrides `HERE` to a fixture tree whose
# hyprbars/build.sh fails -- the installer's paths are already computed by then,
# so the build the install runs is the fixture's and everything else it would
# write stays this test's.
#
# Not one other step of the install may run: the success path builds, unloads and
# *loads* the plugin through hyprctl, which is the live session, and a test never
# touches that. So the compositor and the shell are stubbed in the child
# (fix_hypr_instance above all: it reads the real $XDG_RUNTIME_DIR), and every
# other step that would build, copy, wire or load is replaced by a no-op. Nothing
# in the child can therefore reach the session or the repo, and what is left to
# assert is exactly what do_install wrote before it died: the manifest, and the
# fact that the configs were never reached.
#
# Neither run is in an `if` or a `||` list: `set -e` is on, as it is in the
# installer, and the status is the child's exit.
INSTALL_SRC="$REPO_DIR/install.sh"
[ -f "$INSTALL_SRC" ] || fail "install.sh is not in the repo ($INSTALL_SRC)"
cd "$TMP" || fail "could not cd to $TMP"

# The fixture tree the child installs *from*: the build that fails, and nothing
# the rest of do_install could copy (only an empty quickshell/ so the for loop
# expands to nothing).
FIXTURE="$TMP/fixture"
mkdir -p "$FIXTURE/hyprbars" "$FIXTURE/quickshell" "$FIXTURE/hypr/x-mode"
cat > "$FIXTURE/hyprbars/build.sh" <<'SH'
#!/usr/bin/env bash
# Expected to fail: this is the build a failed install dies in. The marker it
# drops is how the test tells "the build was reached" from "the child never got
# that far" -- without it, an early exit could pass a manifest assertion.
set -euo pipefail
printf 'build attempted\n' >> "${X_TEST_BUILD_MARKER:?}"
echo ">> fixture build.sh: cannot compile hyprbars.cpp" >&2
exit 1
SH
chmod +x "$FIXTURE/hyprbars/build.sh"

cat > "$TMP/child.sh" <<'CHILD'
#!/usr/bin/env bash
# One do_install, in its own process: it takes the whole installer down when the
# build fails, so it cannot share a shell with the assertions.
set -euo pipefail
installer="$1"
fixture="$2"
name="$3"   # reinstall: a manifest is there and has to come through byte for byte
            # first:     no manifest is there, and the failed build must not create one

# shellcheck disable=SC1090
. "$installer"

# From the installer's own source: the fixture is what it installs from.
HERE="$fixture"
HYPRBARS_SO="$fixture/hyprbars/hyprbars.so"
X_MODE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-x-mode"
X_MODE_MANIFEST="$X_MODE_STATE_DIR/installed.txt"
INSTALL_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-x-mode-install.log"

hyprctl()            { echo "hyprctl $* (stubbed)"; }
fix_hypr_instance()  { :; }
hyprbars_loaded()    { return 1; }
mapped_hyprbars()    { :; }
unwire_pack()        { :; }
unload_hyprbars()    { return 0; }
release_hyprbars()   { :; }
sentinel_add()       { :; }
early_add()          { :; }
sentinel_remove()    { :; }
menu_write()         { :; }
workspaces_bar_install() { :; }
copy_tree()          { :; }
plugin_remove()      { :; }
plugin_enabled()     { return 0; }
omarchy()            { echo "omarchy $* (stubbed)"; }
omarchy-shell()      { echo "omarchy-shell $* (stubbed)"; }
omarchy-launch-shell()   { echo "omarchy-launch-shell (stubbed)"; }
omarchy-restart-shell()  { echo "omarchy-restart-shell (stubbed)"; }
pgrep()              { return 0; }
ensure_shell()       { :; }
sleep()              { :; }

# The one step that must not be stubbed away: the build fails, and the install
# is supposed to die there -- before it forgets what is already installed.
log "test: do_install ($name)"
do_install
echo "x-mode test: do_install returned success with a failed hyprbars build" >&2
exit 0
CHILD

export X_TEST_BUILD_MARKER="$TMP/build-attempts"
: > "$X_TEST_BUILD_MARKER"

# x-mode looks installed: a manifest, and a hyprland.lua the pack is wired into.
mkdir -p "$X_MODE_STATE_DIR" "$HYPR"
printf '%s\n' \
  '-- user config' \
  "$X_MODE_BEGIN" \
  "$X_MODE_LOAD" \
  "$X_MODE_END" \
  > "$HYPR/hyprland.lua"
cp "$HYPR/hyprland.lua" "$TMP/hyprland.lua.before"

# Run in a subshell so the child's exit is caught and not this script's: the
# status is the test's to read, and `fail` is what reports it.
run_do_install() { # NAME
  local name="$1" out="$TMP/$1.out" status=0
  ( set -e; bash "$TMP/child.sh" "$INSTALL_SRC" "$FIXTURE" "$name" ) >"$out" 2>&1 || status=$?
  RUN_OUT="$out"
  RUN_STATUS="$status"
}

# Each attempt has to have got as far as the build and said why it stopped; a
# child that never reached the build would satisfy a manifest assertion for the
# wrong reason (nothing installed is nothing truncated), and a do_install that
# changed its wording would stop being pinned to this failure.
check_failed_build() { # NAME ATTEMPT
  local out="$RUN_OUT" attempt="$2"
  [ "$RUN_STATUS" -ne 0 ] || fail "$1: do_install returned success with a failed hyprbars build: $(cat "$out")"
  [ "$(grep -c '^build attempted$' "$X_TEST_BUILD_MARKER")" -ge "$attempt" ] \
    || fail "$1: do_install never reached the failing hyprbars build (attempt $attempt): $(cat "$out")"
  grep -qF 'hyprbars build failed; aborting before installing configs' "$out" \
    || fail "$1: do_install did not report the failed hyprbars build: $(cat "$out")"
}

dump_manifest() { # LABEL
  echo "  $1" >&2
  if [ -f "$X_MODE_MANIFEST" ]; then
    sed 's/^/    manifest: /' "$X_MODE_MANIFEST" >&2
    [ -s "$X_MODE_MANIFEST" ] || echo "    manifest: (empty)" >&2
  else
    echo "    manifest: $X_MODE_MANIFEST does not exist" >&2
  fi
}

# 3. Reinstall: the manifest of the install that is there survives the failed
#    build, byte for byte -- that file is how uninstall knows what to remove.
printf '%s\n' \
  "$TMP/pack/quickshell/x-mode" \
  "$TMP/pack/hypr/x-mode" \
  "$HOME/.local/share/hyprbars/x-mode-hyprbars.so" \
  "$TMP/pack/hypr/x-mode" \
  > "$X_MODE_MANIFEST"
cp "$X_MODE_MANIFEST" "$TMP/manifest.before"
run_do_install reinstall
check_failed_build reinstall 1
if ! cmp -s "$TMP/manifest.before" "$X_MODE_MANIFEST"; then
  echo "  reinstall: do_install emptied the install manifest before its build" >&2
  echo "  expected manifest:" >&2
  sed 's/^/    manifest: /' "$TMP/manifest.before" >&2
  dump_manifest "actual manifest:"
  fail "a failed reinstall build wiped $X_MODE_MANIFEST: $(cat "$RUN_OUT")"
fi

# 4. First install: there is no manifest to keep, and the failed build has to
#    leave it that way -- an empty installed.txt is a manifest that says "this
#    install owns nothing", and an uninstall then removes nothing and calls
#    itself done with the pack still on disk.
rm -f "$X_MODE_MANIFEST"
run_do_install first
check_failed_build first 2
if [ -e "$X_MODE_MANIFEST" ]; then
  dump_manifest "actual manifest:"
  fail "a failed first-install build created $X_MODE_MANIFEST: $(cat "$RUN_OUT")"
fi

echo "  ok   a failed hyprbars build keeps the install manifest it found (and creates none)"

# A failed build is also meant to abort *before* configs are touched, which is
# the reason do_install gives: Hyprland's config and the wiring in it are only
# written after the plugin is there. The bar-workspace step above wrote into
# $TMP/plugins, never into the isolated $HYPR this check watches.
if ! cmp -s "$TMP/hyprland.lua.before" "$HYPR/hyprland.lua"; then
  echo "  expected hyprland.lua:" >&2
  sed 's/^/    hyprland.lua: /' "$TMP/hyprland.lua.before" >&2
  echo "  actual hyprland.lua:" >&2
  sed 's/^/    hyprland.lua: /' "$HYPR/hyprland.lua" >&2
  fail "a failed hyprbars build still rewrote $HYPR/hyprland.lua"
fi
[ -e "$HYPR/x-mode" ] && fail "a failed hyprbars build still copied the pack's config into $HYPR/x-mode"

echo "  ok   a failed hyprbars build leaves the Hyprland config it found alone"

cd "$REPO_DIR" || true
