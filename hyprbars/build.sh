#!/usr/bin/env bash
# Build the hyprbars plugin and install it to
# ~/.local/share/hyprbars/x-mode-hyprbars.so (own file name, so a stock
# hyprbars.so next to it is never overwritten).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="${HOME}/.local/share/hyprbars"

# Hyprland headers are provided by hyprpm's cache.
HEADERS="$(ls -d /var/cache/hyprpm/*/headersRoot 2>/dev/null | head -n1 || true)"
if [[ -z ${HEADERS} ]]; then
  echo "hyprpm headers not found. Run 'hyprpm update' first." >&2
  exit 1
fi

echo "==> building hyprbars"
make -C "$HERE" clean
PKG_CONFIG_PATH="${HEADERS}/share/pkgconfig" make -C "$HERE" all

mkdir -p "$DEST"
install -m644 "$HERE/hyprbars.so" "$DEST/x-mode-hyprbars.so"
echo "==> installed ${DEST}/x-mode-hyprbars.so"
