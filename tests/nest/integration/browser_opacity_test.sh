#!/usr/bin/env bash
# A browser keeps the desktop's opacity, so its titlebar is as solid as any other
# app's.
#
# Omarchy tags chromium-based apps and the tag rule then forces them to tile and
# to take "1.0 0.985" opacity instead of the desktop's. A tag is added while the
# window opens, so that rule is applied after the pack's catch-all and wins where
# the two disagree: the pack overrides the tiling half already, and without the
# opacity half a browser is the one window whose titlebar goes translucent the
# moment it loses focus. The nest plants Omarchy's rules; the pack's own are what
# has to answer them.
. "$(dirname "$0")/../../lib.sh"

# The property as a comparable number: getprop prints "1" or "0.985".
opacity_of() { # CLASS PROP
  nest_ctl getprop "class:$1" "$2" 2>/dev/null | python3 -c '
import sys
try:
    print("%.3f" % float(sys.stdin.read().strip()))
except ValueError:
    print("none")'
}

open_command footbrowser foot -a footbrowser
nest_ctl dispatch "hl.dsp.focus({ window = 'class:footbrowser' })" >/dev/null
sleep 0.3

assert_eq "$(opacity_of footbrowser opacity)" "1.000" "the focused browser is opaque"
assert_eq "$(opacity_of footbrowser opacity_inactive)" "1.000" "and so is the unfocused one, so its titlebar stays solid"

# The window is still floating and drawn with a titlebar: the browser rule the
# pack carries for the tiling half must not have swallowed it.
nest_ctl clients -j | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    if c.get("class") == "footbrowser" and c.get("mapped"):
        if not c.get("floating"):
            raise SystemExit("the browser window is not floating")
        break
else:
    raise SystemExit("the browser window is gone")'
