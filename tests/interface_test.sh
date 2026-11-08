#!/usr/bin/env bash
# The runtime files the shell, the plugin and the config share. Each name is a
# literal on both sides -- there is no shared constant across Lua, C++ and QML --
# so a rename on one side is silent: the writer keeps writing, the reader keeps
# reading a file nobody touches, and the feature just stops happening.
#
# This pins which side owns which name. A new interface file has to be added here,
# which is the moment to ask whether both sides know about it.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
fail=0

# name|file that must mention it|...
expect=(
  "omarchy-x-mode.state|quickshell/x-mode/Dock.qml"
  "omarchy-x-mode.state|quickshell/x-mode/Toggle.qml"
  "omarchy-x-mode.state|quickshell/x-mode/logic.js"
  "omarchy-x-mode.state|hyprbars/main.cpp"
  "omarchy-x-mode.workspace|hypr/x-mode/x-mode.lua"
  "omarchy-x-mode.workspace|quickshell/x-mode/Dock.qml"
  "omarchy-switcher.cmd|hypr/x-mode/x-mode.lua"
  "omarchy-switcher.cmd|quickshell/x-mode/Switcher.qml"
  "omarchy-snap-preview.cmd|hyprbars/dragSession.cpp"
  "omarchy-snap-preview.cmd|quickshell/x-mode/SnapPreview.qml"
  "omarchy-x-mode.tab-textures|hyprbars/barDeco.cpp"
  # The tabbar's + button writes this one; the dock reads it and launches.
  "omarchy-x-mode-launch.cmd|hyprbars/barDeco.cpp"
  "omarchy-x-mode-launch.cmd|quickshell/x-mode/Dock.qml"
)

for row in "${expect[@]}"; do
  name="${row%%|*}"
  file="${row#*|}"
  if ! grep -qF "$name" "$REPO/$file"; then
    echo "FAIL interface: $file no longer mentions $name"
    fail=1
  fi
done

# The other direction: every runtime name that appears in the pack's code has to be
# one of the names above, so a new file introduced on one side only shows up here.
known="$(printf '%s\n' "${expect[@]}" | cut -d'|' -f1 | sort -u)"
found="$(grep -rhoE 'omarchy-[a-z0-9.-]+\.(state|cmd|workspace|tab-textures)' \
  "$REPO/hypr/x-mode" "$REPO/hyprbars" "$REPO/quickshell" 2>/dev/null | sort -u)"
for name in $found; do
  if ! printf '%s\n' "$known" | grep -qxF "$name"; then
    echo "FAIL interface: $name is used in the code but is not a known interface file"
    fail=1
  fi
done

[ "$fail" = 0 ] && echo "ok   interface names"
exit "$fail"
