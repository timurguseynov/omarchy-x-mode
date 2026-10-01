#!/usr/bin/env bash
# Super+click is Ctrl+click for an app with the per-app flag. Super+LMB drag
# is already gone; this bind is the replacement. It is always installed, and
# pass_event keeps Super+click as Super+click when the flag is off.
. "$(dirname "$0")/../../lib.sh"

has_ctrl_click_bind() {
  nest_ctl binds -j | python3 -c '
import json, sys
n = 0
for b in json.load(sys.stdin):
    key = (b.get("key") or "")
    if int(b.get("modmask") or 0) != 64:
        continue
    if key in ("mouse:272", "mouse:273", "mouse:274"):
        n += 1
print(n)'
}

assert_eq "$(has_ctrl_click_bind)" 3 "Super+click (left/right/middle) is bound as Ctrl+click"
