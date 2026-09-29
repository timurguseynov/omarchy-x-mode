# X Mode — Omarchy pack

macOS-like desktop layer for Omarchy (Hyprland + Quickshell): floating windows,
a Mac titlebar with per-tab close buttons, Rectangle-style snapping, a
right-edge dock and an app switcher.

This directory is the pack, and its own git repo (the public mirror). Developed
and run **on this machine**. Reinstall from here with:

```sh
./uninstall.sh && ./install.sh
```

`./install.sh` is additive: it only creates files in its own namespace and one
sentinel block in `~/.config/hypr/hyprland.lua`. `./uninstall.sh` removes
exactly what the install recorded. `./install.sh status` shows what is
installed.

For work on the pack, also read `_docs/AGENTS.md` if it exists: it documents the
sandbox that surrounds this repo.

## Where things are

The code and its comments are the source of truth for how anything behaves.
This file only says where to look; do not duplicate behavior into it. When you
change behavior, update the comments next to the code, and read the existing
comments and the recent git history first so you keep fixes that are already
there.

Pack code, in this repo:

- `hypr/x-mode.lua` — the desktop layer: Hyprland config, binds/events, and the
  snap / grouping engine.
- `hypr/x-mode/` — the pure modules it loads, split out so they can be tested
  without a compositor: `settings.lua` (option/app parsing, rule diff),
  `theme.lua` (colors.toml), `mru.lua` (switcher order). Geometry is *not* here:
  the plugin owns it (`hyprbars/snap.cpp` — zones, the snap cycle, the work
  frame, the chrome), and `x-mode.lua` asks for it.
- `tests/` — the test suite. `tests/run.sh` runs lint (`qmllint`), `unit/` (plain
  lua, no compositor), `qml/` (`logic.js` under `qmltestrunner`) and `nest/` (a
  nested Hyprland running the real config and a freshly built plugin, with
  `nest/integration/` holding the regressions). `tests/pointer/` and
  `tests/keyboard/` are the tools that let a scenario click, drag and press keys,
  and the dock runs a Quickshell of its own; `tests/README.md` has the details.
- `hyprbars/` — vendored patched hyprbars (titlebar, tabbar, drag, snap).
  `build.sh` builds it; `README.md` lists its config keys.
- `quickshell/x-mode/` — the shell plugin.
  - `logic.js` — the pure JS the components share (`pragma library`), unit
    tested with qmltestrunner.
  - `Dock.qml` — right-edge dock.
  - `SnapPreview.qml` — snap zone preview.
  - `Switcher.qml` — app switcher.
  - `Panel.qml`, `Toggle.qml` — bar toggle and settings panel.
  - `IconResolver.qml` — app icon lookup.
  - `manifest.json` — plugin manifest.
- `install.sh`, `uninstall.sh` — install and remove the pack.

## Working rules

- A fix starts with a test that fails. Add the unit or nest scenario that
  reproduces the report, run it, and see it fail for the reason the report gives
  (`tests/nest/run.sh <name>`), and only then change pack code. A fix with no
  test that failed first is a guess: the suite is the only thing that can tell a
  later edit from a regression.
- Do not test by hand on the live session. If something needs to be checked
  there, say so and wait: the user will check it. If you need log output, ask
  for it instead of collecting it yourself.
- `tests/run.sh` is the sanctioned check, and it is automated and isolated: the
  unit layer is plain lua, the nest layer is a nested Hyprland with its own state
  directory and a runtime directory of its own, so nothing the pack writes (the
  state file, the switcher and preview command files) reaches the running
  session. Run it before committing a change to `x-mode.lua`, a module, the
  plugin or an install file.
- Editing and installing are separate steps: make the change in this repo, run
  `tests/run.sh`, and only then install. Never hand-edit or copy over the
  installed files (`~/.config/hypr/x-mode.lua`, `~/.config/hypr/x-mode/`,
  `~/.local/share/hyprbars/`): `install.sh` is the only writer, so its manifest
  stays right and a test build never lands on the live session half-done.
- Keep pure parsing (no `hl`) in the `hypr/x-mode/` modules so it stays unit
  testable; event/state code stays in `x-mode.lua` and is covered by the nest.
  Geometry is the plugin's (`Snap::`), so there is one implementation: the pack
  is its plugin, and Lua asks it (`snap`, `cycle`, `zone`, `usable`,
  `chrome_height`) instead of keeping a second copy in step.
- Never load the pack's plugin into the live session and never `cp` over the
  loaded `x-mode-hyprbars.so`: overwriting a mapped `.so` corrupts its pages and
  crashes the compositor (`SIGILL`). The nest is where a plugin gets loaded.
- After every successful edit or completed task, commit in the repo that owns
  the change. The message says what changed and why.
