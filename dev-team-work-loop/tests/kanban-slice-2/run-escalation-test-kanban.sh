#!/usr/bin/env bash
# Slice 2 acceptance fixture for the kanban migration.
#
# Plan: ~/.claude/plans/okay-lets-plan-theintergration-rustling-hedgehog.md §Slice 2.
#
# What this proves (the load-bearing claim of Slice 2):
#   The dispatcher + a reactive escalation loop can take a [story-impl]
#   task that fails twice, escalate via a [story-deep-research] task,
#   and converge to a passing impl on attempt 3 — without any human
#   unblocking. End-to-end completion through verify + land follows
#   Slice 1's proven path.
#
# Strategy:
#   - Same fixture project as Slice 1 (vitest TypeScript, add() story).
#   - Same Pi shim + Hermes worker shim (the shim already supports
#     HERMES_SHIM_FAIL_FIRST counter behavior — Slice 2 sets =2).
#   - Decompose into 5 tasks (Slice 1 graph: stack-detect, health-check,
#     impl, verify, land).
#   - Set HERMES_SHIM_FAIL_FIRST=2 so the impl shim blocks on its
#     first two spawns.
#   - Add a REACTIVE LOOP alongside the dispatch polling loop:
#       * Each tick, find blocked [story-impl] tasks in our tenant.
#       * prior_runs == 1 → unblock immediately (immediate retry,
#                           "different approach" attempt 2).
#       * prior_runs == 2 → create a [story-deep-research] task
#                           (parentless). When it completes, unblock
#                           impl (so the dispatcher respawns it for
#                           attempt 3, which now has prior_runs == 2
#                           and the shim succeeds).
#   - Slice 1 verify + land flow runs unchanged afterward.
#
# After completion, run ./assert-escalation-test-kanban.sh to verify.

set -uo pipefail

ROOT=/tmp/hermes-kanban-slice2
rm -rf "$ROOT"
mkdir -p "$ROOT"/{src/__tests__,docs/stories,bin,.hermes/sessions}
cd "$ROOT"

# ─── Project scaffold ─────────────────────────────────────────────────────────

cat > package.json <<'JSON'
{
  "name": "hermes-kanban-slice2",
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
# KanbanSlice2 — Agent Context

Slice 2 acceptance fixture for the Hermes Kanban dev-team migration.

The Pi shim succeeds on its first invocation, but the OUTER kanban
worker (pi-dispatcher) is configured to block its first 2 spawns
(HERMES_SHIM_FAIL_FIRST=2). The reactive escalation loop in the runner
detects the block, escalates to a deep-research task on the second
block, and unblocks the impl task to retry. On the third spawn the
shim succeeds.

## Architecture
- TypeScript (ESM), vitest, beads (prefix KanbanSlice2).

## Conventions
- Source in `src/`, tests in `src/__tests__/`.
- NEVER modify test files.
MD

cat > docs/stories/1.1.add-two.md <<'MD'
---
id: KanbanSlice2-1
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

# ─── Pi shim — same as Slice 1 (writes correct impl on first call) ────────────

cat > bin/pi <<'SH'
#!/usr/bin/env bash
LOGDIR=/tmp/hermes-kanban-slice2/.hermes
mkdir -p "$LOGDIR" /tmp/hermes-kanban-slice2/.hermes/sessions
echo "$(date -Iseconds) ARGS: $*" >> "$LOGDIR/pi-shim.log"

# Detect Quinn-review invocation and print APPROVED.
is_quinn=false
for arg in "$@"; do
  case "$arg" in
    --no-tools|ollama-quinn|deepseek-r1:32b) is_quinn=true ;;
  esac
done
if [[ "$is_quinn" == "true" ]]; then
  echo "APPROVED — diff is on-topic and correct"
  exit 0
fi

WORKTREE_DIR="$(pwd)"
mkdir -p "$WORKTREE_DIR/src"
cat > "$WORKTREE_DIR/src/add.ts" <<'TS'
export function add(a: number, b: number): number {
  return a + b;
}
TS

cat <<EOF
[pi-shim] Wrote src/add.ts (correct implementation, attempt 3 with research context)
[pi-shim] PASS
EOF
exit 0
SH
chmod +x bin/pi

