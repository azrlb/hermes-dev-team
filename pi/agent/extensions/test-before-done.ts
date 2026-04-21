/**
 * Test Before Done
 *
 * Prevents the "tests passed by not running" failure seen in Hermes dev-team
 * evals (T2 Eval-1: vi.mock hoisting error → test file failed to load → 0
 * tests executed → model claimed PASS).
 *
 * Strategy:
 *   - Track per-session whether a test command has been executed and whether
 *     its output contains evidence of actual test assertions running.
 *   - When the model attempts bash commands that indicate story completion
 *     (`bd close`, `bd update --status=closed`, `git commit` with fix: prefix),
 *     require prior verified test execution.
 *   - Block with a clear reason if no evidence of tests actually running.
 *
 * Detection patterns:
 *   - test ran: bash command contains 'vitest run' | 'vitest --run' |
 *     'jest' | 'pytest' | 'npm test' | 'npm run test' (and exit code 0)
 *   - tests actually executed: stdout/stderr contains test count markers like
 *     'Tests:  N passed' | '✓' | 'PASS' with a file path | ' passing'
 *   - suspicious (no tests ran): 'Tests: no tests' | '0 passed' |
 *     'no test files' | 'failed to collect' | 'failed to load'
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const TEST_CMD_PATTERNS = [
  /\bvitest\s+(run|--run)\b/i,
  /\bjest\b(?!\.fn|\.mock|\.requireActual)/i,
  /\bpytest\b/i,
  /\bnpm\s+(test|run\s+test)\b/i,
  /\bnpx\s+vitest\s+run\b/i,
];

const SUSPICIOUS_OUTPUT_PATTERNS = [
  /\btests?\s*:\s*no tests?\b/i,
  /\bno test files? found\b/i,
  /\b0 passed\b/i,
  /\bfailed to collect\b/i,
  /\bfailed to load\b/i,
  /\b0 tests? executed\b/i,
];

const VALID_OUTPUT_PATTERNS = [
  /\btests?\s*:\s*\d+ passed\b/i,
  /\b\d+ passing\b/i,
  /PASS\s+[^\s]+\.(test|spec)\.[tj]sx?\b/,
  /✓\s+\d+/,
];

const COMPLETION_CMD_PATTERNS = [
  /\bbd\s+close\s+/i,
  /\bbd\s+update\s+[^\s]+\s+--status\s*=?\s*closed\b/i,
  /\bgit\s+commit\b.*fix:/i,
];

type SessionState = {
  testRunSeen: boolean;
  testVerifiedGreen: boolean;
};

const sessionState = new Map<string, SessionState>();

function getOrCreateState(sessionId: string): SessionState {
  let state = sessionState.get(sessionId);
  if (!state) {
    state = { testRunSeen: false, testVerifiedGreen: false };
    sessionState.set(sessionId, state);
  }
  return state;
}

export default function (pi: ExtensionAPI) {
  // Track test runs: inspect tool_result for bash commands that were test runs
  pi.on("tool_result", async (event, ctx) => {
    if (event.toolName !== "bash") return undefined;

    const cmd = (event.input as { command?: string }).command ?? "";
    const isTestCmd = TEST_CMD_PATTERNS.some((re) => re.test(cmd));
    if (!isTestCmd) return undefined;

    const state = getOrCreateState(ctx.sessionId ?? "default");
    state.testRunSeen = true;

    // Gather output text
    const result = event.result;
    let output = "";
    if (result && Array.isArray(result.content)) {
      for (const c of result.content) {
        if (c.type === "text" && typeof c.text === "string") output += c.text;
      }
    }

    const suspicious = SUSPICIOUS_OUTPUT_PATTERNS.some((re) => re.test(output));
    const valid = VALID_OUTPUT_PATTERNS.some((re) => re.test(output));

    state.testVerifiedGreen = valid && !suspicious;

    return undefined;
  });

  // Block completion commands if tests weren't verified
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "bash") return undefined;

    const cmd = (event.input as { command?: string }).command ?? "";
    const isCompletion = COMPLETION_CMD_PATTERNS.some((re) => re.test(cmd));
    if (!isCompletion) return undefined;

    const state = getOrCreateState(ctx.sessionId ?? "default");

    if (!state.testRunSeen) {
      return {
        block: true,
        reason: "Cannot run this completion command — no test command has been executed in this session. Run the project's test command first (e.g. `npx vitest run <test_file>` or `npm test`).",
      };
    }

    if (!state.testVerifiedGreen) {
      return {
        block: true,
        reason: "Cannot run this completion command — the most recent test run did not show evidence of tests actually passing (output contained '0 tests' or 'failed to load' or similar). Fix the tests so they load and run, then verify green.",
      };
    }

    return undefined;
  });
}
