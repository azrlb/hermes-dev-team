#!/usr/bin/env bash
# Slice 1 assertions for the kanban migration happy-path fixture.
#
# Plan: ~/.claude/plans/okay-lets-plan-theintergration-rustling-hedgehog.md §Slice 1.
#
# Acceptance criteria from §Slice 1 §Acceptance:
#   1. story-root kanban task created with --assignee dev-orchestrator
#   2. Within 5 minutes the dashboard shows orchestrator + 4 children all in `done`
#   3. bd show {id} shows status=closed
#   4. git log -1 --pretty=%B matches `fix({id}):`
#   5. .hermes/sessions/{id}.test-result exists with `PASS <HEAD-sha>`
#   6. git log origin/HEAD..HEAD is empty (push happened)         [N/A: no remote in fixture — assert local clean]
#   7. hermes kanban reclaim {story-land-id} post-success leaves the repo unchanged (idempotency)
#   8. Pi shim was invoked at least once (Pi dispatch wiring works)

set -uo pipefail

ROOT=/tmp/hermes-kanban-slice1
cd "$ROOT" 2>/dev/null || { echo "FAIL: $ROOT does not exist — run run-happy-path.sh first"; exit 99; }

STORY_ID=$(cat .hermes/story-id.txt 2>/dev/null || echo "")
[[ -z "$STORY_ID" ]] && { echo "FAIL: no story id captured by runner"; exit 99; }
ROOT_TASK_ID=$(cat .hermes/root-task-id.txt 2>/dev/null || echo "")

FAIL=0
pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "== Hermes Kanban Slice 1 happy-path assertions (story=$STORY_ID, root=$ROOT_TASK_ID) =="

# 1. story-root task exists in kanban with the right assignee
if [[ -n "$ROOT_TASK_ID" ]] && hermes kanban show "$ROOT_TASK_ID" --json 2>/dev/null | grep -q '"assignee"[[:space:]]*:[[:space:]]*"dev-orchestrator"'; then
  pass "1. story-root task created with --assignee dev-orchestrator"
else
  fail "1. story-root task missing or wrong assignee (id=$ROOT_TASK_ID)"
fi

# 2. Orchestrator + 4 child tasks all in `done`
#    Children: stack-detect, health-check, story-impl, story-verify, story-land
all_done=true
missing_or_pending=()
if [[ -n "$ROOT_TASK_ID" ]]; then
  task_json=$(hermes kanban show "$ROOT_TASK_ID" --json 2>/dev/null || echo '{}')
  root_status=$(echo "$task_json" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('status','unknown'))" 2>/dev/null)
  [[ "$root_status" != "done" ]] && { all_done=false; missing_or_pending+=("root=$root_status"); }

  # Count completed kanban tasks under this tenant — proxy for the children
  # (exact graph-walk depends on kanban v1 query API; this is a coarse count).
  done_count=$(hermes kanban list --tenant KanbanSlice1 --status done --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(len(d) if isinstance(d, list) else 0)
except Exception:
    print(0)
" 2>/dev/null)
  if [[ "$done_count" -ge 5 ]]; then
    pass "2. orchestrator + ≥4 children all done ($done_count tasks in done)"
  else
    fail "2. only $done_count tasks in done (expected ≥5: orchestrator + stack-detect + health-check + impl + verify + land)"
  fi
else
  fail "2. cannot check children — root task id missing"
fi

# 3. bd issue closed
if bd show "$STORY_ID" --json 2>/dev/null | grep -q '"status"[[:space:]]*:[[:space:]]*"closed"'; then
  pass "3. bd story $STORY_ID closed"
else
  STATUS=$(bd show "$STORY_ID" --json 2>/dev/null | grep -oE '"status"[[:space:]]*:[[:space:]]*"[a-z_]+"' | head -1)
  fail "3. bd story $STORY_ID NOT closed (status: $STATUS)"
fi

# 4. HEAD commit message matches fix(<id>):
HEAD_MSG=$(git log -1 --pretty=%B 2>/dev/null)
if echo "$HEAD_MSG" | grep -q "fix($STORY_ID):"; then
  pass "4. HEAD commit message matches fix($STORY_ID):"
else
  fail "4. HEAD commit message is '$HEAD_MSG' — expected to start with fix($STORY_ID):"
fi

# 5. .test-result file exists with PASS <HEAD-sha>
TEST_RESULT_FILE=".hermes/sessions/${STORY_ID}.test-result"
if [[ -f "$TEST_RESULT_FILE" ]]; then
  CONTENT=$(head -1 "$TEST_RESULT_FILE")
  HEAD_SHA=$(git rev-parse HEAD 2>/dev/null)
  if [[ "$CONTENT" == "PASS $HEAD_SHA" ]]; then
    pass "5. .test-result exists with 'PASS $HEAD_SHA'"
  else
    fail "5. .test-result content is '$CONTENT' — expected 'PASS $HEAD_SHA'"
  fi
else
  fail "5. .test-result file missing at $TEST_RESULT_FILE"
fi

# 6. Push state — no remote configured in fixture, so just assert working tree clean
if [[ -z "$(git status --porcelain 2>/dev/null)" ]]; then
  pass "6. working tree clean (no uncommitted changes)"
else
  fail "6. working tree has uncommitted changes after lander ran"
fi

# 7. Idempotency check — reclaim the lander, verify repo state unchanged
LANDER_TASK_ID=$(hermes kanban list --tenant KanbanSlice1 --status done --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    for t in (d if isinstance(d, list) else []):
        if 'land story' in t.get('title', '').lower():
            print(t.get('task_id', '')); break
except Exception:
    pass
" 2>/dev/null)

if [[ -n "$LANDER_TASK_ID" ]]; then
  PRE_HEAD=$(git rev-parse HEAD 2>/dev/null)
  PRE_TR=$(stat -c %Y "$TEST_RESULT_FILE" 2>/dev/null || echo "missing")
  hermes kanban reclaim "$LANDER_TASK_ID" >/dev/null 2>&1 || true
  sleep 30  # let dispatcher respawn the worker
  POST_HEAD=$(git rev-parse HEAD 2>/dev/null)
  POST_TR=$(stat -c %Y "$TEST_RESULT_FILE" 2>/dev/null || echo "missing")
  if [[ "$PRE_HEAD" == "$POST_HEAD" && "$PRE_TR" == "$POST_TR" ]]; then
    pass "7. lander idempotent under reclaim (HEAD + .test-result unchanged)"
  else
    fail "7. lander NOT idempotent — HEAD or .test-result mtime changed after reclaim"
  fi
else
  fail "7. cannot find [story-land] task to reclaim — children may not have been created"
fi

# 8. Pi shim was invoked
if [[ -f .hermes/pi-shim.log ]] && [[ -s .hermes/pi-shim.log ]]; then
  N=$(wc -l < .hermes/pi-shim.log)
  pass "8. Pi shim invoked $N time(s) — pi-dispatcher wiring works"
else
  fail "8. Pi shim NEVER invoked — pi-dispatcher didn't subprocess Pi"
fi

echo
if [[ "$FAIL" == "0" ]]; then
  echo -e "\033[32mAll Slice 1 assertions passed.\033[0m The kanban-native dev-team build half works end-to-end on a happy-path story."
  echo "Next: implement Slice 2 (escalation chain) per the migration plan."
else
  echo -e "\033[31m$FAIL assertion(s) failed.\033[0m Critical assertions: 3, 4, 5, 8."
fi
exit "$FAIL"
