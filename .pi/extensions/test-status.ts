import * as fs from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * Test-run status for this repo.
 *
 * `tests/async.sh run <label> ...` starts a run detached and, when the run is
 * over, writes one `<log>.status` file next to its log: the summary line, the
 * counts, the failing scenarios, and the log path. This watches that directory
 * and turns a new or changed status file into a message in the session, so a
 * finished -- or failed -- run reaches the agent by itself. It is the same
 * mechanism as examples/extensions/file-trigger.ts, on the file the test runner
 * already writes.
 *
 * The agent starts a run and stops there; the run reports back. See AGENTS.md,
 * "Running the suite from an agent session".
 */

const DIR = process.env.XDG_RUNTIME_DIR || "/tmp";
const PREFIX = "xmode-test-";
const SUFFIX = ".status";
// fs.watch is the fast path but is not reliable on every filesystem; the poll
// is the cheap backstop. Both only read a handful of small files.
const POLL_MS = 3000;
const DEBOUNCE_MS = 250;

function statusPaths(dir: string): string[] {
  let names: string[];
  try {
    names = fs.readdirSync(dir);
  } catch {
    return [];
  }
  return names.filter((n) => n.startsWith(PREFIX) && n.endsWith(SUFFIX)).map((n) => join(dir, n));
}

function read(path: string): { text: string; mtime: number } | undefined {
  try {
    const text = fs.readFileSync(path, "utf-8").trim();
    if (!text) return undefined;
    return { text, mtime: fs.statSync(path).mtimeMs };
  } catch {
    return undefined;
  }
}

export default function (pi: ExtensionAPI) {
  let watcher: fs.FSWatcher | undefined;
  let poll: NodeJS.Timeout | undefined;
  let debounce: NodeJS.Timeout | undefined;
  // What each status file said when it was last seen. A file is reported when
  // its contents change, so a run that writes a bigger file twice (or a second
  // run reusing the label) is a new message, and a repeat of the same contents
  // is not.
  const seen = new Map<string, string>();
  let primed = false;

  function scan(): void {
    const live = new Set(statusPaths(DIR));
    for (const path of [...seen.keys()]) {
      if (!live.has(path)) seen.delete(path);
    }
    for (const path of live) {
      const info = read(path);
      if (info === undefined || seen.get(path) === info.text) continue;
      seen.set(path, info.text);
      // The first scan only records what is already there: a run that finished
      // before this session started is not news. /test-status shows those.
      if (!primed) continue;
      pi.sendMessage(
        {
          customType: "xmode-test-status",
          content: info.text,
          display: true,
        },
        { triggerTurn: true },
      );
    }
    primed = true;
  }

  function schedule(): void {
    if (debounce) clearTimeout(debounce);
    debounce = setTimeout(() => {
      debounce = undefined;
      scan();
    }, DEBOUNCE_MS);
    debounce.unref?.();
  }

  function latest(limit: number): string[] {
    const entries = [...seen.keys()]
      .map((path) => ({ path, info: read(path) }))
      .filter((e): e is { path: string; info: { text: string; mtime: number } } => e.info !== undefined)
      .sort((a, b) => b.info.mtime - a.info.mtime);
    return entries.slice(0, limit).map((e) => e.info.text);
  }

  pi.registerCommand("test-status", {
    description: "Show the last test-run status files (tests/async.sh)",
    handler: async (_args, ctx) => {
      scan();
      const rows = latest(3);
      ctx.ui.notify(rows.length > 0 ? rows.join("\n\n") : `No test status in ${DIR} yet`, "info");
    },
  });

  pi.on("session_start", async (_event, ctx) => {
    // A long-lived watcher belongs to the session, not to the factory: some
    // invocations load extensions without starting one.
    scan();
    try {
      watcher = fs.watch(DIR, () => schedule());
    } catch {
      watcher = undefined;
    }
    poll = setInterval(scan, POLL_MS);
    poll.unref?.();
    if (ctx.hasUI) ctx.ui.notify(`test runs in ${DIR} report back here`, "info");
  });

  pi.on("session_shutdown", async () => {
    watcher?.close();
    watcher = undefined;
    if (poll) clearInterval(poll);
    poll = undefined;
    if (debounce) clearTimeout(debounce);
    debounce = undefined;
  });
}
