#!/usr/bin/env bash
# An install deals the open windows out (the arrange marker) on whatever layout
# the workspace is in. The deal floats them. The titlebar is drawn for the
# pack's tag, and that tag is only applied on an xmode workspace, so a dwindle
# workspace came back floating and with no bar. The marker claims the workspace
# as xmode first: the window floats, carries the tag, and the mode sticks.
. "$(dirname "$0")/../../lib.sh"

APP=arrangetag

floating() {
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$APP' and c['mapped'] and not c['hidden']:
        print('yes' if c['floating'] else 'no')
        break"
}

tagged() {
  nest_ctl clients -j | python3 -c "
import json, sys
for c in json.load(sys.stdin):
    if c['class'] == '$APP' and c['mapped'] and not c['hidden']:
        tags = [str(t) for t in (c.get('tags') or [])]
        print('yes' if any(t == 'xmode-workspace' or t == 'xmode-workspace*' for t in tags) else 'no')
        break"
}

pack_mode() {
  local out="/tmp/xmode-arrange-claim-$$"
  rm -f "$out"
  nest_ctl eval "if x_mode and x_mode.mode then hl.exec_cmd(\"sh -c 'echo \" .. tostring(x_mode.mode(1)) .. \" > $out'\") end" >/dev/null
  for _ in $(seq 1 20); do
    [ -f "$out" ] && break
    sleep 0.05
  done
  cat "$out" 2>/dev/null
  rm -f "$out"
}

nest_ctl eval 'o.workspace_mode({ workspace = "1", mode = "dwindle" })' >/dev/null
settle

open_command "$APP" alacritty --class "$APP"
settle
assert_eq "$(count_class "$APP")" 1 "the probe window is open"
assert_eq "$(floating "$APP")" no "a dwindle workspace tiles the window"
assert_eq "$(pack_mode)" dwindle "the workspace is dwindle before the install deal"

touch "$NEST_STATE/state/arrange"
nest_ctl eval 'if x_mode and x_mode.claim_arranged then x_mode.claim_arranged() end' >/dev/null
rm -f "$NEST_STATE/state/arrange"
settle

assert_eq "$(pack_mode)" xmode "the install deal claims the workspace as xmode"
assert_eq "$(floating "$APP")" yes "the claimed window floats"
assert_eq "$(tagged "$APP")" yes "the claimed window carries the titlebar tag"
grep -q 'mode = "xmode"' "$NEST_STATE/home/.local/state/omarchy/workspace-layouts/1.lua" \
  || fail "the claimed mode was not saved for the next login"
