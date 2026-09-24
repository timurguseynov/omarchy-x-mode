# x-mode tests

Two layers:

- **`nest/`** — scenarios in a nested Hyprland. It is a window inside the real
  session running the repo's `x-mode.lua` and the freshly built plugin, with its
  own `$X_MODE_STATE`, so nothing here touches the live session or
  `~/.local/state`. This is where snap/group/no-gaps/topbar/focus are checked.
- **`unit/`** — pure Lua, no compositor. Not written yet; it needs the geometry
  and settings parsing split out of `x-mode.lua` (see below).

## Run

```sh
tests/run.sh            # unit, then nest
tests/nest/run.sh       # nest only
```

The nest layer builds `hyprbars` first (incrementally) and needs a running
Hyprland session (for the nest) plus the hyprpm headers. It starts one nest for
the whole run and cleans the windows between files.

Requirements: `hyprpm` headers (`hyprpm update`), `quickshell`/`qs` (the fake top
bar), and a terminal to open test windows (`foot`, `kitty`).

## nest scenarios

| file | checks |
|---|---|
| `snap_test.sh` | halves keep the bar/gap/border inset and do not overlap |
| `group_test.sh` | a same-app window joins; the tabbar grows the chrome without pushing the visual top |
| `topbar_test.sh` | with the bar gone (shell restart) a snap still clears where it was |
| `nogaps_test.sh` | the panel's file + reload zeroes the gaps and re-lays the snapped windows |
| `focus_test.sh` | the focused window ends up topmost, including after a same-app window joins |

`focus_test.sh` relies on `hyprctl clients -j` being in z-order (topmost last),
which is what `lib.sh`'s helpers read.

## Writing a test

Source `../lib.sh` and use its helpers:

```sh
. "$(dirname "$0")/../lib.sh"

open_window foot
snap foot left
assert_ge "$(visual_top foot)" 36 "the titlebar clears the bar"
```

Helpers: `open_window`, `nest_clean`, `win_geom`, `visual_top`, `group_size`,
`snap`, `bar_top`, `gaps_out`, `nest_ctl`, `nest_socket`, and `assert_eq/ne/ge/le`.

## unit layer (TODO)

`x-mode.lua` is deliberately a single file, so its locals (`usable`, `snap_geom`,
`apply_gaps`, `chrome_h`, `read_settings`, `load_apps`) cannot be reached from a
test. To unit-test them without a compositor, either extract them into
`hypr/x-mode/geom.lua` and `hypr/x-mode/settings.lua` (takes inputs as
arguments, no `hl`), or load the whole file under a `fake_hl.lua` that stubs and
records the Hyprland API.
