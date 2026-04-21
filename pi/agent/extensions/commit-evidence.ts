/**
 * Commit Evidence
 *
 * Prevents the "lazy close" failure seen in Hermes dev-team evals (qwen3:30b
 * Brain closed T3 P1 crypto ticket as "already resolved" based on a grep
 * match, without any code change landing).
 *
 * Strategy:
 *   - Intercept bash calls that close a beads issue (bd close, bd update
 *     --status=closed).
 *   - Parse the issue ID from the command.
 *   - Check git log for a recent commit referencing that issue ID in the
 *     message or as a files-changed touching the relevant file.
 *   - If no commit is found that could plausibly have resolved the issue,
 *     block the close and require a commit first.
 *
 * Heuristic is intentionally lenient: we accept either an explicit issue ID
 * match in the commit message, OR any new commit on the current branch since
 * the issue was claimed. The goal is to catch bald-faced "close without doing
 * anything" cheats, not to enforce perfect commit discipline.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const BD_CLOSE_PATTERN = /\bbd\s+close\s+([A-Za-z0-9]+-[A-Za-z0-9]+)/;
const BD_UPDATE_CLOSE_PATTERN = /\bbd\s+update\s+([A-Za-z0-9]+-[A-Za-z0-9]+)\s+--status\s*=?\s*closed/;

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event) => {
    if (event.toolName !== "bash") return undefined;

    const cmd = (event.input as { command?: string }).command ?? "";
    const match = cmd.match(BD_CLOSE_PATTERN) ?? cmd.match(BD_UPDATE_CLOSE_PATTERN);
    if (!match) return undefined;

    const issueId = match[1];

    // Check if HEAD commit references this issue
    const { stdout: msgOut, code: msgCode } = await pi.exec("git", ["log", "-20", "--pretty=%s%n%b"]);
    if (msgCode !== 0) {
      // Not a git repo or git failed. Let the close proceed — don't false-positive
      // on non-git directories.
      return undefined;
    }

    const hasIssueRef = msgOut.includes(issueId);
    if (hasIssueRef) return undefined;

    // No explicit reference. Check if there's ANY new commit since the last
    // merge-base with main/master (best-effort; if branch discovery fails, fall
    // back to allowing the close — this is a guardrail, not a jail).
    const { stdout: branchOut } = await pi.exec("git", ["rev-parse", "--abbrev-ref", "HEAD"]);
    const currentBranch = branchOut.trim();
    if (!currentBranch || currentBranch === "HEAD") return undefined;

    // Try main, then master
    for (const base of ["main", "master"]) {
      const { stdout: countOut, code: countCode } = await pi.exec("git", [
        "rev-list",
        "--count",
        `${base}..HEAD`,
      ]);
      if (countCode === 0) {
        const newCommits = parseInt(countOut.trim() || "0", 10);
        if (newCommits > 0) return undefined; // at least some work landed on this branch
        break;
      }
    }

    return {
      block: true,
      reason: `Cannot close ${issueId}: no commit on this branch references this issue, and no new commits exist since branching from main/master. Make the fix and commit it (e.g. \`git commit -m "fix: ... ${issueId}"\`) before closing.`,
    };
  });
}
