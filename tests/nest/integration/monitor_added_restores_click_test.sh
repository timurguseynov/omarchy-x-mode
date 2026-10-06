#!/usr/bin/env bash
# After a monitor is unplugged the pack pages a window back onto its half and
# configures the client, but it must not raise: a click on the restored
# titlebar is what brings it to the front. Kitty stays on screen and focused
# so a restore that raised foot would show up here.
. "$(dirname "$0")/../../lib.sh"

open_window foot
open_window kitty
settle

# Park them apart so a click has one answer. Foot on the left half, kitty on
# the right and focused. Fractions, not a 100x80 box: that strip is smaller
# than the titlebar buttons and a content click misses.
place_frac foot 4 25 35 40
place_frac kitty 55 30 35 40
nest_ctl dispatch "hl.dsp.focus({ window = 'class:kitty' })" >/dev/null
sleep 0.3
assert_eq "$(topmost)" kitty "kitty is on top before the unplug"

read -r px py pw ph <<<"$(nest_ctl monitors -j | python3 -c '
import json, sys
m = next(x for x in json.load(sys.stdin) if x.get("focused"))
s = m["scale"] or 1
print(m["x"], m["y"], m["width"] // s, m["height"] // s)
')"

foot_at() {
  nest_ctl clients -j | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    if c["class"] == "foot":
        print(c["at"][0], c["at"][1], c["size"][0], c["size"][1]); break
'
}

read -r fx fy fw fh <<<"$(foot_at)"
left=$fx
[ "$pw" -gt $((fw + 160)) ] || fail "monitor ${pw}px is too narrow for a ${fw}px window"

off=$((left - pw))
nest_ctl dispatch "hl.dsp.window.move({ x = $off, y = $fy, relative = false, window = 'class:foot' })" >/dev/null
wait_still foot
sleep 0.2
read -r ax ay aw ah <<<"$(foot_at)"
echo "foot placed at $ax,$ay size ${aw}x${ah} (asked $off)"
assert_between "$ax" $((off - 1)) $((off + 1)) "the off-screen place did not stick"

# Call the same restore the monitor.added/removed handler runs. Creating a
# second output to fire those events leaves the virtual pointer on the
# destroyed headless, and the click then misses.
nest_ctl eval 'if hl.plugin and hl.plugin.hyprbars and hl.plugin.hyprbars.fit_all then hl.plugin.hyprbars.fit_all() end' >/dev/null
settle
sleep 0.2

read -r ax ay aw ah <<<"$(foot_at)"
echo "foot after fit: at $ax,$ay size ${aw}x${ah} (want $left)"
assert_between "$ax" $((left - 1)) $((left + 1)) "fit must page the window back to its own slot"
assert_eq "$aw" "$fw" "fit must not resize the window"
assert_eq "$ah" "$fh" "fit must not resize the window"
assert_eq "$(active_class)" kitty "fit must not steal focus"
assert_eq "$(topmost)" kitty "fit must not raise the restored window"

read -r tx ty <<<"$(titlebar_point foot)"
echo "clicking restored foot titlebar at $tx,$ty (box $ax,$ay ${aw}x${ah})"
pointer_click "$tx" "$ty"
sleep 0.3
assert_eq "$(active_class)" foot "clicking the restored titlebar focuses that window"
assert_eq "$(topmost)" foot "clicking the restored titlebar raises that window"
