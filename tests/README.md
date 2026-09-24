# x-mode tests

Four layers:

- **`lint/`** (via `lint.sh`) — `qmllint` over `quickshell/x-mode/*.qml`. The
  Quickshell/qs.* modules are not on the lint import path, so their "not found"
  warnings are expected; only real errors fail.
- **`unit/`** — pure Lua, no compositor: the modules in `hypr/x-mode/`
  (geometry, settings, theme, MRU).
- **`qml/`** — pure JS, no compositor: the shell plugin's shared logic in
  `quickshell/x-mode/logic.js`, run with `qmltestrunner` offscreen.
- **`nest/`** — scenarios in a nested Hyprland: a window inside the real session
  running the repo's `x-mode.lua` and the freshly built plugin, with its own
  `$X_MODE_STATE`, so nothing here touches the live session or
  `~/.local/state`.

## Run

```sh
bash tests/run.sh       # lint, unit, qml, then nest
tests/nest/run.sh       # nest only
bash tests/unit/run.sh  # pure lua only
bash tests/qml/run.sh   # pure JS only
```

The nest layer builds `hyprbars` first (incrementally) and needs a running
Hyprland session (for the nest) plus the hyprpm headers. It starts one nest for
the whole run and cleans the windows between files.

Requirements: `hyprpm` headers (`hyprpm update`), `quickshell`/`qs` (the fake top
bar), a terminal to open test windows (`foot`, `kitty`), and Qt's `qmllint` /
`qmltestrunner` (in `/usr/lib/qt6/bin`).

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

## unit layer

Pure logic that does not need a compositor. It lives in sibling modules next to
`x-mode.lua`, so the tests load them directly with plain `lua`:

| file | module | covers |
|---|---|---|
| `geometry_test.lua` | `hypr/x-mode/geom.lua` | frame (including scale), zone insets with and without gaps, halves not overlapping, maximize, almost-maximize, cycle sizes, `fit_box` clamping, `cycle_index` |
| `settings_test.lua` | `hypr/x-mode/settings.lua` | options/apps parsing, the apps section vs the whole file, the legacy array, the merge of the two old files, the rule diff |
| `theme_test.lua` | `hypr/x-mode/theme.lua` | the TOML subset (inline comments, quotes), hex/rgb conversion, the bar color defaults |
| `mru_test.lua` | `hypr/x-mode/mru.lua` | touch ordering, step wrapping, sort by MRU then focus |

Adding to a module is the way to make something unit-testable: `x-mode.lua`
still holds the event/state layer (binds, `hl.dispatch`, grouping, switcher),
which the nest layer exercises instead.

## qml layer

Same idea for the shell plugin: the pure JS it shares lives in
`quickshell/x-mode/logic.js` (`.pragma library`), so it can be tested with
`qmltestrunner` offscreen, without a Quickshell runtime.

| file | covers |
|---|---|
| `tst_logic.qml` | `parseEnabled` (on/off/1/0/true/false/empty/junk), `shellQuote`, `parseApps` (object, legacy array, invalid), `cleanName`, `lastSegment`, `webappHostFromExec` |

What is *not* unit-testable this way: the components themselves. `import
Quickshell` fails under `qmltestrunner` (`plugin "quickshell-coreplugin" not
found`) — the Quickshell types live in the Quickshell binary. Component and
behaviour tests need a real Quickshell, i.e. the nest or the VM (drive via the
plugin's IPC and check the state files / `hyprctl`). Add to `logic.js` to make
more of the plugin testable.
