#!/usr/bin/env bash
# omarchy-x-mode installer.
#
# Additive by design: it only creates files in its own namespace (the
# ~/.config/hypr/x-mode directory) and makes a single, sentinel-marked edit to
# ~/.config/hypr/hyprland.lua. Uninstall removes exactly what it created and
# leaves the user's own config untouched -- including ~/.config/hypr/x-mode.json,
# the settings the panel writes, which lives next to the pack's directory rather
# than inside it so it survives an uninstall.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

# Install manifest: the exact list of paths we created, so uninstall removes only
# our own files and never touches user content.
X_MODE_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-x-mode"
X_MODE_MANIFEST="${X_MODE_STATE_DIR}/installed.txt"
manifest_reset() { mkdir -p "$X_MODE_STATE_DIR"; : > "$X_MODE_MANIFEST"; }
manifest_add() { mkdir -p "$X_MODE_STATE_DIR"; printf '%s\n' "$1" >> "$X_MODE_MANIFEST"; }

# The sentinel blocks we add to hyprland.lua (removed verbatim on uninstall).
# The early one has to run before Omarchy's workspace modes: her titlebars
# module queues its own hyprbars.so as soon as a workspace floats, and the
# pack's plugin is already that hyprbars. The block at the end loads the pack.
X_MODE_BEGIN='-- >>> omarchy-x-mode >>>'
X_MODE_END='-- <<< omarchy-x-mode <<<'
X_MODE_LOAD='dofile((os.getenv("HOME") or "") .. "/.config/hypr/x-mode/x-mode.lua")'
EARLY_BEGIN='-- >>> omarchy-x-mode-plugins >>>'
EARLY_END='-- <<< omarchy-x-mode-plugins <<<'
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
    sed -i "/^${X_MODE_BEGIN}$/,/^${X_MODE_END}$/d;/^${EARLY_BEGIN}$/,/^${EARLY_END}$/d" "$1"
    sentinel_trim "$1"
  fi
}
# Before require("default.hypr.omarchy"), so a reload does not queue her
# titlebars plugin. A keybinding scan dofiles this file with a stub hl; the
# pcall is what keeps that scan from dying on the wrap.
early_add() {
  [ -f "$1" ] || return 0
  python3 - "$1" "$EARLY_BEGIN" "$EARLY_END" <<'PY'
import pathlib, re, sys
path, begin, end = sys.argv[1:4]
file = pathlib.Path(path)
text = file.read_text()
text = re.sub(r"\n?" + re.escape(begin) + r".*?" + re.escape(end) + r"\n?", "\n", text, flags=re.S)
body = """%s
do
  local ok, load_plugin = pcall(function() return hl.plugin.load end)
  if ok and type(load_plugin) == "function" then
    hl.plugin.load = function(path)
      if type(path) == "string" and path:find("omarchy-hyprland-titlebars", 1, true) then
        return
      end
      return load_plugin(path)
    end
  end
end
%s
""" % (begin, end)
needle = 'require("default.hypr.omarchy")'
idx = text.find(needle)
if idx < 0:
    text = body + "\n" + text.lstrip("\n")
else:
    text = text[:idx] + body + "\n" + text[idx:]
file.write_text(text)
PY
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
# Omarchy merges a user extension into its menu; the pack adds one row to the
# Appearance -> Workspace Layout submenu there. Marked off, so an uninstall takes
# exactly its own block out of a file the user owns.
MENU_JSONC="$CONFIG/omarchy/extensions/omarchy-menu.jsonc"
MENU_BEGIN="// >>> omarchy-x-mode >>>"
MENU_END="// <<< omarchy-x-mode <<<"

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

# Every step goes to a log as well as the terminal, and the file is flushed line by
# line. The compositor can die in the middle of an install (unloading the plugin
# while the shell rebuilds its layers has done it twice), and that takes the
# terminal and everything it printed with it -- the log is then the only record of
# which step it was. It lives next to the state directory rather than inside it,
# because do_uninstall removes that directory.
INSTALL_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-x-mode-install.log"
# A plugin swap is only safe with no windows open: Hyprland runs the plugin's code
# in place, and its decorations hold listeners of their own. Unloading it with a
# window on screen has crashed the compositor twice (see the install log: the run
# stopped right after "loading patched hyprbars").
# Is a hyprbars loaded? The CLI prints the plugin's *name* and never the path it was
# loaded from (`hyprctl plugin list -j` has no file field), so matching on
# $HYPRBARS_SO silently answered "no" every time: install then copied over the
# loaded .so, and uninstall deleted it while it was still loaded -- the two ways
# this session has been crashed. The pack's own config unloads a stock
# `hyprbars.so` at startup, so "hyprbars listed" means the pack's in practice.
hyprbars_loaded() {
  hyprctl plugin list 2>/dev/null | grep -qi 'hyprbars'
}

windows_open() {
  hyprctl -j clients 2>/dev/null | grep -c '"mapped": *true' 2>/dev/null || echo 0
}

# Bring the shell back if it is not running. omarchy-restart-shell is silent (its
# output is dropped) and a restart that fails leaves the desktop with no bar and no
# dock at all -- which is exactly what a finished install looked like: the log ran
# to "restarting the shell" and the shell was not there afterwards.
ensure_shell() {
  pgrep -x quickshell >/dev/null 2>&1 && return 0
  warn "the shell is not running; starting it"
  OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}" omarchy-launch-shell >/dev/null 2>&1 || true
  local i
  for i in $(seq 1 50); do
    pgrep -x quickshell >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  warn "the shell did not start; run 'omarchy-launch-shell' by hand"
  return 0
}

