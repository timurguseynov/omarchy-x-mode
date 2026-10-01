#!/usr/bin/env bash
# A group shares one layout target. Hyprland translates that target once per
# member, so a two-tab group lands twice as far off as a single window. Fit
# has to run once for the group (the current tab covers the others) and
# still put every member on the same restored slot, mapped, without raising.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window foot 2
open_window kitty
settle
assert_eq "$(group_size foot)" 2 "two foot windows share the group"

nest_ctl dispatch "hl.dsp.window.resize({ x = 100, y = 80, relative = false, window = 'class:foot' })" >/dev/null
settle

read -r px py pw ph <<<"$(nest_ctl monitors -j | python3 -c '
import json, sys
m = next(x for x in json.load(sys.stdin) if x.get("focused"))
s = m["scale"] or 1
print(m["x"], m["y"], m["width"] // s, m["height"] // s)
')"

read -r ww <<<"$(nest_ctl clients -j | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    if c["class"] == "foot":
        print(c["size"][0]); break
')"

left=$((px + 80))
[ "$pw" -gt $((ww + 160)) ] || fail "monitor ${pw}px is too narrow for a ${ww}px window"

place_frac kitty 55 30 30 40
nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
assert_eq "$(topmost)" kitty "kitty is on top before the unplug"

off=$((left - pw))
nest_ctl dispatch "hl.dsp.window.move({ x = $off, y = $((py + 80)), relative = false, window = 'class:foot' })" >/dev/null
wait_still foot

foot_xs() {
  nest_ctl clients -j | python3 -c '
import json, sys
xs = []
for c in json.load(sys.stdin):
    if c["class"] == "foot" and c["mapped"]:
        xs.append((c["at"][0], c["size"][0]))
for x, w in xs:
    print(x, w)
'
}

n=0
while read -r ax aw; do
  n=$((n + 1))
  assert_between "$ax" $((off - 1)) $((off + 1)) "tab $n: the off-screen place did not stick"
done <<<"$(foot_xs)"
assert_eq "$n" 2 "both tabs were off-screen together"

nest_ctl output create headless HEADLESS-1 >/dev/null 2>&1
for i in $(seq 1 40); do
  nest_ctl monitors -j | grep -q '"name": "HEADLESS-1"' && break
  sleep 0.1
done
settle
sleep 0.3

n=0
x0=""
while read -r ax aw; do
  n=$((n + 1))
  echo "foot tab $n after added: at $ax size $aw (want $left)"
  assert_between "$ax" $((left - 1)) $((left + 1)) "tab $n must come back to the same slot as the group, not a second page"
  assert_eq "$aw" "$ww" "tab $n: fit must not resize"
  if [ -z "$x0" ]; then
    x0="$ax"
  else
    assert_eq "$ax" "$x0" "both tabs share one restored box"
  fi
done <<<"$(foot_xs)"
assert_eq "$n" 2 "both tabs stay mapped"
assert_eq "$(group_size foot)" 2 "the group stays a group"
assert_eq "$(active_class)" kitty "fit must not steal focus"
assert_eq "$(topmost)" kitty "fit must not raise the group"

nest_ctl output destroy HEADLESS-1 >/dev/null 2>&1 || true