# ─── bin/hermes shim (Slice 2 reuses Slice 1's, supports SHIM_FAIL_FIRST) ─────
SHIM_SRC=/media/bob/C/AI_Projects/hermes-dev-team/dev-team-work-loop/tests/kanban-slice-1/shims/hermes-kanban-shim.sh
cp "$SHIM_SRC" bin/hermes
chmod +x bin/hermes

# ─── .gitignore for runtime artifacts ─────────────────────────────────────────
cat > .gitignore <<'GIT'
node_modules/
.hermes/
GIT

# ─── Install + git + beads ────────────────────────────────────────────────────

echo "[setup] npm install..."
npm install --silent

git init -q
git -c user.email=test@test -c user.name=test add -A
git -c user.email=test@test -c user.name=test commit -q -m "initial fixture"

# Bare remote so the lander's `git pull --rebase && git push` actually works.
BARE_REMOTE=/tmp/hermes-kanban-slice2-remote.git
rm -rf "$BARE_REMOTE"
git init --bare -q "$BARE_REMOTE"
git remote add origin "$BARE_REMOTE"
git -c user.email=test@test -c user.name=test push -q -u origin HEAD:refs/heads/main
git branch --set-upstream-to=origin/main main 2>/dev/null || \
  git branch --set-upstream-to=origin/main master 2>/dev/null || true

echo "[setup] bd init..."
bd init --prefix KanbanSlice2 >/dev/null 2>&1 || true

