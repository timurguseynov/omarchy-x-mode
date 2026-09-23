#!/usr/bin/env bash
# omarchy-x-mode installer.
#
# Additive by design: it only creates files in its own namespace (tim.*,
# x-mode.lua, x-mode/) and makes a single, sentinel-marked edit to
# ~/.config/hypr/hyprland.lua. Uninstall removes exactly what it created and
# leaves the user's own config untouched.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

# Install manifest: the exact list of paths we created, so uninstall removes only
# our own files and never touches user content.
X_MODE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-x-mode"
X_MODE_MANIFEST="${X_MODE_STATE_DIR}/installed.txt"
manifest_reset() { mkdir -p "$X_MODE_STATE_DIR"; : > "$X_MODE_MANIFEST"; }
manifest_add() { mkdir -p "$X_MODE_STATE_DIR"; printf '%s\n' "$1" >> "$X_MODE_MANIFEST"; }

# The single sentinel block we add to hyprland.lua (removed verbatim on uninstall).
X_MODE_BEGIN='-- >>> omarchy-x-mode >>>'
X_MODE_END='-- <<< omarchy-x-mode <<<'
X_MODE_LOAD='dofile((os.getenv("HOME") or "") .. "/.config/hypr/x-mode.lua")'
sentinel_present() { grep -qF -e "$X_MODE_BEGIN" "$1" 2>/dev/null; }
# Drop trailing blank lines so reinstall/uninstall does not accumulate gaps.
sentinel_trim() {
  [ -f "$1" ] || return 0
  python3 - "$1" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_text(p.read_text().rstrip("\n") + "\n")
PY
}
sentinel_remove() {
  if [ -f "$1" ]; then
    sed -i "/^${X_MODE_BEGIN}$/,/^${X_MODE_END}$/d" "$1"
    sentinel_trim "$1"
  fi
}
sentinel_add() {
  [ -f "$1" ] || return 0
  sentinel_remove "$1"
  # One blank line before the block; trim already cleared leftover gaps.
  printf '\n%s\n%s\n%s\n' "$X_MODE_BEGIN" "$X_MODE_LOAD" "$X_MODE_END" >> "$1"
}

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
HYPR="$CONFIG/hypr"
PLUGINS_DIR="$CONFIG/omarchy/plugins"
WITH_HYPRBARS=1

# Our patched plugin gets its own file name so it never clobbers a stock
# hyprbars the user may already have. A stock one found loaded is disabled on
# install and re-enabled on uninstall (recorded in $PRIOR_HYPRBARS).
HYPRBARS_DIR="$HOME/.local/share/hyprbars"
HYPRBARS_SO="$HYPRBARS_DIR/x-mode-hyprbars.so"
STOCK_HYPRBARS_SO="$HYPRBARS_DIR/hyprbars.so"
PRIOR_HYPRBARS="$X_MODE_STATE_DIR/prior-hyprbars"
PRIOR_WINDOWS="$X_MODE_STATE_DIR/prior-windows.json"

# Omarchy's CLI needs OMARCHY_PATH; an ssh command doesn't source the profile.
export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn\033[0m %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: ./install.sh [install|uninstall|status] [--no-hyprbars]

  install      (default) copy plugins + config, enable plugins, build hyprbars
  uninstall    remove everything the installer created
  status       show what is installed

Options:
  --no-hyprbars   skip building/installing the patched hyprbars plugin
EOF
}

copy_file() { # src dst
  mkdir -p "$(dirname "$2")"
  cp -f "$1" "$2"
  manifest_add "$2"
}

copy_tree() { # src_dir dst_dir
  rm -rf "$2"
  mkdir -p "$(dirname "$2")"
  cp -R "$1" "$2"
  manifest_add "$2"
}

plugin_enabled() { # id
  python3 - "$CONFIG/omarchy/shell.json" "$1" <<'PY'
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if sys.argv[2] in [p.get("id") for p in cfg.get("plugins", [])] else 1)
PY
}

