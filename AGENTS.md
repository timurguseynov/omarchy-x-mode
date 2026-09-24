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

- `hypr/x-mode.lua` — Hyprland config and the snap / grouping engine.
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

- Do not test by hand. If something needs to be checked, say so and wait: the
  user will check it. If you need log output, ask for it instead of collecting
  it yourself.
- After every successful edit or completed task, commit in the repo that owns
  the change. Pack changes go to this repo. Sandbox changes (`_docs/`, and the
  outer checkout's `AGENTS.md` and `.pi/`) go to the outer repo. The message
  says what changed and why.

## Discord update

When asked for a Discord post, write it the way `_docs/discord.update.md` does:
one line of the few highlights actually worth announcing, then one short line
for everything else ("Plus minor bug fixes and polish: …"). Keep it to what a
user would notice. End with `Update with ./install.sh`.
