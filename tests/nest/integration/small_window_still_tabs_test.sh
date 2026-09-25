#!/usr/bin/env bash
# Grouping does not look at size: a small window of a class that is already open is
# another document, not a popup, so it becomes a tab. The plugin classifies popups
# the way Hyprland does (override-redirect, modal, transients), and the old size
# floor is only a fallback for when the plugin is not loaded.
#
# Small foot windows are the cheap way to have a real, tiny window of a class known
# to group.
. "$(dirname "$0")/../../lib.sh"

open_command foot foot --window-size-pixels=120x90
open_command foot foot --window-size-pixels=120x90

assert_eq "$(count_class foot)" 2 "both small windows are open"
read -r _ _ w _ _ <<<"$(win_geom foot)"
assert_le "$w" 150 "the window really is small"
assert_eq "$(group_size foot)" 2 "a small window is still a tab, not a popup"
