#!/usr/bin/env bash
# Hermes work-loop escalation regression test (v2 — forced-stall fixture).
#
# Strategy:
#   - Shim `pi` itself so EVERY pi invocation reports FAIL with the same error
#     count (guaranteed stall, no matter what Hermes prompts it with).
#   - Shim `claude` so `claude -p` records the call AND writes the correct
#     implementation (the only thing that can land the story).
#   - Run `dev-team/work-loop` directly with a strict prompt forbidding inline
#     coding by the orchestrator — it MUST go through Step 7 (pi -q).
#   - Capture the real bd-assigned story ID for the assertion script.
set -euo pipefail

ROOT=/tmp/hermes-escalation-test
rm -rf "$ROOT"
mkdir -p "$ROOT"/{src/__tests__,docs/stories,bin,.hermes/sessions}
cd "$ROOT"

# ---- package.json + vitest ---------------------------------------------------
cat > package.json <<'JSON'
{
  "name": "hermes-escalation-test",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "vitest run",
    "test:single": "vitest run"
  },
  "devDependencies": {
    "vitest": "^1.6.0",
    "typescript": "^5.4.0"
  }
}
JSON

cat > tsconfig.json <<'JSON'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*"]
}
JSON

cat > AGENTS.md <<'MD'
# EscTest — Agent Context

Regression fixture for Hermes work-loop escalation. Pi is shimmed to always
fail; `claude -p` is shimmed to apply the real fix. The work-loop must:
  1. Dispatch Pi via Step 7 (Pi will FAIL).
  2. After 2 stalled retries, escalate to `claude -p` per Step 8.
  3. Run the Verify & Resume block (re-run the test file).
  4. Land the story (commit + bd close).

## Architecture
- TypeScript (ESM), vitest, beads (prefix EscTest).

## Conventions
- Source in `src/`, tests in `src/__tests__/`.
- NEVER modify test files.
- Hermes orchestrator MUST NOT write source files itself — all code goes
  through `pi -q` per work-loop Step 7.
MD

cat > docs/stories/1.1.tricky-parser.md <<'MD'
---
id: EscTest-1
title: Tricky parser
status: ready
test_file: src/__tests__/tricky-parser.test.ts
---

# Story 1.1 — Tricky parser

Implement `parse(s: string): number | null` in `src/tricky-parser.ts` to make
all tests in `src/__tests__/tricky-parser.test.ts` pass.
MD

cat > src/__tests__/tricky-parser.test.ts <<'TS'
import { describe, it, expect } from "vitest";
import { parse } from "../tricky-parser";

describe("tricky parser", () => {
  it("returns null for empty input", () => {
    expect(parse("")).toBeNull();
  });
  it("parses integers", () => {
    expect(parse("42")).toBe(42);
  });
  it("treats the literal 'NaN' as 0", () => {
    expect(parse("NaN")).toBe(0);
  });
});
TS

# ---- Pi shim — always FAILS, always reports the same 1 failing test ----------
# This guarantees the "same test count for 2 retries" stall detector fires.
cat > bin/pi <<'SH'
#!/usr/bin/env bash
LOGDIR=/tmp/hermes-escalation-test/.hermes
mkdir -p "$LOGDIR" /tmp/hermes-escalation-test/.hermes/sessions
echo "$(date -Iseconds) ARGS: $*" >> "$LOGDIR/pi-shim.log"

# Honor --session by touching the session file (proves Step 7 passed it).
SESSION=""
for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == "--session" ]]; then
    j=$((i+1)); SESSION="${!j}"; break
  fi
done
if [[ -n "$SESSION" ]]; then
  mkdir -p "$(dirname "$SESSION")"
  echo "{\"shim\":true,\"ts\":\"$(date -Iseconds)\"}" >> "$SESSION"
fi

# Always emit the same failure summary so the stall detector trips.
cat <<EOF
[pi-shim] Reading AGENTS.md...
[pi-shim] Running vitest...
FAIL  src/__tests__/tricky-parser.test.ts
  × tricky parser > treats the literal 'NaN' as 0
    Expected: 0
    Received: NaN

