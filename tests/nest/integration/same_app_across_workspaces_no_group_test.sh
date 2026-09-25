#!/usr/bin/env bash
# Same-app windows group with a peer of the same class AND the same workspace, so
# a window opened on another space stays on its own. Grouping across workspaces
# would drag a window onto a space it was not on.
. "$(dirname "$0")/../../lib.sh"

# Say where each window opens rather than trusting the workspace a previous
# scenario left behind.
nest_ctl dispatch "hl.dsp.focus({ workspace = \"1\" })" >/dev/null
sleep 0.3
open_window foot
nest_ctl dispatch "hl.dsp.focus({ workspace = \"2\" })" >/dev/null
sleep 0.4
open_window foot 2

assert_eq "$(count_class foot)" 2 "both windows exist"
assert_le "$(group_size foot)" 1 "a same-app window on another space is not a tab"

ws="$(nest_ctl clients -j | python3 -c "
import json, sys
print(' '.join(sorted(str(c['workspace']['id']) for c in json.load(sys.stdin) if c['class'] == 'foot')))")"
assert_eq "$ws" "1 2" "each window stays on the space it was opened on"

nest_ctl dispatch "hl.dsp.focus({ workspace = \"1\" })" >/dev/null
