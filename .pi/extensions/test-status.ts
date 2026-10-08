import * as fs from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/**
 * Test-run status for this repo, scoped to this pi session.
 *
 * `tests/async.sh run <label> ...` starts a run detached and, when the run is
 * over, writes one `<log>.status` file next to its log: a `session:` stamp when
 * a pi session started it (PI_SESSION_ID), then the summary line, the counts,
 * the failing scenarios, and the log path. This watches that directory and
 * turns a new or changed status file into a message in the session -- but only
 * when the stamp matches this session. A run Goose started, or one from a
 * terminal, has no stamp (or a different one) and must not start a turn here.
 * Same mechanism as examples/extensions/file-trigger.ts, on the file the test
 * runner already writes.
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

function parseStatus(text: string): { session: string | undefined; body: string } {
  if (!text.startsWith("session: ")) return { session: undefined, body: text };
  const nl = text.indexOf("\n");
  if (nl < 0) return { session: text.slice("session: ".length).trim(), body: "" };
  return {
    session: text.slice("session: ".length, nl).trim(),
    body: text.slice(nl + 1),
  };
}

function sessionIdFrom(ctx: {
  sessionManager?: { getSessionFile?: () => string | null | undefined };
}): string | undefined {
  const file = ctx.sessionManager?.getSessionFile?.();
  if (!file) return undefined;
  const base = file.split(/[/\\]/).pop() || "";
  const fromName = base.match(
    /_([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$/i,
  );
  if (fromName) return fromName[1];
  try {
    const header = JSON.parse(fs.readFileSync(file, "utf-8").split("\n")[0] || "null") as {
      id?: unknown;
    };
    if (typeof header?.id === "string" && header.id) return header.id;
  } catch {
    // Ephemeral sessions have no file yet; those runs simply do not report back.
  }
  return undefined;
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
  let sessionId: string | undefined;

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
      // No stamp, or a stamp for another session: Goose, a terminal, a second
      // pi session. /test-status still lists them; they must not start a turn.
      const parsed = parseStatus(info.text);
      if (!sessionId || parsed.session !== sessionId || !parsed.body.trim()) continue;
      pi.sendMessage(
        {
          customType: "xmode-test-status",
          content: parsed.body,
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
    sessionId = sessionIdFrom(ctx);
    scan();
    try {
      watcher = fs.watch(DIR, () => schedule());
    } catch {
      watcher = undefined;
    }
    poll = setInterval(scan, POLL_MS);
    poll.unref?.();
    if (ctx.hasUI) {
      ctx.ui.notify(
        sessionId
          ? "test runs this session starts report back here"
          : `test runs in ${DIR} report back here`,
        "info",
      );
    }
  });

  pi.on("session_shutdown", async () => {
    watcher?.close();
    watcher = undefined;
    if (poll) clearInterval(poll);
    poll = undefined;
    if (debounce) clearTimeout(debounce);
    debounce = undefined;
    sessionId = undefined;
  });
}