# The menu row, written into Omarchy's user extension. Textual, not parsed: the file
# is JSONC with comments, and a JSON round-trip would throw them away. A block from an
# earlier install is replaced, and the row is inserted before the closing brace with a
# comma only when there is something in front of it.
menu_write() { # ACTION
  python3 - "$MENU_JSONC" "$MENU_BEGIN" "$MENU_END" "$1" <<'PY'
import re, sys

path, begin, end, action = sys.argv[1:5]
try:
    text = open(path).read()
except FileNotFoundError:
    text = "{\n}\n"

text = re.sub(r"\n?[ \t]*" + re.escape(begin) + r".*?" + re.escape(end), "", text, flags=re.S)

row = (
    '  "trigger.appearance.workspace-layout.xmode": {'
    '"icon":"","label":"X Mode","description":"The pack\'s floating desktop",'
    '"checked":"[[ $(' + action + ' default) == \\"xmode\\" ]]",'
    '"action":"' + action + ' default xmode"}'
)

idx = text.rstrip().rfind("}")
head, tail = text[:idx], text[idx:]
stripped = head.rstrip()
if not stripped.endswith(("{", ",")):
    stripped += ","
block = stripped + "\n  " + begin + "\n" + row + ",\n  " + end + "\n"
open(path, "w").write(block + tail)
PY
}

menu_remove() {
  [ -f "$MENU_JSONC" ] || return 0
  python3 - "$MENU_JSONC" "$MENU_BEGIN" "$MENU_END" <<'PY'
import re, sys

path, begin, end = sys.argv[1:4]
text = open(path).read()
new = re.sub(r"\n?[ \t]*" + re.escape(begin) + r".*?" + re.escape(end), "", text, flags=re.S)
if new != text:
    open(path, "w").write(new)
PY
}

log_file() {
  mkdir -p "$(dirname "$INSTALL_LOG")" 2>/dev/null || return 0
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$INSTALL_LOG" 2>/dev/null || true
}

# Everything the script writes goes to the log as well as the terminal -- including
# what an aborting command says. A step that dies takes the terminal with it (the
# session it runs in), and an error message nobody captured is how "uninstall just
# stops" looked: the log ended mid-step with no reason in it.
if [ -n "${BASH_VERSION:-}" ]; then
  exec > >(tee -a "$INSTALL_LOG") 2>&1
fi

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; log_file "step  $*"; }
warn() { printf '\033[1;33mwarn\033[0m %s\n' "$*" >&2; log_file "WARN  $*"; }

usage() {
  cat <<'EOF'
Usage: ./install.sh [install|uninstall|status]

  install      (default) copy plugins + config, enable plugins, build hyprbars
  uninstall    remove everything the installer created
  status       show what is installed
EOF
}

copy_tree() { # src_dir dst_dir
  rm -rf "$2"
  mkdir -p "$(dirname "$2")"
  cp -R "$1" "$2"
  manifest_add "$2"
}

