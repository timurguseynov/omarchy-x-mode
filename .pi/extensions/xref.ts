import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { spawn } from "node:child_process";
import { resolve } from "node:path";

function run(cmd: string, args: string[], cwd: string, signal?: AbortSignal): Promise<{ stdout: string; code: number }> {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(cmd, args, { cwd, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => { stdout += d.toString(); });
    child.stderr.on("data", (d) => { stderr += d.toString(); });
    const onAbort = () => child.kill("SIGTERM");
    signal?.addEventListener("abort", onAbort, { once: true });
    child.on("error", reject);
    child.on("close", (code) => {
      signal?.removeEventListener("abort", onAbort);
      if (code !== 0 && !stdout) {
        reject(new Error(stderr.trim() || `exit ${code}`));
        return;
      }
      resolvePromise({ stdout: stdout.trimEnd(), code: code ?? 0 });
    });
  });
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "xref",
    label: "xref",
    description:
      "Look up a symbol in _sources (Hyprland, hyprbars, Quickshell, Rectangle, Omarchy) via ctags. Returns compact file:line + kind + name. Use before grepping those trees.",
    promptSnippet: "Jump to a function/class/method in _sources reference checkouts (ctags)",
    promptGuidelines: [
      "Use xref to find functions, classes, methods, and QML ids in _sources (Hyprland C++, hyprbars, Quickshell QML, Rectangle Swift, Omarchy) instead of grepping the whole tree.",
      "Call xref with the symbol name first (exact). If empty, retry with match=prefix or match=substr. Then read only the matching file around that line.",
      "Do not rg/find across _sources until xref misses; do not dump whole files from _sources.",
    ],
    parameters: Type.Object({
      name: Type.String({ description: "Symbol to find, e.g. layoutTarget, CHyprBar, onMouseButton" }),
      match: Type.Optional(Type.String({
        description: "exact (default), prefix, or substr",
      })),
      kind: Type.Optional(Type.String({
        description: "Optional kind filter: f function, c class, s struct, m member, p prototype, t type, i id",
      })),
      limit: Type.Optional(Type.Number({ description: "Max rows (default 40)" })),
    }),
    async execute(_id, params, signal, _onUpdate, ctx) {
      const extra = resolve(ctx.cwd, "_docs/_sources");
      const script = resolve(extra, "scripts/xref.sh");
      const args: string[] = [];
      if (params.match === "prefix") args.push("-p");
      if (params.match === "substr") args.push("-s");
      if (params.kind) args.push("-k", String(params.kind));
      if (params.limit) args.push("-n", String(params.limit));
      args.push(params.name);
      const { stdout } = await run(script, args, extra, signal);
      const text = stdout || "(no matches)";
      return { content: [{ type: "text", text }], details: { count: stdout ? stdout.split("\n").length : 0 } };
    },
  });
}
