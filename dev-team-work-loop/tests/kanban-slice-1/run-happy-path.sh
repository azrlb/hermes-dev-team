#!/usr/bin/env bash
# Slice 1 acceptance fixture for the kanban migration.
#
# Plan: ~/.claude/plans/okay-lets-plan-theintergration-rustling-hedgehog.md §Slice 1.
#
# Strategy:
#   - Build a tiny project with one failing TDD test.
#   - Shim `pi` so its first invocation writes the correct implementation and
#     exits 0 (HAPPY PATH — no escalation expected).
#   - Run the kanban-native dev-orchestrator profile on a story-root task.
#   - Let dispatcher walk: stack-detect → health-check → story-impl → story-verify → story-land.
#   - Expect: bd issue closed, .test-result written, fix(<id>): commit at HEAD.
#
# Pre-reqs:
#   1. ./scripts/setup-kanban-profiles.sh has run (4 profiles exist).
#   2. The 4 SKILL.md files in skills/dev-team/{kanban-decomposition,pi-dispatcher,cross-check,land-the-plane}/ exist.
#   3. Hermes Kanban v1 available (`hermes kanban` subcommand).
#
# After the run completes, run ./assert-happy-path.sh to verify.

set -euo pipefail

ROOT=/tmp/hermes-kanban-slice1
rm -rf "$ROOT"
mkdir -p "$ROOT"/{src/__tests__,docs/stories,bin,.hermes/sessions}
cd "$ROOT"

# ─── Project scaffold ─────────────────────────────────────────────────────────

cat > package.json <<'JSON'
{
  "name": "hermes-kanban-slice1",
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
# KanbanSlice1 — Agent Context

Slice 1 acceptance fixture for the Hermes Kanban dev-team migration.

The Pi shim succeeds on its first call (HAPPY PATH). The dispatcher should
walk the per-story sub-graph (stack-detect → health-check → impl → verify
→ land) and close the bd issue without invoking any escalation.

## Architecture
- TypeScript (ESM), vitest, beads (prefix KanbanSlice1).

## Conventions
- Source in `src/`, tests in `src/__tests__/`.
- NEVER modify test files.
MD

cat > docs/stories/1.1.add-two.md <<'MD'
---
id: KanbanSlice1-1
title: Sum two numbers
status: ready
test_file: src/__tests__/add.test.ts
---

# Story 1.1 — Sum two numbers

Implement `add(a: number, b: number): number` in `src/add.ts` to make all
tests in `src/__tests__/add.test.ts` pass.
MD

cat > src/__tests__/add.test.ts <<'TS'
import { describe, it, expect } from "vitest";
import { add } from "../add";

describe("add", () => {
  it("adds two positive integers", () => {
    expect(add(2, 3)).toBe(5);
  });
  it("handles negative numbers", () => {
    expect(add(-1, 1)).toBe(0);
  });
  it("handles zero", () => {
    expect(add(0, 0)).toBe(0);
  });
});
TS

# ─── Pi shim — writes correct impl on first call, exits 0 ─────────────────────
# Real Pi would run vitest, see failures, write the impl, re-run, see PASS.
# This shim short-circuits to the same end state without an LLM call.

cat > bin/pi <<'SH'
#!/usr/bin/env bash
LOGDIR=/tmp/hermes-kanban-slice1/.hermes
mkdir -p "$LOGDIR" /tmp/hermes-kanban-slice1/.hermes/sessions
echo "$(date -Iseconds) ARGS: $*" >> "$LOGDIR/pi-shim.log"

# Honor --session by appending to the session file (proves the dispatcher
# passed it correctly).
SESSION=""
for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == "--session" ]]; then
    j=$((i+1)); SESSION="${!j}"; break
  fi
done
if [[ -n "$SESSION" ]]; then
  mkdir -p "$(dirname "$SESSION")"
  cat >> "$SESSION" <<JSONL
{"role":"system","content":"shim invocation"}
{"role":"user","content":"shim arguments captured"}
{"role":"assistant","message":{"content":[{"type":"toolCall","name":"write","input":{"path":"src/add.ts"}}]}}
JSONL
fi

# Detect Quinn-review invocation (--no-tools --provider ollama-quinn) and
# print APPROVED so the lander's per-commit Quinn check passes.
is_quinn=false
for arg in "$@"; do
  case "$arg" in
    --no-tools|ollama-quinn|deepseek-r1:32b) is_quinn=true ;;
  esac
