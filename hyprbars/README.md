# hyprbars (X Mode)

Adds macOS-style title bars to windows, with tabs for grouped apps.

This is the [upstream hyprbars](https://github.com/hyprwm/hyprland-plugins)
plugin (pin `7644cec`), patched for [X Mode](../README.md): a single close
button, a tab strip for same-app groups (per-tab close + `+` to open another
window), titlebar drag-to-edge snapping, and a clean unload path.

Built automatically by the pack installer (`install.sh`). Skip with
`--no-hyprbars`. Manual build:

```sh
./build.sh
# → ~/.local/share/hyprbars/x-mode-hyprbars.so
```

## Config

All options live under `plugin:hyprbars`. X Mode sets sensible defaults from
`hypr/x-mode.lua` (theme colors, height, close button) — you usually don’t need
to touch these.

```lua
hl.config({
    plugin = {
        hyprbars = {
            bar_height = 28,
            tab_height = 24,
            bar_color = "rgb(1e1e2e)",
            ["col.text"] = "rgb(cdd6f4)",
            on_double_click = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
        },
    },
})

hl.plugin.hyprbars.add_button({
    bg_color = "rgb(ff4040)",
    fg_color = "rgb(ffffff)",
    size = 10,
    icon = "󰖭",
    action = "hyprctl dispatch 'hl.dsp.window.close()'",
})
```

| property | type | description | default |
| --- | --- | --- | --- |
| `enabled` | bool | whether to enable the bars | `true` |
| `bar_color` | color | bar background color | |
| `bar_height` | int | titlebar height | `15` |
| `tab_height` | int | group tabbar height | `24` |
| `bar_blur` | bool | blur the bar (also needs global blur) | |
| `col.text` | color | title / tab text color | |
| `bar_title_enabled` | bool | render the title | `true` |
| `bar_text_size` | int | title font size | `10` |
| `bar_text_weight` | font weight | title weight (`thin`…`heavy`, or 100–1000) | `400` |
| `bar_text_font` | str | title font | `Sans` |
| `bar_text_align` | left / center | title alignment | `center` |
| `bar_buttons_alignment` | right / left | button side | `right` |
| `bar_part_of_window` | bool | bar is part of the window (shadows wrap it) | |
| `bar_precedence_over_border` | bool | bar above the border | |
| `bar_padding` | int | left / right padding | `7` |
| `bar_button_padding` | int | padding between buttons | `5` |
| `icon_on_hover` | bool | show button icons only on hover | `false` |
| `inactive_button_color` | color | button bg when the window isn’t focused | |
| `on_double_click` | str | command on double-click of the bar | |

### Snap / grouping (X Mode)

| property | type | description | default |
| --- | --- | --- | --- |
| `x_mode_dock_inset` | int | right snap inset, dock card plus half of `gaps_out`; set by `x-mode.lua` | `45` |
| `x_mode_snap_margin` | int | edge strip that starts a snap (px) | `12` |
| `x_mode_snap_corner` | int | corner square that picks a quarter (px) | `20` |
| `x_mode_snap_short_edge` | int | side-edge px from top/bottom for half snaps | `145` |
| `x_mode_snap_top_slop` | int | extra px below the top bar that still maximize | `8` |
| `x_mode_snap_top_half` | bool | top short strip → top half | `false` |
| `x_mode_snap_bottom_half` | bool | bottom short strip → bottom half | `false` |
| `x_mode_almost_maximize_percent` | int | almost-maximize size (%) | `90` |
| `x_mode_group_min_width` | int | don’t auto-group narrower windows | `400` |
| `x_mode_group_min_height` | int | don’t auto-group shorter windows | `300` |

## Buttons

```lua
hl.plugin.hyprbars.add_button({
    bg_color = "rgb(ff4040)",
    fg_color = "rgb(ffffff)",
    size = 10,
    icon = "X",
    action = "hyprctl dispatch 'hl.dsp.window.close()'",
})
```

Legacy keyword (ini configs): `hyprbars-button = bgcolor, size, icon, on-click, fgcolor`.

## Window rules

Dynamic rules:

- `hyprbars:no_bar` — hide the titlebar (and tabs) on matching windows
- `hyprbars:always_tabbar` — keep the tab strip even for a single window
- `hyprbars:bar_color` — override bar background
- `hyprbars:title_color` — override title color

```lua
o.window({ class = "chromium" }, { ["hyprbars:no_bar"] = true })
```

X Mode’s settings panel writes these for you via per-app chrome toggles.

## License

Based on [hyprland-plugins](https://github.com/hyprwm/hyprland-plugins)
(BSD 3-Clause). Pack changes are MIT — see the repo root `LICENSE`.
