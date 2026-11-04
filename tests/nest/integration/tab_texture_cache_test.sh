#!/usr/bin/env bash
# A tab's title texture is cached in CHyprBar::m_tabTexs, keyed by the title text,
# and that map is only ever cleared by onConfigReloaded. So a window that renames
# itself -- anything that draws a live title: a browser, a shell prompt with a cwd,
# an editor's current file -- leaves a texture behind for every title it has had
# while it sat in a group, and none of them is ever drawn again. The bar pays for
# them in GPU memory until the config is reloaded.
#
# What this pins is the *observation*: the plugin publishes the size of that cache
# (renderTabs writes it to $XDG_RUNTIME_DIR/omarchy-x-mode.tab-textures whenever
# its own number changes). With one grouped window that retitles itself twelve
# times, a cache that keeps only the tabs on screen holds at most a handful of
# entries; a cache that never drops anything holds every title it saw.
#
# The assertion is expected to be red until the keys the group no longer has are
# dropped. It is deliberately not loosened to match what the bar does today: a
# bound that is set to whatever the bug produces pins the bug.
. "$(dirname "$0")/../../lib.sh"

SIZE_FILE="$NEST_RUNTIME/omarchy-x-mode.tab-textures"
TITLES="$NEST_RUNTIME/tab-textures-title"
LAST=12

# The window under test paints its own titles: OSC 2 through /dev/tty, one every
# 0.25s, with the number it used written to a file after each. shellPrompt reads
# the OSC off the terminal's output, so the title the compositor reports is the
# one this loop chose -- not a cwd and not the shell's own title.
rm -f "$SIZE_FILE" "$TITLES"
# Same class as the second window: grouping is by class, and only a group draws
# the tab cache this test reads. The OSC goes to the shell's stdout, which foot
# attaches to the pty; /dev/tty is not there because the nest starts the client
# with no controlling terminal.
open_command foot foot sh -c "
  i=1
  while [ \"\$i\" -le $LAST ]; do
    printf '\033]2;cache-%s\007' \"\$i\"
    printf '%s' \"\$i\" > '$TITLES'
    i=\$((i + 1))
    sleep 0.25
  done
  sleep 30
"

# The second foot joins the first. open_window's count is the total, and the
# command above already opened one.
open_window foot 2

# The title loop has to have run to the end before the cache is read: the last
# title is what the final texture is for, and the earlier ones are the leftovers.
marker=""
for _ in $(seq 1 $((100 * NEST_SLOW))); do
  marker="$(cat "$TITLES" 2>/dev/null || true)"
  [ "$marker" = "$LAST" ] && break
  sleep 0.1
done

size="$(cat "$SIZE_FILE" 2>/dev/null || echo absent)"
group="$(group_size foot)"
titles_seen="$(cat "$TITLES" 2>/dev/null || echo absent)"

# Everything the failure needs to say which half broke: the window's own count of
# titles, the published cache size (or that nothing was published at all), and
# whether the two windows were ever a group -- two ungrouped windows have one tab
# each, and a cache that holds 2 for that reason is not this bug.
if [ "$marker" != "$LAST" ] || [ "$size" = absent ] || [ "${size:-99}" -gt 4 ] 2>/dev/null; then
  echo "  title loop reached: '$titles_seen' (want $LAST)" >&2
  echo "  cache size file:    '$size' in $SIZE_FILE" >&2
  echo "  group_size foot:    '$group'" >&2
fi

[ "$marker" = "$LAST" ] || fail "foot never got to title cache-$LAST (its marker says '$titles_seen')"

# The plugin has to have published at all. An absent file is a bar that never
# drew a tabbar, and a size read from a file nobody wrote is not evidence.
[ "$size" != absent ] || fail "the plugin published no tab texture count at $SIZE_FILE (group_size foot: '$group')"
case "$size" in
  '' | *[!0-9]*) fail "the tab texture count is not a number: '$size' (group_size foot: '$group')" ;;
esac

# A bounded cache keeps the current tabs and drops what the group no longer has:
# two tabs, so at most a couple of title variants each -- four is generous and
# still impossible for a cache that kept all twelve titles of one window.
assert_le "$size" 4 "the tab texture cache held $size textures after $LAST titles of one grouped window (group_size foot: '$group')"