# Remove one of our shell plugins and the backup the CLI leaves behind.
# `omarchy plugin remove` deletes a plugin folder outright only when it is a
# symlink or a git checkout; ours is a plain copy, so it moves the folder to
# .<id>.bak.<ts> instead -- one backup per install or uninstall, 172 of them
# after a few months of `./uninstall.sh && ./install.sh`. Those are copies of
# this pack, whose source is this repo, nothing reads them (the plugin scanner
# skips hidden folders) and they sit in Omarchy's own plugin directory, so drop
# the backups of our own ids. Plain rm when the CLI is not there at all.
plugin_remove() { # id
  omarchy plugin remove "$1" --yes >/dev/null 2>&1 || rm -rf "$PLUGINS_DIR/$1"
  rm -rf "${PLUGINS_DIR:?}/.$1.bak."* 2>/dev/null || true
}

plugin_enabled() { # id
  # The shell's registry is the answer, not shell.json: that file's `plugins`
  # array carries per-plugin settings, and a plugin enabled through the registry
  # need not appear in it at all. Asking the file said "not enabled" for a plugin
  # that was -- which made every install warn, and once left x-mode disabled, so
  # the dock and the bar widget were simply not there.
  local answer
  answer="$(omarchy-shell shell listPlugins 2>/dev/null)"
  if [ -n "$answer" ]; then
    printf '%s' "$answer" | python3 -c '
import json, sys
try:
    plugins = json.load(sys.stdin)
except Exception:
    sys.exit(2)
want = sys.argv[1]
sys.exit(0 if any(p.get("id") == want and p.get("enabled") for p in plugins) else 1)' "$1"
    case $? in
      0) return 0 ;;
      1) return 1 ;;
    esac
  fi
  # No shell to ask (an install from a TTY with the shell down): the file is all
  # there is.
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
  log_file "=== install start (pid $$, $0 $*)"
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
  log "building patched hyprbars"
  if ! "$HERE/hyprbars/build.sh"; then
    warn "hyprbars build failed; aborting before installing configs"
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

  # Hyprland runs the plugin's code in place from the .so, so the file may not be
  # written over (or deleted) while it is loaded: see hyprbars/build.sh. The
  # order below is the safe one, and it is what do_uninstall mirrors:
  #   1. take the pack out of the Lua config, so nothing in Lua can call into the
  #      plugin any more,
  #   2. reload: the Lua state is rebuilt without x-mode.lua,
  #   3. unload the old plugin,
  #   4. copy the new .so while nothing maps it,
  #   5. load it, and wire the pack back in at the end of the install.
  # Doing 3 before 1 leaves the old Lua state holding closures into a plugin that
  # is gone, and the next focus change calls into nothing. On a reinstall the
  # config is still the previous one, so the unwiring has to happen here too.
  if grep -q "^${X_MODE_BEGIN}$" "$HYPR/hyprland.lua" 2>/dev/null; then
    log "unwiring x-mode before the plugin is replaced"
    sentinel_remove "$HYPR/hyprland.lua"
    hyprctl reload >/dev/null 2>&1 || true
  fi

  log "installing patched hyprbars"
  mkdir -p "$HYPRBARS_DIR"
  if hyprbars_loaded && [ "$(windows_open)" -gt 0 ]; then
    # Loaded, and windows are on screen: stage the build instead of swapping it.
    # The pack's own exec_on_start moves it into place at the next startup, where
    # there are no windows and no decorations to leave listeners behind.
    install -m644 "$HERE/hyprbars/hyprbars.so" "$HYPRBARS_SO.new" \
      || warn "could not stage the plugin at $HYPRBARS_SO.new"
    warn "hyprbars is loaded: the new build is staged as $HYPRBARS_SO.new and loads at the next login"
  else
    hyprctl plugin unload "$HYPRBARS_SO" >/dev/null 2>&1 || true
    install -m644 "$HERE/hyprbars/hyprbars.so" "$HYPRBARS_SO" \
      || warn "could not copy the plugin to $HYPRBARS_SO"
    hyprctl plugin load "$HYPRBARS_SO" >/dev/null 2>&1 || warn "could not load hyprbars now (it will load on next login)"
  fi
  # No arrange marker here. This reload is the plugin's (on a fresh install the
  # pack's config is not wired in yet, on a reinstall it is still the previous
  # one), and a marker left for it is an arrange with the old geometry -- or a
  # second arrange, dealing the windows out in a new order a moment later. The one
  # marker is written below, for the reload that parses the config just
  # installed.
  log "reloading Hyprland to activate hyprbars"
  hyprctl reload >/dev/null 2>&1 || true

  log "installing shell plugins"
  # Migrate from the old two-plugin layout (tim.dock + tim.snap-preview).
  for old in tim.dock tim.snap-preview; do
    plugin_remove "$old"
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
    if ! plugin_enabled "$id"; then
      # The running shell rewrites shell.json too, so an enable can be lost the
      # moment it is written. Ask again, and say so plainly if it still did not
      # stick -- a plugin that installs but stays disabled has no dock and no bar
      # widget, which reads as "the pack is not installed".
      omarchy plugin enable "$id" >/dev/null 2>&1 || true
      sleep 0.5
      plugin_enabled "$id" || warn "$id is installed but stayed disabled: run 'omarchy plugin enable $id' once the shell is up"
    fi
  done

  log "installing Hyprland config"
  # Clean up the old drop-in / script layout from earlier installs.
  rm -f "$HYPR"/conf.d/5x-x-mode-*.lua 2>/dev/null || true
  # Earlier installs put the config file next to the directory instead of in it.
  rm -f "$HYPR/x-mode.lua" 2>/dev/null || true
  # The pure parsing modules live next to x-mode.lua; the whole directory is the
  # pack's, x-mode.lua dofiles its siblings relative to its own path, and
  # uninstall removes the directory as one entry. Geometry is not in there: that
  # is the plugin's (hyprbars/snap.cpp).
  copy_tree "$HERE/hypr/x-mode" "$HYPR/x-mode"
  # The panel's settings used to live in the state dir, which uninstall wipes.
  # Move an existing one to its own file next to the directory so it survives.
  if [ -f "$X_MODE_STATE_DIR/settings.json" ] && [ ! -f "$HYPR/x-mode.json" ]; then
    mv "$X_MODE_STATE_DIR/settings.json" "$HYPR/x-mode.json"
  fi

  log "adding the X Mode row to the menu"
  menu_write "$HYPR/x-mode/xmode"

  log "wiring x-mode into hyprland.lua"
  early_add "$HYPR/hyprland.lua"
  sentinel_add "$HYPR/hyprland.lua"

  # The one arrange marker. The config deals the already-open windows out (groups
  # across the halves, a lone group centred) and removes the marker only once it
  # has actually dealt them, so a parse that cannot run the deal (the plugin is not
  # loaded yet) keeps it instead of dropping the arrange on the floor.
  mkdir -p "$X_MODE_STATE_DIR"
  : > "$X_MODE_STATE_DIR/arrange"

  log "reloading Hyprland"
  hyprctl reload >/dev/null 2>&1 || true

  # The re-float and the arrange are both left to the config: install.sh drops
  # the `arrange` marker before its reload, and x-mode.lua's own timer fades the
  # windows out, re-floats them, arranges them and brings them back — all on
  # invisible windows. Doing either here would move them on screen first and a
  # second time a moment later.

  # `rescanPlugins` + `plugin enable` only update the registry: a plugin that is
  # already loaded keeps the QML instance it was created with, so updated files
  # (and a stale icon index) would not take effect until a manual restart.
  log "restarting the shell to load the updated plugins"
  OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}" omarchy-restart-shell >/dev/null 2>&1 || warn "could not restart the shell; run 'omarchy-restart-shell' to load the plugins"
  ensure_shell

  log "installed omarchy-x-mode"
  log_file "=== install done"
}

