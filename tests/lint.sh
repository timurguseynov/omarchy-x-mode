#!/usr/bin/env bash
# Static QML check: qmllint over the shell plugin. The Quickshell and qs.*
# modules are not on the lint import path, so their "not found" warnings are
# expected; only real errors fail.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
QMLDIR="$HERE/../quickshell/x-mode"
LINT="${QMLLINT:-/usr/lib/qt6/bin/qmllint}"
GREEN=$'\033[32m'; RED=$'\033[31m'; RESET=$'\033[0m'

if [ ! -x "$LINT" ]; then
  echo "  ${RED}FAIL${RESET} qmllint not found at $LINT"
  exit 1
fi

fail=0
for f in "$QMLDIR"/*.qml; do
  out="$(QT_QPA_PLATFORM=offscreen "$LINT" "$f" 2>&1)"
  errs="$(printf '%s\n' "$out" | grep -E "Error:" || true)"
  if [ -n "$errs" ]; then
    echo "  ${RED}FAIL${RESET} $(basename "$f")"
    printf '%s\n' "$errs" | sed 's/^/       /'
    fail=1
  fi
done

# A row's three-state crosses a QML signal as a *string*: "inherit", "on", "off".
# Declared a bool, the signal coerces the value before the handler sees it -- "on"
# arrives as true and so does "inherit" (it pins where it meant to clear) -- and a
# state that matches nothing clears a flag instead of setting it: the switch blinks
# and stays off, and the file is rewritten without the flag. qmllint does not check
# signal argument types (a string passed to a bool parameter lints clean), so the
# contract is checked here.
for sig in 'signal flagToggled(string flag, string value)' 'signal keyToggled(string id, string value)'; do
  if ! grep -qF "$sig" "$QMLDIR/Panel.qml"; then
    echo "  ${RED}FAIL${RESET} Panel.qml: missing '$sig'"
    fail=1
  fi
done

# The card scrolls in three places -- the app list, an app's card and the keys
# screen -- and each region is given the room the rows above it leave. Those
# rows were listed by hand once per region, and the keys screen's list named the
# back row and the header but not the hero and the separator above them: that
# region was sized for a card taller than it was in, so it ran past the bottom
# of the card and its last rows could not be scrolled to. qmllint cannot see
# geometry, so the shape that cannot forget a row is pinned here: one figure,
# read off the card's own column, used by all three regions.
if ! grep -qF 'column.children.length' "$QMLDIR/Panel.qml"; then
  echo "  ${RED}FAIL${RESET} Panel.qml: fixedAboveHeight no longer reads the card's rows off its column"
  fail=1
fi
uses="$(grep -cF 'root.fixedAboveHeight' "$QMLDIR/Panel.qml")"
if [ "$uses" != 3 ]; then
  echo "  ${RED}FAIL${RESET} Panel.qml: fixedAboveHeight feeds $uses scroll regions, expected 3"
  fail=1
fi

# A watched state file is written by truncating it first (the panel, the toggle,
# the plugin and a reload all do), so a read can land in the middle of a write.
# Reading that as a state is what blanked the settings rows and collapsed the
# keys card for a moment on every toggle -- and what would flip the desktop on
# in the middle of a write. The readers go through Logic.readJsonAnswer /
# readEnabledLine, which answer "nothing" for a torn read; qmllint cannot see
# which reader has the guard, so the readers are pinned here.
json_reads="$(grep -cF 'Logic.readJsonAnswer(text())' "$QMLDIR/Panel.qml")"
if [ "$json_reads" != 2 ]; then
  echo "  ${RED}FAIL${RESET} Panel.qml: $json_reads of its 2 watched files keep their state on a torn read"
  fail=1
fi
for f in Toggle.qml Dock.qml Switcher.qml SnapPreview.qml; do
  if ! grep -qF 'Logic.readEnabledLine(' "$QMLDIR/$f"; then
    echo "  ${RED}FAIL${RESET} $f: reads the on/off line without Logic.readEnabledLine"
    fail=1
  fi
done

# A card's row shows the state's own words only for a moment after the click
# (Logic.appRowDescription): the tint carries the state, and the row goes back to
# what the replacement is for. qmllint cannot see the two rows, so they are
# pinned here -- a row that reads keyFlagDescription directly never goes back.
app_rows="$(grep -cF 'Logic.appRowDescription(' "$QMLDIR/Panel.qml")"
if [ "$app_rows" != 2 ]; then
  echo "  ${RED}FAIL${RESET} Panel.qml: $app_rows of the 2 app-key rows go back to their meaning after the click"
  fail=1
fi

[ "$fail" = 0 ] && echo "  ${GREEN}ok${RESET}   qmllint (missing Quickshell/qs imports warn, they do not fail)"
exit "$fail"
