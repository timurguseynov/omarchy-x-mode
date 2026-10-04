#!/usr/bin/env bash
# The arrange that install.sh triggers deals a room's windows across the
# workspace, and it must do that per workspace: a window is never moved to another
# space. A window left on the second workspace has to be arranged there, not pulled
# back to the first -- and alone on its space it is centred (the plugin's
# almost-maximize), not put on a half.
. "$(dirname "$0")/../../lib.sh"

extent="$(pointer_extent)"
mw="${extent%x*}"
half=$((mw / 2))

open_window foot
nest_ctl dispatch "hl.dsp.window.move({ workspace = \"2\", window = 'class:foot' })" >/dev/null
sleep 0.3
nest_ctl dispatch "hl.dsp.focus({ workspace = \"1\" })" >/dev/null
sleep 0.3

touch "$NEST_STATE/state/arrange"
nest_ctl reload >/dev/null
sleep 1.0

ws="$(nest_ctl clients -j | python3 -c "
import json, sys
print(' '.join(str(c['workspace']['id']) for c in json.load(sys.stdin) if c['class'] == 'foot'))")"
assert_eq "$ws" 2 "the arrange must not move a window to another workspace"

read -r _ _ w _ _ <<<"$(nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == 'foot':
        print(c['at'][0], c['at'][1], c['size'][0], c['size'][1], 0)
        break")"
assert_ge "$w" $((half + 40)) "the lone group is centred where it already was, not on a half"
