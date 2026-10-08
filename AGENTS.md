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

- `hypr/x-mode/` — the pack's Hyprland config: `x-mode.lua` is the desktop
  layer (Hyprland config, binds/events, and the snap / grouping engine), and the
  pure modules it loads are split out next to it so they can be tested without a
  compositor: `settings.lua` (option/app parsing, rule diff), `theme.lua`
  (colors.toml), `mru.lua` (switcher order), `supermap.lua` (the Super-as-Ctrl
  plan). Geometry is *not* here: the plugin owns it (`hyprbars/snap.cpp` — zones,
  the snap cycle, the work frame, the chrome), and `x-mode.lua` asks for it.
- `tests/` — the test suite. `tests/run.sh` runs lint (`qmllint`), `unit/` (plain
  lua, no compositor), `qml/` (`logic.js` under `qmltestrunner`) and `nest/` (a
  nested Hyprland running the real config and a freshly built plugin, with
  `nest/integration/` holding the regressions). `tests/pointer/` and
  `tests/keyboard/` are the tools that let a scenario click, drag and press keys,
  and the dock runs a Quickshell of its own; `tests/README.md` has the details.
  Run the full suite and the nest **only** as `NEST_JOBS=5 NEST_WORKSPACE=5`;
  other values are not a sanctioned check and their results do not count.
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
  (`NEST_JOBS=5 NEST_WORKSPACE=5 tests/nest/run.sh <name>`), and only then change pack code. A fix with no
  test that failed first is a guess: the suite is the only thing that can tell a
  later edit from a regression.
- Do not test by hand on the live session. If something needs to be checked
  there, say so and wait: the user will check it. If you need log output, ask
  for it instead of collecting it yourself.
- `tests/run.sh` is the sanctioned check. Always run it, and `tests/nest/run.sh`,
  as `NEST_JOBS=5 NEST_WORKSPACE=5`: five nests at once, mapped on workspace 5.
  That is the only sanctioned way to run them. Do not run the full `tests/run.sh`
  or the whole nest with a different `NEST_JOBS`/`NEST_WORKSPACE` (including the
  defaults), and do not treat such a run as evidence: a difference there is a
  property of the run, not of the change.
  The nests run on the live session by default (`NEST_HOST=session`), which is the
  sanctioned mode. `NEST_HOST=shared` is a Hyprland host of the run's own on a vkms
  card, and is not green yet (see tests/README.md); it is not what the sanctioned
  run uses.
  It is automated and isolated: the unit layer is plain lua, the nest layer is a
  nested Hyprland with its own state directory and a runtime directory of its
  own, so nothing the pack writes (the state file, the switcher and preview
  command files) reaches the running session. Run it before committing a change
  to `x-mode.lua`, a module, the plugin or an install file.
- Editing and installing are separate steps: make the change in this repo, run
  `tests/run.sh`, and only then install. Never hand-edit or copy over the
  installed files (`~/.config/hypr/x-mode/`, `~/.local/share/hyprbars/`):
  `install.sh` is the only writer, so its manifest stays right and a test build
  never lands on the live session half-done. The panel's settings
  (`~/.config/hypr/x-mode.json`) are the user's and sit next to that directory,
  not in it.
- Keep pure parsing (no `hl`) in the `hypr/x-mode/` modules so it stays unit
  testable; event/state code stays in `x-mode.lua` and is covered by the nest.
  Geometry is the plugin's (`Snap::`), so there is one implementation: the pack
  is its plugin, and Lua asks it (`snap`, `cycle`, `zone`, `usable`,
  `chrome_height`) instead of keeping a second copy in step.
- Never load the pack's plugin into the live session and never `cp` over the
  loaded `x-mode-hyprbars.so`: overwriting a mapped `.so` corrupts its pages and
  crashes the compositor (`SIGILL`). The nest is where a plugin gets loaded.
- After every successful edit or completed task, commit in the repo that owns
  the change. The message says what changed and why. The commit flow is the
  user's: the `pi-git-commit` extension blocks `git add`/`git commit` in the
  agent's bash and unlocks the `git_commit` tool only while `/commit` is open, so
  the agent finishes a task, says it is ready, and waits for `/commit` -- it
  cannot stage or commit on its own. `/toggle-allow-git` is what allows
  mutative git in bash for a session, if the user wants the agent to commit
  without the flow.

## Running the suite from an agent session

Tests here take minutes, and an agent tool call that waits for one is killed
part-way: that reads as a hang and wastes the run. So **no test run is waited for
inside a call**. The agent's whole part is to start the run detached; the run
reports itself when it is over (see the status file below), and the agent
resumes from that report.

```sh
bash tests/async.sh run suite bash tests/run.sh
bash tests/async.sh run keys  bash tests/nest/run.sh key_pin digit_tabs
```

`async.sh` sets the sanctioned `NEST_JOBS=5 NEST_WORKSPACE=5` and keeps one log
per label under `$XDG_RUNTIME_DIR`.

After starting a run, say which label is going and stop there: do **not** poll it
with `status`, do not `sleep` before a check, and do not wait for it in a call.

`tests/async.sh run` writes `<log>.status` the moment a run ends: the same text
`status` prints (state, summary lines, counts, the failing scenarios) plus the
log path. The project extension `.pi/extensions/test-status.ts` watches those
files and sends that text as a message that starts a turn, so **the run reports
itself**: the agent starts a run, stops, and resumes on its own when the report
arrives -- no timer, no poll, no token. The user's token (`готово` when the run
is green, `+` when there is something in it for the agent) is only the fallback
for when the watcher is not loaded, such as a session started before the
extension was added.

Once a run has reported itself (or been reported), the agent may read the log,
the status file and the run's counts -- that is looking at a finished run, not
polling a going one. Only the sanctioned invocation counts as evidence, and a run
counts once its status file says finished with `FAIL: 0`, `WARN: 0` and
`NOT RUN: 0`:

- `WARN` is Hyprland's own errors, reported as `WARN` lines: a config that threw
  while parsing, a Lua callback that threw while the session ran. Those are real
  -- a parse that died halfway used to pass as green.
- `NOT RUN` is a scenario the run was asked for and never reported: a slot whose
  nest would not come up, or a scenario lost with the worker that held it. The
  run is red for those, because it ran less than it was asked to. The check diffs
  the chosen scenarios against what was reported by name, so a scenario that was
  taken from the queue and then lost cannot slip through.

While a run is going, work on something that cannot invalidate it: do not edit
files a running suite reads, and start no second run against the same scenarios.
If there is nothing else to do, say so and stop: the report is a message that
will arrive.

A scenario written to look at one thing while working on a test is named
`tests/nest/integration/debug_tmp_test.sh`: it is gitignored on purpose, and it
must be deleted or renamed before the change lands.
