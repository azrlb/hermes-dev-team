#!/usr/bin/env bash
# Slice 2.5 acceptance fixture — parametrized by BLOCKER_TYPE.
#
# Plan: ~/.claude/plans/okay-lets-plan-theintergration-rustling-hedgehog.md
#       §"Per-blocker-type branching".
#
# What this proves:
#   For each of the 4 non-HARD_PROBLEM blocker types, the reactive watcher
#   reads the block reason, classifies the failure, and creates the right
#   kind of branch task (e.g. story-rewrite for STORY_AMBIGUITY, infra-fix
#   for INFRA). The branch shim emits a canned outcome. The watcher then
#   unblocks impl, which converges on the next attempt.
#
#   HARD_PROBLEM is already proven in Slice 2 (deep-research-bridge path).
#   This fixture covers the other 4: STORY_AMBIGUITY, TEST_MISMATCH,
#   INFRA, MISSING_DEPENDENCY.
#
# Usage:
#   BLOCKER_TYPE=STORY_AMBIGUITY    bash run-blocker-test.sh
#   BLOCKER_TYPE=TEST_MISMATCH      bash run-blocker-test.sh
#   BLOCKER_TYPE=INFRA              bash run-blocker-test.sh
#   BLOCKER_TYPE=MISSING_DEPENDENCY bash run-blocker-test.sh
#
# After completion, run ./assert-blocker-test.sh to verify.

set -uo pipefail

BLOCKER_TYPE="${BLOCKER_TYPE:-STORY_AMBIGUITY}"

# Map blocker type → branch skill + title prefix the watcher will create.
case "$BLOCKER_TYPE" in
  STORY_AMBIGUITY)    BRANCH_SKILL=dev-team/story-rewrite;        BRANCH_TITLE_PREFIX=story-rewrite ;;
  TEST_MISMATCH)      BRANCH_SKILL=dev-team/story-test-review;    BRANCH_TITLE_PREFIX=story-test-review ;;
  INFRA)              BRANCH_SKILL=dev-team/infra-fix;            BRANCH_TITLE_PREFIX=infra-fix ;;
  MISSING_DEPENDENCY) BRANCH_SKILL=dev-team/prereq-builder;       BRANCH_TITLE_PREFIX=prereq ;;
  HARD_PROBLEM)       BRANCH_SKILL=dev-team/deep-research-bridge; BRANCH_TITLE_PREFIX=deep-research ;;
  *)
    echo "ERROR: unknown BLOCKER_TYPE: $BLOCKER_TYPE" >&2
    echo "Supported: STORY_AMBIGUITY, TEST_MISMATCH, INFRA, MISSING_DEPENDENCY, HARD_PROBLEM" >&2
    exit 2
    ;;
esac

ROOT=/tmp/hermes-kanban-slice2.5
rm -rf "$ROOT"
mkdir -p "$ROOT"/{src/__tests__,docs/stories,bin,.hermes/sessions}
cd "$ROOT"

# Persist the blocker type for the assert script
mkdir -p .hermes
echo "$BLOCKER_TYPE" > .hermes/blocker-type.txt
echo "$BRANCH_SKILL" > .hermes/branch-skill.txt
echo "$BRANCH_TITLE_PREFIX" > .hermes/branch-title-prefix.txt

# ─── Project scaffold ─────────────────────────────────────────────────────────

