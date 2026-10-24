#!/usr/bin/env python3
"""Keep PI_SESSION_ID in Grok's terminal tool.

pi-xai-oauth deletes Pi's session variables from run_terminal_command. The
transcript path and the model fingerprint stay deleted. PI_SESSION_ID has to
survive: tests/async.sh stamps a status file with it, and
.pi/extensions/test-status.ts only reports a run back into the session that
started it.

The package lives in node_modules, so an update puts the deletion back. This
rewrites that one string list and nothing else. If the list is no longer a
plain array of names, or it is no longer what the terminal hook deletes, it
exits without writing.

    tests/keep-pi-session-id.py [path/to/grok-native.ts]

No path: the installed pi-xai-oauth under ~/.pi/agent/npm/node_modules.
"""

import os
import re
import sys
from pathlib import Path

KEEP = "PI_SESSION_ID"
MUST_STAY = "PI_SESSION_FILE"
CONST = "PI_SESSION_ENVIRONMENT_KEYS"
ARRAY = re.compile(
    r"const " + CONST + r" = \[(.*?)\] as const;",
    re.DOTALL,
)
ENTRY = re.compile(r'"([A-Z0-9_]+)"')


def installed_source() -> Path:
    root = Path(os.environ.get("PI_AGENT_DIR", Path.home() / ".pi/agent"))
    return (
        root
        / "npm/node_modules/pi-xai-oauth/extensions/xai/tools/grok-native.ts"
    )


def fail(message: str) -> None:
    print(f"fail: {message}", file=sys.stderr)
    raise SystemExit(1)


def string_entries(body: str) -> list[str]:
    """Names in a plain string array. None when the body is not just those."""
    without = re.sub(r"/\*.*?\*/", "", body, flags=re.DOTALL)
    without = re.sub(r"//[^\n]*", "", without)
    if not re.fullmatch(r'[\s,"A-Z0-9_]*', without):
        fail(
            f"{CONST} is not a plain list of strings; "
            "the package layout changed, edit it by hand"
        )
    return ENTRY.findall(without)


def hook_deletes_this_list(text: str) -> bool:
    """True when the terminal hook still deletes whatever that list holds."""
    return (
        re.search(
            r"for\s*\(\s*const\s+\w+\s+of\s+"
            + CONST
            + r"\s*\)\s*delete\s+context\.env\[\w+\]",
            text,
        )
        is not None
    )


def patch(text: str) -> str | None:
    found = list(ARRAY.finditer(text))
    if len(found) != 1:
        fail(
            f"expected one `{CONST}` list, found {len(found)}; "
            "the package layout changed, edit it by hand"
        )
    if not hook_deletes_this_list(text):
        fail(
            f"{CONST} is not the list the terminal hook deletes; "
            "editing it would not change the command environment"
        )
    match = found[0]
    entries = string_entries(match.group(1))
    if MUST_STAY not in entries:
        fail(f"refusing to edit a list that does not keep {MUST_STAY}")
    if KEEP not in entries:
        return None
    if entries.count(KEEP) != 1:
        fail(f"{KEEP} appears {entries.count(KEEP)} times in {CONST}")
    kept = [name for name in entries if name != KEEP]
    if not kept:
        fail(f"refusing to leave {CONST} empty")
    body = "\n" + "".join(f'  "{name}",\n' for name in kept)
    return text[: match.start(1)] + body + text[match.end(1) :]


def main() -> None:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else installed_source()
    if len(sys.argv) > 2:
        fail("usage: keep-pi-session-id.py [grok-native.ts]")
    if not path.is_file():
        fail(f"not found: {path}")
    original = path.read_text()
    updated = patch(original)
    if updated is None:
        print(f"ok: already keeps {KEEP} ({path})")
        return
    if updated == original:
        print(f"ok: already keeps {KEEP} ({path})")
        return
    path.write_text(updated)
    print(f"patched: {KEEP} stays, {MUST_STAY} is still deleted ({path})")


if __name__ == "__main__":
    main()