Test Files  1 failed (1)
     Tests  1 failed | 2 passed (3)

[pi-shim] Could not determine why "NaN" should equal 0. Story does not specify.
[pi-shim] FAIL
EOF

# Write a result marker the work-loop may read.
STORY_ID="${STORY_ID:-unknown}"
echo "FAIL" > "/tmp/hermes-escalation-test/${STORY_ID}.result" 2>/dev/null || true
exit 1
SH
chmod +x bin/pi

# ---- Claude shim — `claude -p` writes the correct implementation -------------
cat > bin/claude <<'SH'
#!/usr/bin/env bash
LOGDIR=/tmp/hermes-escalation-test/.hermes
mkdir -p "$LOGDIR"
echo "$(date -Iseconds) ARGS: $*" >> "$LOGDIR/claude-shim.log"
if [[ "${1:-}" == "-p" ]]; then
  cat > /tmp/hermes-escalation-test/src/tricky-parser.ts <<'TS'
export function parse(s: string): number | null {
  if (s === "") return null;
  if (s === "NaN") return 0;
  const n = Number(s);
  return Number.isNaN(n) ? null : n;
}
TS
  echo "[claude-shim] applied tricky-parser fix via claude -p"
  exit 0
fi
exit 0
SH
chmod +x bin/claude

# ---- Install + git + beads ---------------------------------------------------
echo "[setup] npm install..."
npm install --silent

git init -q
git add -A
git -c user.email=test@test -c user.name=test commit -q -m "initial fixture"

echo "[setup] bd init..."
bd init --prefix EscTest >/dev/null 2>&1 || true

# Create story and capture the real ID.
BD_OUT=$(bd create "Tricky parser story" \
  --type feature --priority 0 \
  -d "story_file=docs/stories/1.1.tricky-parser.md
test_file=src/__tests__/tricky-parser.test.ts
budget_usd=2.00" 2>&1)
echo "$BD_OUT"
STORY_ID=$(echo "$BD_OUT" | grep -oE 'EscTest-[a-z0-9]+' | head -1)
if [[ -z "$STORY_ID" ]]; then
  STORY_ID=$(bd list --json 2>/dev/null | grep -oE '"id"[[:space:]]*:[[:space:]]*"EscTest-[a-z0-9]+"' | head -1 | grep -oE 'EscTest-[a-z0-9]+')
fi
echo "$STORY_ID" > .hermes/story-id.txt
echo "[setup] story id = $STORY_ID"

# ---- Run work-loop with shimmed PATH -----------------------------------------
export PATH="$ROOT/bin:$HOME/.local/bin:$PATH"
export STORY_ID

PROMPT="Run dev-team/work-loop on the single ready story (${STORY_ID}).

CRITICAL ORCHESTRATOR RULES:
- You are the orchestrator. You MUST NOT write source files yourself.
- All implementation code MUST go through Step 7: 'pi -q ... --session .hermes/sessions/${STORY_ID}.jsonl --yolo --agent tdd-coder'.
- Pi will FAIL — that is expected for this fixture.
- After Pi stalls (same failure count for 2 retries), follow Step 8 escalation chain.
- When you reach the 'claude -p --model claude-opus-4-6' step, run it as a shell command.
- After claude -p returns, you MUST run the Verify & Resume block: re-run vitest on src/__tests__/tricky-parser.test.ts and branch on the result.
- On PASS, complete Step 9 Land the Plane (commit + bd close).
- Story id is ${STORY_ID}. Run bd ready --json first."

echo "[run] launching work-loop (PATH first entry: $(echo "$PATH" | cut -d: -f1))"
hermes chat -s dev-team/work-loop --yolo -q "$PROMPT" 2>&1 | tee run.log

echo "[run] complete. Story id was: $STORY_ID"
echo "[run] Now run ./assert-escalation-test.sh"
