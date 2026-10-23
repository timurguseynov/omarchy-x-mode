#!/usr/bin/env bash
# Build the hyprbars plugin into this directory. Building only: the installed
# copy (~/.local/share/hyprbars/x-mode-hyprbars.so) is written by install.sh,
# and only after it has unloaded the plugin it replaces.
#
# That split is not tidiness. Hyprland maps the .so into its own address space
# and runs the plugin's code in place, so writing over the file (or deleting it)
# while the plugin is loaded pulls the pages out from under the running
# compositor: the next call into the plugin lands in memory that is no longer
# there, and the whole session dies -- a session-wide crash from a file copy.
# install.sh therefore unloads first and copies while nothing maps the file.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

# Hyprland headers are provided by hyprpm's cache.
HEADERS="$(ls -d /var/cache/hyprpm/*/headersRoot 2>/dev/null | head -n1 || true)"
if [[ -z ${HEADERS} ]]; then
  echo "hyprpm headers not found. Run 'hyprpm update' first." >&2
  exit 1
fi

echo "==> building hyprbars"
make -C "$HERE" clean
PKG_CONFIG_PATH="${HEADERS}/share/pkgconfig" make -C "$HERE" all
echo "==> built ${HERE}/hyprbars.so"