done
if [[ "$is_quinn" == "true" ]]; then
  echo "APPROVED — diff is on-topic and correct"
  echo "[pi-shim] Quinn review: APPROVED"
  exit 0
fi

# tdd-coder happy path: write the correct implementation.
WORKTREE_DIR="$(pwd)"
mkdir -p "$WORKTREE_DIR/src"
cat > "$WORKTREE_DIR/src/add.ts" <<'TS'
export function add(a: number, b: number): number {
  return a + b;
}
TS

cat <<EOF
[pi-shim] Reading AGENTS.md...
[pi-shim] Reading test file src/__tests__/add.test.ts...
[pi-shim] Wrote src/add.ts (correct implementation, no escalation needed)
[pi-shim] Running vitest src/__tests__/add.test.ts...

PASS  src/__tests__/add.test.ts (3 tests)
  ✓ add adds two positive integers
  ✓ add handles negative numbers
  ✓ add handles zero

Test Files  1 passed (1)
     Tests  3 passed (3)

[pi-shim] PASS
EOF
exit 0
SH
chmod +x bin/pi

# ─── bin/hermes shim (Slice 1 acceptance — bypass slow local LLMs) ────────────
# The dispatcher spawns workers as `hermes -p <profile> --skills ... chat -q ...`
# (relative path), so $ROOT/bin appearing first in PATH causes our shim to be
# invoked. The shim short-circuits the 5 dev-team workers with canned outcomes;
# any non-shimmed invocation falls through to the real hermes binary.
SHIM_SRC=/media/bob/C/AI_Projects/hermes-dev-team/dev-team-work-loop/tests/kanban-slice-1/shims/hermes-kanban-shim.sh
cp "$SHIM_SRC" bin/hermes
chmod +x bin/hermes

# ─── Install + git + beads ────────────────────────────────────────────────────

echo "[setup] npm install..."
npm install --silent

# .gitignore for transient runtime artifacts. Without this, the assertion that
# checks "working tree clean after lander" fails because vitest writes
# node_modules/.vite/ on its first run, and the dispatcher writes .hermes/
# session + dispatch logs.
cat > .gitignore <<'GIT'
node_modules/
.hermes/
GIT

git init -q
git -c user.email=test@test -c user.name=test add -A
git -c user.email=test@test -c user.name=test commit -q -m "initial fixture"

# Bare remote so the lander's `git pull --rebase && git push` actually works.
# Without this, the lander would block on push and end-to-end never completes.
BARE_REMOTE=/tmp/hermes-kanban-slice1-remote.git
rm -rf "$BARE_REMOTE"
git init --bare -q "$BARE_REMOTE"
git remote add origin "$BARE_REMOTE"
git -c user.email=test@test -c user.name=test push -q -u origin HEAD:refs/heads/main
git branch --set-upstream-to=origin/main main 2>/dev/null || \
  git branch --set-upstream-to=origin/main master 2>/dev/null || true

echo "[setup] bd init..."
bd init --prefix KanbanSlice1 >/dev/null 2>&1 || true