cat > package.json <<'JSON'
{
  "name": "hermes-kanban-slice2-5",
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

cat > AGENTS.md <<MD
# KanbanSlice2.5 — Agent Context

Slice 2.5 fixture: per-blocker-type branching. Configured for
BLOCKER_TYPE=$BLOCKER_TYPE → branch skill $BRANCH_SKILL.

The pi-dispatcher shim is configured to block its first 2 spawns with
\`BLOCKER_TYPE=$BLOCKER_TYPE\` in the block reason. The reactive
watcher reads the type and creates a corresponding branch task.

## Architecture
- TypeScript (ESM), vitest, beads (prefix KanbanSlice25).
MD

cat > docs/stories/1.1.add-two.md <<'MD'
---
id: KanbanSlice25-1
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

# ─── Pi shim — same as Slice 1/2 ──────────────────────────────────────────────

cat > bin/pi <<'SH'
#!/usr/bin/env bash
LOGDIR=/tmp/hermes-kanban-slice2.5/.hermes
mkdir -p "$LOGDIR" /tmp/hermes-kanban-slice2.5/.hermes/sessions
echo "$(date -Iseconds) ARGS: $*" >> "$LOGDIR/pi-shim.log"

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
echo "[pi-shim] wrote src/add.ts"
exit 0
SH
chmod +x bin/pi

# ─── bin/hermes shim (shared) ─────────────────────────────────────────────────
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

BARE_REMOTE=/tmp/hermes-kanban-slice2.5-remote.git
rm -rf "$BARE_REMOTE"
git init --bare -q "$BARE_REMOTE"
git remote add origin "$BARE_REMOTE"
git -c user.email=test@test -c user.name=test push -q -u origin HEAD:refs/heads/main
git branch --set-upstream-to=origin/main main 2>/dev/null || \
  git branch --set-upstream-to=origin/main master 2>/dev/null || true

echo "[setup] bd init..."
bd init --prefix KanbanSlice25 >/dev/null 2>&1 || true

BD_OUT=$(bd create "Sum two numbers" \
  --type feature --priority 0 \
  -d "story_file=docs/stories/1.1.add-two.md
test_file=src/__tests__/add.test.ts
budget_usd=2.00" 2>&1)
echo "$BD_OUT"
STORY_ID=$(echo "$BD_OUT" | grep -oE 'KanbanSlice25-[a-z0-9]+' | head -1)
[[ -z "$STORY_ID" ]] && STORY_ID=$(bd list --json 2>/dev/null | grep -oE '"id"[[:space:]]*:[[:space:]]*"KanbanSlice25-[a-z0-9]+"' | head -1 | grep -oE 'KanbanSlice25-[a-z0-9]+')
echo "$STORY_ID" > .hermes/story-id.txt
echo "[setup] story id = $STORY_ID"

# ─── Story-root + decomposition ───────────────────────────────────────────────

export PATH="$ROOT/bin:$HOME/.local/bin:$PATH"
export STORY_ID
export HERMES_SHIM_FAIL_FIRST=2
export HERMES_SHIM_BLOCKER_TYPE="$BLOCKER_TYPE"
export HERMES_TENANT=KanbanSlice25
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
echo "[run] story-root task = $ROOT_TASK_ID"
echo "[run] BLOCKER_TYPE=$BLOCKER_TYPE → branch skill: $BRANCH_SKILL"

IDS_JSON=$(bash "$HELPER" \
  "$STORY_ID" \
  "${ROOT}/docs/stories/1.1.add-two.md" \
  "${ROOT}/src/__tests__/add.test.ts" \
  "${ROOT}" \
  "story-${STORY_ID}" \
  "npx vitest run")
echo "$IDS_JSON" | tee .hermes/decomposer-output.json

hermes kanban complete "$ROOT_TASK_ID" \
  --summary "decomposed via deterministic helper (Slice 2.5 BLOCKER_TYPE=$BLOCKER_TYPE)" \
  --metadata "{\"task_graph\":$IDS_JSON,\"blocker_type\":\"$BLOCKER_TYPE\"}" >/dev/null 2>&1 || true
echo "[run] story-root marked done"

IMPL_TASK_ID=$(echo "$IDS_JSON" | python3 -c "
import json, sys
print(json.loads(sys.stdin.read()).get('story_impl', ''))
")
echo "[run] impl task id = $IMPL_TASK_ID"

# ─── Reactive escalation (BLOCKER_TYPE-aware) ─────────────────────────────────

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

  # Count blocked events (the same metric the shim uses).
  local block_count
  block_count=$(echo "$impl_json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(sum(1 for e in d.get('events', []) if e.get('kind') == 'blocked'))
except: print(0)
")

  if [[ "$block_count" -lt 2 ]]; then
    # First block — straight retry, "different approach" attempt.
    echo "[react] impl blocked at attempt $block_count — unblocking for retry"
    hermes kanban unblock "$impl_id" 2>&1 | tail -1
    return 0
  fi

  # Second block — read the most recent block reason, parse BLOCKER_TYPE, and
  # route to the matching branch task. If branch already exists and is done,
  # unblock impl. Idempotent across ticks.
  local last_reason
  last_reason=$(echo "$impl_json" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    blocks = [e for e in d.get('events', []) if e.get('kind') == 'blocked']
    if blocks:
        print(blocks[-1].get('payload', {}).get('reason', ''))
except: pass
")
  local detected_type
  detected_type=$(echo "$last_reason" | grep -oE 'BLOCKER_TYPE=[A-Z_]+' | head -1 | cut -d= -f2)
  [[ -z "$detected_type" ]] && detected_type=HARD_PROBLEM

  # Route — same map as the runner's case above.
  local route_skill route_title_prefix
  case "$detected_type" in
    STORY_AMBIGUITY)    route_skill=dev-team/story-rewrite;        route_title_prefix=story-rewrite ;;
    TEST_MISMATCH)      route_skill=dev-team/story-test-review;    route_title_prefix=story-test-review ;;
    INFRA)              route_skill=dev-team/infra-fix;            route_title_prefix=infra-fix ;;
    MISSING_DEPENDENCY) route_skill=dev-team/prereq-builder;       route_title_prefix=prereq ;;
    *)                  route_skill=dev-team/deep-research-bridge; route_title_prefix=deep-research ;;
  esac

  # Find existing branch task (idempotency on ticks).
  local branch_id
  branch_id=$(hermes kanban list --tenant "$HERMES_TENANT" --json 2>/dev/null \
    | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    prefix = '$route_title_prefix'
    for t in d:
        if t.get('title', '').lower().startswith(prefix.lower()):
            print(t['id']); break
except: pass
")

  if [[ -z "$branch_id" ]]; then
    echo "[react] impl blocked at attempt $block_count, BLOCKER_TYPE=$detected_type — creating branch task ($route_skill)"
    branch_id=$(hermes kanban create "${route_title_prefix} for ${STORY_ID}" \
      --assignee dev-orchestrator \
      --tenant "$HERMES_TENANT" \
      --workspace "dir:${ROOT}" \
      --skill "$route_skill" \
      --body "Branch task for blocker type $detected_type on impl $impl_id.

bd_id=${STORY_ID}
worktree=${ROOT}
test_file=${ROOT}/src/__tests__/add.test.ts
parent_impl_task=$impl_id
blocker_type=$detected_type" \
      --max-runtime 30m \
      --json | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
    echo "$branch_id" > .hermes/branch-task-id.txt
    echo "[react] created branch task $branch_id"
    return 0
  fi

  local branch_status
  branch_status=$(hermes kanban show "$branch_id" --json 2>/dev/null \
    | python3 -c "
import json, sys
try: print(json.load(sys.stdin)['task'].get('status','unknown'))
except: print('unknown')
")
  if [[ "$branch_status" == "done" ]]; then
    echo "[react] branch $branch_id done — unblocking impl"
    hermes kanban unblock "$impl_id" 2>&1 | tail -1
  else
    echo "[react] branch $branch_id status=$branch_status — waiting"
  fi
}

# ─── Polling loop ─────────────────────────────────────────────────────────────

echo "[run] reactive escalation loop active (BLOCKER_TYPE=$BLOCKER_TYPE, FAIL_FIRST=$HERMES_SHIM_FAIL_FIRST)"
echo "[run] waiting for dispatcher to drain (max 15 minutes)"
deadline=$(( $(date +%s) + 900 ))
while [[ $(date +%s) -lt $deadline ]]; do
  hermes kanban dispatch 2>&1 | tee -a .hermes/dispatch.log >/dev/null || true
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
  graph=$(hermes kanban list --tenant "$HERMES_TENANT" --json 2>/dev/null | python3 -c "
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

echo "[run] dispatcher dragged to completion or timeout. Now run ./assert-blocker-test.sh"
echo "[run] BLOCKER_TYPE was: $BLOCKER_TYPE"
echo "[run] story id was: $STORY_ID"
