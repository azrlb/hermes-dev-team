/**
 * Absolute Paths Enforcer
 *
 * Prevents the "double-nested path" failure seen in Hermes dev-team evals.
 *
 * Failure pattern: Brain invoked Pi with prompt containing path like
 * "packages/auth/src/mtls.ts". Pi's CWD was already
 * /media/bob/C/AI_Projects/FlowInCash-Core/packages/auth so the relative path
 * resolved to packages/auth/packages/auth/src/mtls.ts. Fix landed at a
 * nonsense path and the real file was untouched.
 *
 * Strategy: intercept tool_call for write/edit/read; if path is relative,
 * resolve to absolute against process.cwd() and mutate the input. Log the
 * correction so Brain sees that the path was normalized. For bash commands
 * that contain file paths, we don't parse them (too risky) — we only handle
 * structured file-tool inputs.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { isAbsolute, resolve } from "node:path";

const FILE_TOOLS = new Set(["read", "write", "edit"]);

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event) => {
    if (!FILE_TOOLS.has(event.toolName)) return undefined;

    const input = event.input as { path?: string; file_path?: string };
    const field = input.path !== undefined ? "path" : input.file_path !== undefined ? "file_path" : null;
    if (!field) return undefined;

    const raw = (input as Record<string, string>)[field];
    if (typeof raw !== "string" || raw.length === 0) return undefined;

    if (isAbsolute(raw)) return undefined;

    const absolute = resolve(process.cwd(), raw);
    (input as Record<string, string>)[field] = absolute;

    // Let Pi log the mutation in the tool-call trace so Brain sees the corrected path.
    return undefined;
  });
}