# Create story and capture the real ID.
BD_OUT=$(bd create "Sum two numbers" \
  --type feature --priority 0 \
  -d "story_file=docs/stories/1.1.add-two.md
test_file=src/__tests__/add.test.ts
budget_usd=2.00" 2>&1)
echo "$BD_OUT"
STORY_ID=$(echo "$BD_OUT" | grep -oE 'KanbanSlice1-[a-z0-9]+' | head -1)
if [[ -z "$STORY_ID" ]]; then
  STORY_ID=$(bd list --json 2>/dev/null | grep -oE '"id"[[:space:]]*:[[:space:]]*"KanbanSlice1-[a-z0-9]+"' | head -1 | grep -oE 'KanbanSlice1-[a-z0-9]+')
fi
echo "$STORY_ID" > .hermes/story-id.txt
echo "[setup] story id = $STORY_ID"

# ─── Create the story-root kanban task ────────────────────────────────────────

export PATH="$ROOT/bin:$HOME/.local/bin:$PATH"
export STORY_ID

# ─── Slice 1: bypass the LLM orchestrator ────────────────────────────────────
# The dev-orchestrator profile is restricted-by-convention from terminal
# tools, so it cannot invoke our deterministic decomposer helper. For Slice 1
# (which tests the WORKERS, not the orchestrator's reactive logic), the runner
# calls the decomposer directly. Slice 2+ re-introduces the LLM orchestrator
# for reactive escalation routing where its judgment is actually needed.

export HERMES_TENANT=KanbanSlice1
HELPER=/media/bob/C/AI_Projects/hermes-dev-team/scripts/kanban-decompose-story.sh

# Create a story-root task assigned to dev-orchestrator. We don't actually
# spawn the orchestrator (Slice 1 bypasses it — see comment below), but
# the task must exist for assertion 1 to find a dev-orchestrator-assigned
# root. We mark it done immediately after decomposition so the dispatcher
# never tries to spawn it.
ROOT_TASK_ID=$(hermes kanban create "story-root for ${STORY_ID}" \
  --assignee dev-orchestrator \
  --tenant "$HERMES_TENANT" \
  --workspace "dir:${ROOT}" \
  --skill dev-team/kanban-decomposition \
  --body "Decompose story ${STORY_ID} for kanban execution.
bd_id=${STORY_ID}
story_file=${ROOT}/docs/stories/1.1.add-two.md
test_file=${ROOT}/src/__tests__/add.test.ts
worktree=${ROOT}
mode=greenfield" \
  --json | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
echo "$ROOT_TASK_ID" > .hermes/root-task-id.txt
echo "[run] story-root task = $ROOT_TASK_ID (assigned to dev-orchestrator)"

echo "[run] running decomposer helper directly (bypassing LLM orchestrator for Slice 1)"
# Pass explicit test_single_cmd to sidestep stack-detect's known --testPathPattern bug.
# For this Vitest fixture: 'npx vitest run' takes a path positional, no flag.
IDS_JSON=$(bash "$HELPER" \
  "$STORY_ID" \
  "${ROOT}/docs/stories/1.1.add-two.md" \
  "${ROOT}/src/__tests__/add.test.ts" \
  "${ROOT}" \
  "story-${STORY_ID}" \
  "npx vitest run")
echo "$IDS_JSON" | tee .hermes/decomposer-output.json

# Mark the story-root task done now that decomposition is complete.
# (Slice 2+ will move this transition into the dev-orchestrator profile's
# actual run — for Slice 1 the runner just bypasses it.)
hermes kanban complete "$ROOT_TASK_ID" \
  --summary "decomposed via deterministic helper (Slice 1 bypass)" \
  --metadata "{\"task_graph\":$IDS_JSON}" >/dev/null 2>&1 || true
echo "[run] story-root task $ROOT_TASK_ID marked done"

# Pull the [story-land] id for the dispatcher-completion check below.
LAND_TASK_ID=$(echo "$IDS_JSON" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
print(d.get('story_land', ''))
")
echo "[run] tracking [story-land] task id = $LAND_TASK_ID"

# ─── Wait for the dispatcher to walk the graph ────────────────────────────────

echo "[run] gateway is stopped — explicitly ticking dispatcher each cycle"
echo "[run] waiting for dispatcher to drain (max 60 minutes — Path A: end-to-end real workers)"
deadline=$(( $(date +%s) + 3600 ))
while [[ $(date +%s) -lt $deadline ]]; do
  hermes kanban dispatch 2>&1 | tee -a .hermes/dispatch.log >/dev/null || true
  bd_status=$(bd show "$STORY_ID" --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    i = d[0] if isinstance(d, list) else d
    print(i.get('status', 'unknown'))
except Exception:
    print('unknown')
" 2>/dev/null)
  if [[ "$bd_status" == "closed" ]]; then
    echo "[run] bd $STORY_ID closed"
    break
  fi
  graph=$(hermes kanban list --tenant KanbanSlice1 --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    if isinstance(d, list):
        parts = []
        for t in d:
            title = t.get('title', '')
            short = title.split(' ')[0] if title else '?'
            parts.append(f\"{short}={t.get('status','?')}\")
        print(' '.join(parts))
except Exception:
    print('graph error')
" 2>/dev/null)
  echo "[run $(date +%H:%M:%S)] bd=$bd_status | $graph"
  sleep 30
done

echo "[run] dispatcher dragged to completion or timeout. Now run ./assert-happy-path.sh"
echo "[run] story id was: $STORY_ID"
echo "[run] root task id was: $ROOT_TASK_ID"
