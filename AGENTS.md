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
- A fix that does not fix is reverted, not kept. When the scenario that was added
  to fail first is still red after the change -- or a probe that was made to test a
  guess shows the guess was wrong -- the change goes back out (`git checkout --
  <file>`, `git revert`, or `git reset` before it was committed) and the next idea
  starts from a clean tree. A guess that stayed in the code is worse than no guess:
  it reads like a fix to the next reader, it has its own tests to keep green, and
  it hides the real one. The same for a probe: logging, an extra wait in a test, a
  "maybe this helps" line in the helper -- if it did not answer the question it was
  written for, it is removed in the same turn. Keep only what turned its own red
  green, or what the report it came from explicitly asked for.
- A scenario that fails in a full run is the agent's to isolate, and it is chased
  on its own -- `tests/async.sh run <label> bash tests/nest/run.sh <name>` -- not
  by running the suite again. The whole run is not there to prove that the
  scenarios work together: it is there to prove that what changed did not break
  anything that is related to it (the grouping of the dock, the keys of a mode,
  the plugin under an install). So a red scenario is read alone, first at its own
  name and then against whatever it shares state with, and the full run comes back
  as the last check before a commit, not as the way to investigate. Nothing in the
  suite retries anything: a red line is a red line, and it is the agent that runs it
  again, by hand, once the reason is known. Run *that scenario* -- not a group of
  them, not a filter that happens to match its neighbours: a group is a different
  run with a different order, so it neither reproduces what the full run did nor
  proves the scenario is fine, and it costs the same minutes for nothing.
- A scenario carries the diagnostics that would name its cause, and a red one
  gets them added. `assert_eq ... (got X)` says what the scenario read; it does
  not say who wrote X, so on a failure the run leaves the other side behind too:
  the dock's own click log, the order file, the pack's published mode, the tail of
  the relevant log. That is how the last two dock failures were found -- the click
  log said `press right kitty` where the test aimed at foot, and the menu's own
  layer box showed the card clamped away from where the helper thought it was.
  Print them on failure, not on a green run (a successful run stays quiet and
  fast), and prefer a product that publishes what it saw over a test that guesses:
  the dock's order file, the workspace mode the pack publishes, the
  `X_MODE_DOCK_DEBUG` click log. Every red scenario is an opportunity to move a
  guess into an observation, so the next run of that scenario explains itself
  instead of needing a probe.
- Do not test by hand on the live session. If something needs to be checked
  there, say so and wait: the user will check it. If you need log output, ask
  for it instead of collecting it yourself.
- `tests/run.sh` is the sanctioned check. Always run it, and `tests/nest/run.sh`,
  as `NEST_JOBS=5 NEST_WORKSPACE=5`: five nests at once, mapped on workspace 5.
  That is the only sanctioned way to run them. Do not run the full `tests/run.sh`
  or the whole nest with a different `NEST_JOBS`/`NEST_WORKSPACE` (including the
  defaults), and do not treat such a run as evidence: a difference there is a
  property of the run, not of the change.
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
- Panel copy is one caption line. A SwitchRow or LinkRow description is 30
  characters or less: the settings card is 360px and elides anything longer.
  Put the rest in the README, not in the row.
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

**Nothing in this flow gets a timeout.** Not the run (`timeout 900 bash
tests/async.sh run ...`), not a `sleep` before looking at a log, not a `tail` of
a log that a scenario is still writing. A timeout is a guess about how long the
work takes, and it turns "the run is still going" into "the run failed" without
telling anyone which. The run reports itself when it ends, so the absence of a
report is not a reason to wait longer -- it is the answer. If the report does not
arrive, something is wrong with the report: the watcher is not loaded, the status
file has no `session:` stamp from this session, the worker died, or the run was
started from a tool that deleted `PI_SESSION_ID`. Look at that, by hand, and fix
it; do not add a sleep and check again.

A `sleep` right after `async.sh run` is the shape this goes wrong in, and it
keeps looking harmless: it is only a few seconds, and then a `ls` or a `tail` to
"see how it is going". Do not do it. There is nothing to see -- the log is empty
until the run ends -- so the turn is over the moment the label is named. If
there is work that cannot invalidate the run (reading a finished run's log,
editing something no scenario reads), do that; if there is not, end the turn and
let the report arrive.

`tests/async.sh run` writes `<log>.status` the moment a run ends: the same text
`status` prints (state, summary lines, counts, the failing scenarios) plus the
log path, and a `session:` stamp when a pi session started the run. The project
extension `.pi/extensions/test-status.ts` watches those files and sends that
text as a message that starts a turn **only when the stamp is this session**, so
**the run reports itself** and a run Goose or another session started does not:
the agent starts a run, stops, and resumes on its own when the report arrives --
no timer, no poll, no token. The user's token (`готово` when the run is green,
`+` when there is something in it for the agent) is only the fallback for when
the watcher is not loaded, such as a session started before the extension was
added.

That report starts a turn, and the turn is not the user talking. It is one
machine message about one finished run: read the log and the status file, say
what they say, and stop. Do not pick the previous conversation back up, do not
re-ask a question that is still waiting for an answer, and do not read a green
run as the user agreeing to anything -- `FAIL: 0` means the check passed and
nothing else. The turn is over when the run is accounted for: a red run is the
agent's to isolate (its scenario, alone, as above); a green one that only
confirms what was already said gets one line, not a new subject.

The stamp is `PI_SESSION_ID`, which Pi's own bash tool exports. Grok's
`run_terminal_command` (package `pi-xai-oauth`,
`extensions/xai/tools/grok-native.ts`) deletes it, together with the transcript
path and the model fingerprint, so a run started from that tool writes a status
file with no `session:` line and the watcher stays quiet. `tests/keep-pi-session-id.py`
puts `PI_SESSION_ID` back and leaves the other four deleted. It rewrites only
the `PI_SESSION_ENVIRONMENT_KEYS` list, and it does not write at all if that
list is no longer a plain list of names or no longer the list the terminal hook
deletes. Run it when a status file from this session has no `session:` line, and
again after the package is updated: the edit is in `node_modules` and a
reinstall drops it. The pi process that is already running keeps the old hook
until it is restarted.

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