do_install() {
  manifest_reset

  # Snapshot the open windows so uninstall can put them back the way they were
  # before the pack floated/grouped them. Keep the first snapshot across
  # reinstalls (uninstall removes the state dir, so a clean cycle re-snapshots).
  if [ ! -f "$PRIOR_WINDOWS" ] && hyprctl clients -j >/dev/null 2>&1; then
    hyprctl clients -j | python3 -c '
import json, sys
out = []
for c in json.load(sys.stdin):
    if not c.get("mapped"):
        continue
    out.append({
        "address": c.get("address"),
        "class": c.get("class"),
        "title": c.get("title"),
        "workspace": (c.get("workspace") or {}).get("name"),
        "floating": bool(c.get("floating")),
        "at": c.get("at"),
        "size": c.get("size"),
        "grouped": len(c.get("grouped") or []),
        "pinned": bool(c.get("pinned")),
        "fullscreen": c.get("fullscreen"),
    })
print(json.dumps(out))
' > "$PRIOR_WINDOWS" 2>/dev/null || rm -f "$PRIOR_WINDOWS"
  fi

  # Compile first. The patched hyprbars build is the slow, failure-prone step
  # and it writes nothing until it succeeds, so doing it before we touch any
  # config keeps a failed build from leaving a half-installed pack behind.
  if ((WITH_HYPRBARS)); then
    log "building patched hyprbars"
    if ! "$HERE/hyprbars/build.sh"; then
      warn "hyprbars build failed; aborting before installing configs"
      warn "re-run with --no-hyprbars to install without the patched titlebar"
      exit 1
    fi
    manifest_add "$HYPRBARS_SO"

    # If the user already has a stock hyprbars loaded, disable it and remember
    # the path so uninstall can re-enable it. `plugin unload` prints
    # "plugin not loaded" when that exact path isn't loaded.
    if [ -f "$STOCK_HYPRBARS_SO" ] && [ "$(hyprctl plugin unload "$STOCK_HYPRBARS_SO" 2>/dev/null || true)" != "plugin not loaded" ]; then
      mkdir -p "$X_MODE_STATE_DIR"
      printf '%s\n' "$STOCK_HYPRBARS_SO" > "$PRIOR_HYPRBARS"
      log "disabled existing hyprbars (will re-enable on uninstall)"
    fi

    log "loading patched hyprbars"
    hyprctl plugin unload "$HYPRBARS_SO" >/dev/null 2>&1 || true
    hyprctl plugin load "$HYPRBARS_SO" >/dev/null 2>&1 || warn "could not load hyprbars now (it will load on next login)"
    # Before either reload: the config spreads the already-open windows across
    # the left and right halves, then deletes the marker. Whichever of the two
    # reloads parses the new config first does the arrange; the other, and
    # every reload after, leaves windows where the user put them.
    mkdir -p "$X_MODE_STATE_DIR"
    : > "$X_MODE_STATE_DIR/arrange"
    log "reloading Hyprland to activate hyprbars"
    hyprctl reload >/dev/null 2>&1 || true
  fi

  log "installing shell plugins"
  # Migrate from the old two-plugin layout (tim.dock + tim.snap-preview).
  for old in tim.dock tim.snap-preview; do
    omarchy plugin remove "$old" --yes >/dev/null 2>&1 || true
    rm -rf "$PLUGINS_DIR/$old"
  done
  for d in "$HERE"/quickshell/*/; do
    copy_tree "$d" "$PLUGINS_DIR/$(basename "$d")"
  done
  omarchy-shell -q shell rescanPlugins 2>/dev/null || warn "shell not running; enable the plugins later"
  for d in "$HERE"/quickshell/*/; do
    omarchy plugin enable "$(basename "$d")" >/dev/null 2>&1 || true
  done
  # The running shell rewrites shell.json too; re-check after a moment and
  # retry anything that didn't stick.
  sleep 1
  for d in "$HERE"/quickshell/*/; do
    id="$(basename "$d")"
    plugin_enabled "$id" || omarchy plugin enable "$id" >/dev/null 2>&1 || warn "could not enable $id"
  done

  log "installing Hyprland config"
  # Clean up the old drop-in / script layout from earlier installs.
  rm -f "$HYPR"/conf.d/5x-x-mode-*.lua 2>/dev/null || true
  rm -rf "$HYPR/x-mode" 2>/dev/null || true
  copy_file "$HERE/hypr/x-mode.lua" "$HYPR/x-mode.lua"

  log "wiring x-mode into hyprland.lua"
  sentinel_add "$HYPR/hyprland.lua"

  # Recreate the marker: the reload above may already have consumed it, and
  # this reload is the one that parses the config just installed.
  mkdir -p "$X_MODE_STATE_DIR"
  : > "$X_MODE_STATE_DIR/arrange"

  log "reloading Hyprland"
  hyprctl reload >/dev/null 2>&1 || true

  # The catch-all float rule only applies to new windows, so windows opened
  # while the pack wasn't active stay tiled. Dragging a tiled window makes
  # Hyprland float it and center it under the cursor (looks like a jump), so
  # re-float anything still tiled. Skip fullscreen windows.
  if hyprctl clients -j >/dev/null 2>&1; then
    log "re-floating open windows"
    while IFS= read -r addr; do
      [ -n "$addr" ] || continue
      hyprctl dispatch "hl.dsp.window.float({ action = \"enable\", window = \"address:$addr\" })" >/dev/null 2>&1 || true
    done < <(hyprctl clients -j | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    if c.get("mapped") and not c.get("floating") and not c.get("fullscreen"):
        print(c["address"])
')
  fi

  # The config's own arrange runs on a timer that races this re-float, so do
  # it again now that every window is actually floating. Same shuffle, and it
  # only changes which window lands on which half.
  hyprctl eval 'if x_mode and x_mode.arrange_halves then x_mode.arrange_halves() end' >/dev/null 2>&1 || true

  # `rescanPlugins` + `plugin enable` only update the registry: a plugin that is
  # already loaded keeps the QML instance it was created with, so updated files
  # (and a stale icon index) would not take effect until a manual restart.
  log "restarting the shell to load the updated plugins"
  OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}" omarchy-restart-shell >/dev/null 2>&1 || warn "could not restart the shell; run 'omarchy-restart-shell' to load the plugins"

  log "installed omarchy-x-mode"
}

do_uninstall() {
  log "disabling/removing shell plugins"
  for id in x-mode tim.dock tim.snap-preview; do
    omarchy plugin remove "$id" --yes >/dev/null 2>&1 || rm -rf "$PLUGINS_DIR/$id"
  done
  omarchy-shell -q shell rescanPlugins 2>/dev/null || true

  log "unwiring x-mode from hyprland.lua"
  sentinel_remove "$HYPR/hyprland.lua"

  log "unloading patched hyprbars"
  # Deleting the .so does not unload it; unload explicitly so titlebars go away.
  hyprctl plugin unload "$HYPRBARS_SO" >/dev/null 2>&1 || true

  # Re-enable a stock hyprbars that was loaded before we replaced it.
  if [ -f "$PRIOR_HYPRBARS" ]; then
    prior="$(head -n1 "$PRIOR_HYPRBARS" 2>/dev/null || true)"
    if [ -n "$prior" ] && [ -f "$prior" ]; then
      log "re-enabling previous hyprbars"
      hyprctl plugin load "$prior" >/dev/null 2>&1 || warn "could not re-enable $prior"
    fi
  fi

  log "removing installed files"
  rm -f "$HYPR"/conf.d/5x-x-mode-*.lua 2>/dev/null || true
  rm -rf "$HYPR/x-mode" 2>/dev/null || true
  if [ -f "$X_MODE_MANIFEST" ]; then
    tac "$X_MODE_MANIFEST" | while IFS= read -r p; do
      [ -n "$p" ] || continue
      rm -rf -- "$p"
    done
  fi

  hyprctl reload >/dev/null 2>&1 || true
  sleep 0.5

  # Put windows back the way they were before the pack floated/grouped them:
  # ungroup everything, restore floating windows to their old position/size, and
  # tile the rest (including windows opened while the pack was installed).
  if [ -f "$PRIOR_WINDOWS" ]; then
    log "restoring window state"
    python3 - "$PRIOR_WINDOWS" <<'PY' || true
import json, subprocess, sys, time
prior = json.load(open(sys.argv[1]))
try:
    cur = json.loads(subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True).stdout)
except Exception:
    cur = []
prior_by = {p.get("address"): p for p in prior}

def disp(expr):
    subprocess.run(["hyprctl", "dispatch", expr], capture_output=True)
    # Dispatches on the same window race if sent back-to-back; let each settle.
    time.sleep(0.12)

for c in cur:
    addr = c.get("address")
    if not addr:
        continue
    w = f"address:{addr}"
    if c.get("grouped"):
        disp(f'hl.dsp.window.move({{ out_of_group = true, window = "{w}" }})')
    p = prior_by.get(addr)
    # Windows opened while the pack was installed (no snapshot) go back to tiling.
    want_float = bool(p.get("floating")) if p is not None else False
    if want_float:
        if not c.get("floating"):
            disp(f'hl.dsp.window.float({{ action = "enable", window = "{w}" }})')
        at = p.get("at") or [0, 0]
        size = p.get("size") or [0, 0]
        disp(f'hl.dsp.window.resize({{ x = {int(size[0])}, y = {int(size[1])}, relative = false, window = "{w}" }})')
        disp(f'hl.dsp.window.move({{ x = {int(at[0])}, y = {int(at[1])}, relative = false, window = "{w}" }})')
    elif c.get("floating"):
        disp(f'hl.dsp.window.float({{ action = "disable", window = "{w}" }})')
PY
  fi

  OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}" omarchy-restart-shell >/dev/null 2>&1 || true
  rm -rf "$X_MODE_STATE_DIR"
  log "uninstalled omarchy-x-mode"
}

do_status() {
  echo "state dir: $X_MODE_STATE_DIR"
  echo "manifest:  $X_MODE_MANIFEST"
  if [ -f "$X_MODE_MANIFEST" ]; then
    echo "installed paths:"
    sed 's/^/  /' "$X_MODE_MANIFEST"
  else
    echo "not installed"
  fi
  if sentinel_present "$HYPR/hyprland.lua"; then
    echo "wired: yes"
  else
    echo "wired: no"
  fi
}

cmd="install"
for a in "$@"; do
  case "$a" in
    install | uninstall | status) cmd="$a" ;;
    --no-hyprbars) WITH_HYPRBARS=0 ;;
    -h | --help) usage; exit 0 ;;
    *)
      echo "unknown argument: $a" >&2
      usage
      exit 2
      ;;
  esac
done

case "$cmd" in
  install) do_install ;;
  uninstall) do_uninstall ;;
  status) do_status ;;
esac
