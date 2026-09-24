# X Mode — Omarchy pack

macOS-like desktop layer for Omarchy (Hyprland + Quickshell): floating windows,
a Mac titlebar with per-tab close buttons, Rectangle-style snapping, a
right-edge dock and an app switcher.

This directory is the pack, and its own git repo (the public mirror). The
sandbox around it lives in `_docs/`: reference trees under `_docs/_sources/`,
notes under `_docs/_info/`. Developed and run **on this machine**. Reinstall
from here with:

```sh
./uninstall.sh && ./install.sh
```

`./install.sh` is additive: it only creates files in its own namespace and one
sentinel block in `~/.config/hypr/hyprland.lua`. `./uninstall.sh` removes
exactly what the install recorded. `./install.sh status` shows what is
installed. `--no-hyprbars` skips the titlebar plugin build.

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
  without a compositor: `geom.lua` (frame and zone math, window fit),
  `settings.lua` (option/app parsing, rule diff), `theme.lua` (colors.toml),
  `mru.lua` (switcher order).
- `tests/` — the test suite. `tests/run.sh` runs `unit/` (plain lua, no
  compositor) then `nest/` (a nested Hyprland running the real config and a
  freshly built plugin); `tests/README.md` has the details.
- `hyprbars/` — vendored patched hyprbars (titlebar, tabbar, drag, snap).
  `build.sh` builds it; `README.md` lists its config keys.
- `quickshell/x-mode/` — the shell plugin.
  - `Dock.qml` — right-edge dock.
  - `SnapPreview.qml` — snap zone preview.
  - `Switcher.qml` — app switcher.
  - `Panel.qml`, `Toggle.qml` — bar toggle and settings panel.
  - `IconResolver.qml` — app icon lookup.
  - `manifest.json` — plugin manifest.
- `install.sh`, `uninstall.sh` — install and remove the pack.

Sandbox, under `_docs/`, read-only unless a note is being written:

- `_docs/_sources/` — reference checkouts (Hyprland, upstream hyprbars,
  Quickshell, Rectangle, Omarchy, and others). See `_docs/_sources/INDEX.md`.
  Search them with the `xref` tool, not by reading whole trees.
- `_docs/_info/` — notes. Not pack code.
- `_docs/discord.update.md` — the shape of a Discord update post.

## Working rules

- Do not test by hand on the live session. If something needs to be checked
  there, say so and wait: the user will check it. If you need log output, ask
  for it instead of collecting it yourself.
- `tests/run.sh` is the sanctioned check, and it is automated and isolated: the
  unit layer is plain lua, the nest layer is a nested Hyprland with its own
  state dir. Run it before committing a change to `x-mode.lua`, a module, the
  plugin or an install file.
- Editing and installing are separate steps: make the change in this repo, run
  `tests/run.sh`, and only then install. Never hand-edit or copy over the
  installed files (`~/.config/hypr/x-mode.lua`, `~/.config/hypr/x-mode/`,
  `~/.local/share/hyprbars/`): `install.sh` is the only writer, so its manifest
  stays right and a test build never lands on the live session half-done.
- `./install.sh --no-hyprbars` installs the Lua and the modules without touching
  the plugin; use it when `hyprbars/` did not change (the build is the slow
  step).
- Keep pure logic (no `hl`) in the `hypr/x-mode/` modules so it stays unit
  testable; event/state code stays in `x-mode.lua` and is covered by the nest.
- Never load the pack's plugin into the live session and never `cp` over the
  loaded `x-mode-hyprbars.so`: overwriting a mapped `.so` corrupts its pages and
  crashes the compositor (`SIGILL`). The nest is where a plugin gets loaded.
- After every successful edit or completed task, commit in the repo that owns
  the change. Pack changes go to this repo. Sandbox changes (`_docs/`, and the
  outer checkout's `AGENTS.md` and `.pi/`) go to the outer repo. The message
  says what changed and why.

## Discord update

When asked for a Discord post, write it the way `_docs/discord.update.md` does:
one line of the few highlights actually worth announcing, then one short line
for everything else ("Plus minor bug fixes and polish: …"). Keep it to what a
user would notice. End with `Update with ./install.sh`.
