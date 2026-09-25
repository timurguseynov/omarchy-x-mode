#!/usr/bin/env bash
# The dock follows x-mode's on/off flag, which lives in a file in the runtime
# directory. The flag is written by the bar toggle and read here, so turning
# x-mode off has to hide the dock without restarting the shell.
. "$(dirname "$0")/../../lib.sh"

dock_start
dock_settle
assert_ne "$(dock_box 2>/dev/null || echo none)" none "the dock is there while x-mode is on"

echo off > "$DOCK_RUNTIME/omarchy-x-mode.state"
sleep 1.0
assert_eq "$(dock_box 2>/dev/null || echo none)" none "turning x-mode off hides the dock"

echo on > "$DOCK_RUNTIME/omarchy-x-mode.state"
sleep 1.0
assert_ne "$(dock_box 2>/dev/null || echo none)" none "turning x-mode back on shows it again"

dock_stop
