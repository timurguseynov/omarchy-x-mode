#!/usr/bin/env bash
# The titlebar is drawn by the plugin into the window's own render pass, so there
# is nothing to ask Hyprland about: this is a pixels test. The band of screen
# above a window's box has to change when the window opens, and a band elsewhere
# has to stay the same, so the difference is the titlebar and not noise.
#
# grim captures the nest's output in physical pixels while the geometry is
# logical, so the band is scaled by the monitor's scale.
. "$(dirname "$0")/../../lib.sh"

shots="$NEST_STATE/shots"
mkdir -p "$shots"
scale="$(nest_ctl monitors -j | python3 -c "import json,sys;print(int(json.load(sys.stdin)[0]['scale']))")"

# A shot nobody looks at, so the first comparison is not against a frame that was
# still being drawn.
nest_screenshot "$shots/warmup.png"
nest_screenshot "$shots/empty.png"
open_window foot
sleep 0.5
read -r x y w h _ <<<"$(win_geom foot)"
nest_screenshot "$shots/open.png"

# The 28px of chrome above the window box, and a control band next to it.
band_h=$((28 * scale))
magick "$shots/empty.png" -crop "$((w * scale))x${band_h}+$((x * scale))+$(((y - 28) * scale))" +repage "$shots/empty_band.png"
magick "$shots/open.png"  -crop "$((w * scale))x${band_h}+$((x * scale))+$(((y - 28) * scale))" +repage "$shots/open_band.png"
# The control band is the top-right corner: the bar is a layer and is in both
# shots, and the window does not reach there. A band beside the titlebar would
# not do — the titlebar starts at the window's x, so a strip at x=2 overlaps it.
shot_w="$(magick identify -format '%w' "$shots/empty.png")"
magick "$shots/empty.png" -crop "60x60+$((shot_w - 60))+0" +repage "$shots/empty_far.png"
magick "$shots/open.png"  -crop "60x60+$((shot_w - 60))+0" +repage "$shots/open_far.png"

band_diff="$(image_diff "$shots/empty_band.png" "$shots/open_band.png")"
far_diff="$(image_diff "$shots/empty_far.png" "$shots/open_far.png")"

assert_ge "$band_diff" 500 "the titlebar band changes when the window opens (got $band_diff)"
assert_le "$far_diff" 60 "a band away from the window does not (got $far_diff)"
