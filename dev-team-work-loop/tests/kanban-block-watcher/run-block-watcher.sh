#!/usr/bin/env bash
# Block-watcher fixture — exercises the watcher → escalator → recovery
# chain added to skills/dev-team/{block-watcher,escalation-handler}/SKILL.md
# in commit b59b6af (2026-05-09), which closes Gap 2 from
# DESIGN-2026-05-09-disconnected-escalation.md.
#
# Strategy:
#   1. Set up a small tenant with one synthetic blocked task, planted
#      with a HEAD_MOVED_PASS block reason (verbatim from
#      land-the-plane/SKILL.md § HEAD moved protocol).
#   2. Create a [block-watcher] task and invoke the watcher shim.
#   3. The watcher detects the blocked task and creates an escalate-<id>
#      task assigned to dev-orchestrator with dev-team/escalation-handler.
#   4. Invoke the escalator shim on the escalate task.
#   5. The escalator classifies HEAD_MOVED_PASS, creates a [story-attribute]
#      recovery task assigned to hermes-lander.
#   6. Re-invoke the watcher to verify idempotency: it should NOT spawn a
#      duplicate escalator for the same blocked task.
#
# After the run, ./assert-block-watcher.sh verifies:
#   - exactly one escalate-* task exists for the blocked task
#   - the escalate task's metadata captures the right blocker_type
#   - a [story-attribute] recovery task exists with the right assignee/skill
#   - the watcher exited cleanly (kanban complete, not block)

set -uo pipefail

ROOT=/tmp/hermes-kanban-block-watcher
TENANT=KanbanBlockWatcher
SHIM=/media/bob/C/AI_Projects/hermes-dev-team/dev-team-work-loop/tests/kanban-block-watcher/shims/hermes-kanban-shim.sh
STATE="$ROOT/.fixture-state.txt"

mkdir -p "$ROOT"
: > "$STATE"

# ─── Cleanup any prior run ────────────────────────────────────────────────────

echo "[setup] archiving prior $TENANT tasks..."
hermes kanban list --tenant "$TENANT" --json 2>/dev/null \
  | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin) or []
    for t in d:
        print(t['id'])
except Exception:
    pass
" 2>/dev/null \
  | xargs -I{} hermes kanban archive {} 2>/dev/null || true

# ─── Step 1: plant a synthetic blocked task ───────────────────────────────────