do_uninstall() {
  log_file "=== uninstall start (pid $$, $0 $*)"
  # The order here is the whole point. Hyprland runs the plugin's code in place
  # from $HYPRBARS_SO, and the pack's Lua calls into it on every focus change
  # (window.active -> hyprbars.raise). So: unwire the config, reload (the Lua
  # state is rebuilt without the pack, and nothing in Lua points into the plugin
  # any more), unload the plugin, and only then take the shell plugins away --
  # their layer surfaces going unmapped is what walks the input path into that
  # Lua. Unloading or deleting the .so first, with the pack still wired, is how a
  # plain uninstall segfaulted the compositor and took the whole session down.
  log "unwiring x-mode from hyprland.lua"
  sentinel_remove "$HYPR/hyprland.lua"
  hyprctl reload >/dev/null 2>&1 || true

  log "retiring patched hyprbars"
  # Not unloaded here, and the file only removed once it is not loaded. Unloading
  # the plugin with windows on screen has crashed the compositor (its decorations
  # hold listeners, and a layer going away walks the input path straight into
  # them); removing a loaded .so does the same. So: with windows open the plugin
  # stays loaded -- no titlebars change until the next login -- and the file stays
  # with it.
  KEEP_SO=""
  if hyprbars_loaded; then
    if [ "$(windows_open)" -eq 0 ]; then
      hyprctl plugin unload "$HYPRBARS_SO" >/dev/null 2>&1 || true
    fi
    if hyprbars_loaded; then
      KEEP_SO="$HYPRBARS_SO"
      warn "the plugin stays loaded until the next login; keeping $HYPRBARS_SO"
    fi
  fi

  # Re-enable a stock hyprbars that was loaded before we replaced it.
  if [ -f "$PRIOR_HYPRBARS" ]; then
    prior="$(head -n1 "$PRIOR_HYPRBARS" 2>/dev/null || true)"
    if [ -n "$prior" ] && [ -f "$prior" ]; then
      log "re-enabling previous hyprbars"
      hyprctl plugin load "$prior" >/dev/null 2>&1 || warn "could not re-enable $prior"
    fi
  fi

  log "disabling/removing shell plugins"
  for id in x-mode tim.dock tim.snap-preview; do
    plugin_remove "$id"
  done
  omarchy-shell -q shell rescanPlugins 2>/dev/null || true

  log "taking the X Mode row out of the menu"
  menu_remove

  log "removing installed files"
  rm -f "$HYPR"/conf.d/5x-x-mode-*.lua 2>/dev/null || true
  # The pack's directory, and the config file earlier installs left beside it.
  rm -rf "$HYPR/x-mode" 2>/dev/null || true
  rm -f "$HYPR/x-mode.lua" 2>/dev/null || true
  # ~/.config/hypr/x-mode.json (the panel's settings) is the user's, not ours: it
  # is not in the manifest and stays, so a reinstall brings the settings back.
  if [ -f "$X_MODE_MANIFEST" ]; then
    tac "$X_MODE_MANIFEST" | while IFS= read -r p; do
      [ -n "$p" ] || continue
      # A plugin that is still loaded keeps its file: see the unload above. Written
      # as an `if`, not as `[ … ] && [ … ] && continue`: under `set -e` a failing
      # `&&` chain ends the script, and with KEEP_SO empty that aborted every
      # uninstall right here -- before the shell was restarted, which is why the
      # desktop came back with no bar and no dock at all.
      if [ -n "$KEEP_SO" ] && [ "$p" = "$KEEP_SO" ]; then
        log "keeping $p (still loaded)"
        continue
      fi
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
    # The window's own tag decides, and the snapshot only breaks the tie: a window
    # carrying the pack's tag is one the *pack* floated, whatever the snapshot says.
    # The snapshot is taken at install time and cannot be trusted for that -- an
    # install that ran while the pack was already on (a reinstall) recorded every
    # window as floating, and the next uninstall then "restored" them to floating,
    # which is how windows stayed floating after an uninstall.
    tags = [str(t) for t in (c.get("tags") or [])]
    pack_floated = any(t == "xmode-workspace" or t == "xmode-workspace*" for t in tags)
    want_float = (bool(p.get("floating")) if p is not None else False) and not pack_floated
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
  ensure_shell
  # Kept on purpose: the user's settings, not ours.
  if [ -f "$HYPR/x-mode.json" ]; then
    log "kept settings  $HYPR/x-mode.json"
  fi
  rm -rf "$X_MODE_STATE_DIR"
  log "uninstalled omarchy-x-mode"
  log_file "=== uninstall done"
}

do_status() {
  echo "state dir: $X_MODE_STATE_DIR"
  echo "manifest:  $X_MODE_MANIFEST"
  if [ -f "$HYPR/x-mode.json" ]; then
    echo "settings:  $HYPR/x-mode.json (kept on uninstall)"
  else
    echo "settings:  $HYPR/x-mode.json (none yet)"
  fi
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