BD_OUT=$(bd create "Sum two numbers" \
  --type feature --priority 0 \
  -d "story_file=docs/stories/1.1.add-two.md
test_file=src/__tests__/add.test.ts
budget_usd=2.00" 2>&1)
echo "$BD_OUT"
STORY_ID=$(echo "$BD_OUT" | grep -oE 'KanbanSlice2-[a-z0-9]+' | head -1)
if [[ -z "$STORY_ID" ]]; then
  STORY_ID=$(bd list --json 2>/dev/null | grep -oE '"id"[[:space:]]*:[[:space:]]*"KanbanSlice2-[a-z0-9]+"' | head -1 | grep -oE 'KanbanSlice2-[a-z0-9]+')
fi
echo "$STORY_ID" > .hermes/story-id.txt
echo "[setup] story id = $STORY_ID"

# ─── Story-root + decomposition (same pattern as Slice 1) ─────────────────────

# Make our shims available to spawned workers.
export PATH="$ROOT/bin:$HOME/.local/bin:$PATH"
export STORY_ID

# Slice 2 KEY KNOB: tell the impl shim to block its first 2 spawns.
# The reactive escalation loop below handles the unblock + deep-research
# creation. On the 3rd spawn the shim sees prior_runs == 2 and succeeds.
export HERMES_SHIM_FAIL_FIRST=2

export HERMES_TENANT=KanbanSlice2
HELPER=/media/bob/C/AI_Projects/hermes-dev-team/scripts/kanban-decompose-story.sh

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

echo "[run] running decomposer helper directly (bypassing LLM orchestrator for Slice 2)"
IDS_JSON=$(bash "$HELPER" \
  "$STORY_ID" \
  "${ROOT}/docs/stories/1.1.add-two.md" \
  "${ROOT}/src/__tests__/add.test.ts" \
  "${ROOT}" \
  "story-${STORY_ID}" \
  "npx vitest run")
echo "$IDS_JSON" | tee .hermes/decomposer-output.json

hermes kanban complete "$ROOT_TASK_ID" \
  --summary "decomposed via deterministic helper (Slice 2 bypass)" \
  --metadata "{\"task_graph\":$IDS_JSON}" >/dev/null 2>&1 || true
echo "[run] story-root task $ROOT_TASK_ID marked done"

IMPL_TASK_ID=$(echo "$IDS_JSON" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
print(d.get('story_impl', ''))
")
echo "[run] tracking [story-impl] task id = $IMPL_TASK_ID for reactive escalation"

# ─── Reactive escalation function ─────────────────────────────────────────────
# Called once per tick. Stateless: re-evaluates the impl task's status and
# the existence of any [story-deep-research] task each time. Idempotent.

react_to_blocked_impl() {
  local impl_id="$1"
  local impl_json
  impl_json=$(hermes kanban show "$impl_id" --json 2>/dev/null) || return 0

  local impl_status
  impl_status=$(echo "$impl_json" | python3 -c "
import json, sys
try: print(json.load(sys.stdin)['task'].get('status','unknown'))
except: print('unknown')
")
  [[ "$impl_status" == "blocked" ]] || return 0

  local prior_runs
  prior_runs=$(echo "$impl_json" | python3 -c "
import json, sys
try: print(len(json.load(sys.stdin).get('runs',[])))
except: print(0)
")

  if [[ "$prior_runs" == "1" ]]; then
    # First block — straightforward retry with a different approach.
    echo "[react] impl blocked at attempt 1 — unblocking for retry attempt 2"
    hermes kanban unblock "$impl_id" 2>&1 | tail -1
    return 0
  fi

  if [[ "$prior_runs" -ge "2" ]]; then
    # Second block — escalate to deep research. Find or create a
    # [story-deep-research] task. When it completes, unblock impl.
    local research_id
    research_id=$(hermes kanban list --tenant KanbanSlice2 --json 2>/dev/null \
      | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    for t in d:
        if 'deep-research' in t.get('title','').lower():
            print(t['id']); break
except: pass
")

    if [[ -z "$research_id" ]]; then
      echo "[react] impl blocked at attempt 2 — creating [story-deep-research]"
      research_id=$(hermes kanban create "deep-research for ${STORY_ID}" \
        --assignee dev-orchestrator \
        --tenant "$HERMES_TENANT" \
        --workspace "dir:${ROOT}" \
        --skill dev-team/deep-research-bridge \
        --body "Deep research escalation for impl task ${impl_id}.

bd_id=${STORY_ID}
worktree=${ROOT}
test_file=${ROOT}/src/__tests__/add.test.ts
parent_impl_task=${impl_id}

Wraps scripts/escalator.py: walks the multi-tier escalation chain
(different approaches, web research, deepseek-r1) and emits research
findings for the next impl attempt." \
        --max-runtime 30m \
        --json | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
      echo "$research_id" > .hermes/deep-research-id.txt
      echo "[react] created deep-research task $research_id"
      return 0
    fi

    # Research task exists — check its status.
    local research_status
    research_status=$(hermes kanban show "$research_id" --json 2>/dev/null \
      | python3 -c "
import json, sys
try: print(json.load(sys.stdin)['task'].get('status','unknown'))
except: print('unknown')
")
    if [[ "$research_status" == "done" ]]; then
      echo "[react] deep-research $research_id completed — unblocking impl for attempt 3"
      hermes kanban unblock "$impl_id" 2>&1 | tail -1
    else
      echo "[react] deep-research $research_id status=$research_status — waiting"
    fi
  fi
}

# ─── Wait for the dispatcher to walk the graph (with reactive escalation) ─────

echo "[run] gateway is stopped — explicitly ticking dispatcher each cycle"
echo "[run] reactive escalation loop active (HERMES_SHIM_FAIL_FIRST=$HERMES_SHIM_FAIL_FIRST)"
echo "[run] waiting for dispatcher to drain (max 15 minutes — shims should be fast)"
deadline=$(( $(date +%s) + 900 ))
while [[ $(date +%s) -lt $deadline ]]; do
  hermes kanban dispatch 2>&1 | tee -a .hermes/dispatch.log >/dev/null || true

  # Reactive layer: react to blocked impl tasks.
  react_to_blocked_impl "$IMPL_TASK_ID"

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
  graph=$(hermes kanban list --tenant KanbanSlice2 --json 2>/dev/null | python3 -c "
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
  sleep 15
done

echo "[run] dispatcher dragged to completion or timeout. Now run ./assert-escalation-test-kanban.sh"
echo "[run] story id was: $STORY_ID"
echo "[run] root task id was: $ROOT_TASK_ID"
echo "[run] impl task id was: $IMPL_TASK_ID"