echo "[step 1] planting synthetic blocked [story-land] task..."
BLOCKED_ID=$(hermes kanban create "[story-land] synthetic blocked lander" \
  --tenant "$TENANT" \
  --workspace "dir:${ROOT}" \
  --assignee hermes-lander \
  --skill dev-team/land-the-plane \
  --body "bd_id=fake-bd
worktree=${ROOT}" \
  --json | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
echo "  blocked task = $BLOCKED_ID"

# Use the verbatim HEAD_MOVED_PASS reason from
# land-the-plane/SKILL.md § HEAD moved protocol.
HEAD_MOVED_REASON="HEAD moved deadbeef→cafebabe; target test passes at HEAD; orchestrator must reconcile attribution"
hermes kanban block "$BLOCKED_ID" "$HEAD_MOVED_REASON" >/dev/null
echo "  blocked with reason: $HEAD_MOVED_REASON"
echo "blocked_id $BLOCKED_ID" >> "$STATE"

# ─── Step 2: create the [block-watcher] task ──────────────────────────────────

echo "[step 2] creating [block-watcher] task..."
WATCHER_ID=$(hermes kanban create "[block-watcher] watch ${TENANT}" \
  --tenant "$TENANT" \
  --workspace "dir:${ROOT}" \
  --assignee dev-orchestrator \
  --skill dev-team/block-watcher \
  --body "Watch tenant ${TENANT} for blocked tasks.
tenant=${TENANT}
poll_interval_seconds=1
max_runtime_seconds=30" \
  --json | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
echo "  watcher task = $WATCHER_ID"
echo "watcher_id $WATCHER_ID" >> "$STATE"

# ─── Step 3: invoke the watcher shim ──────────────────────────────────────────

echo "[step 3] invoking block-watcher shim..."
HERMES_KANBAN_TASK="$WATCHER_ID" \
HERMES_KANBAN_WORKSPACE="$ROOT" \
HERMES_SHIM_WATCHER_POLL_SECS=1 \
HERMES_SHIM_WATCHER_MAX_POLLS=4 \
  bash "$SHIM" -p dev-orchestrator \
    --skills kanban-orchestrator \
    --skills dev-team/block-watcher \
    chat -q "watch task $WATCHER_ID" 2>&1 | tail -10

# ─── Step 4: dispatch the escalator the watcher just created ──────────────────

ESCALATE_ID=$(hermes kanban list --tenant "$TENANT" --status ready --json 2>/dev/null \
  | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin) or []
    for t in d:
        if t.get('title','').startswith('escalate-'):
            print(t['id']); break
except Exception:
    pass
")
if [[ -z "$ESCALATE_ID" ]]; then
  echo "[step 4] WARN: no escalate-* task in ready status; checking all statuses..."
  ESCALATE_ID=$(hermes kanban list --tenant "$TENANT" --json 2>/dev/null \
    | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin) or []
    for t in d:
        if t.get('title','').startswith('escalate-'):
            print(t['id']); break
except Exception:
    pass
")
fi
echo "  escalate task = ${ESCALATE_ID:-MISSING}"
echo "escalate_id ${ESCALATE_ID:-MISSING}" >> "$STATE"

if [[ -n "$ESCALATE_ID" && "$ESCALATE_ID" != "MISSING" ]]; then
  echo "[step 4] invoking escalation-handler shim..."
  HERMES_KANBAN_TASK="$ESCALATE_ID" \
  HERMES_KANBAN_WORKSPACE="$ROOT" \
    bash "$SHIM" -p dev-orchestrator \
      --skills kanban-orchestrator \
      --skills dev-team/escalation-handler \
      chat -q "handle escalation $ESCALATE_ID" 2>&1 | tail -10
fi

# ─── Step 5: record the recovery task id (if any) ─────────────────────────────

RECOVERY_ID=$(hermes kanban list --tenant "$TENANT" --json 2>/dev/null \
  | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin) or []
    for t in d:
        title = t.get('title','')
        if title.startswith('[story-attribute') or title.startswith('[story-impl-attempt'):
            print(t['id']); break
except Exception:
    pass
")
echo "  recovery task = ${RECOVERY_ID:-MISSING}"
echo "recovery_id ${RECOVERY_ID:-MISSING}" >> "$STATE"

# ─── Step 6: idempotency check ────────────────────────────────────────────────
# Re-invoke a fresh watcher; it should NOT spawn another escalate-* for
# the same blocked task. We give the watcher a different id (new task)
# to simulate a watcher restart.

echo "[step 6] idempotency check — running a 2nd watcher round..."
WATCHER2_ID=$(hermes kanban create "[block-watcher] watch ${TENANT} (round 2)" \
  --tenant "$TENANT" \
  --workspace "dir:${ROOT}" \
  --assignee dev-orchestrator \
  --skill dev-team/block-watcher \
  --body "Watch tenant ${TENANT} for blocked tasks.
tenant=${TENANT}
poll_interval_seconds=1
max_runtime_seconds=10" \
  --json | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
echo "watcher2_id $WATCHER2_ID" >> "$STATE"

HERMES_KANBAN_TASK="$WATCHER2_ID" \
HERMES_KANBAN_WORKSPACE="$ROOT" \
HERMES_SHIM_WATCHER_POLL_SECS=1 \
HERMES_SHIM_WATCHER_MAX_POLLS=3 \
  bash "$SHIM" -p dev-orchestrator \
    --skills kanban-orchestrator \
    --skills dev-team/block-watcher \
    chat -q "watch round 2 $WATCHER2_ID" 2>&1 | tail -5

ESCALATE_COUNT=$(hermes kanban list --tenant "$TENANT" --json 2>/dev/null \
  | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin) or []
    print(sum(1 for t in d if t.get('title','').startswith('escalate-')))
except Exception:
    print(-1)
")
echo "  total escalate-* tasks in tenant: $ESCALATE_COUNT (idempotent if = 1)"
echo "escalate_count $ESCALATE_COUNT" >> "$STATE"

echo
echo "[done] state file: $STATE"
echo "[done] now run ./assert-block-watcher.sh"
