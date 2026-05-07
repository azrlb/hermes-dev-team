#!/usr/bin/env bash
# Slice 2 assertions for the kanban-native escalation regression.
#
# Plan: ~/.claude/plans/okay-lets-plan-theintergration-rustling-hedgehog.md §Slice 2.
#
# What we're proving:
#   The dispatcher + a reactive escalation loop converge to a passing
#   impl across 3 attempts via a deep-research-bridge step, without
#   any human intervention. End-to-end completion through verify and
#   land follows.

set -uo pipefail

ROOT=/tmp/hermes-kanban-slice2
cd "$ROOT" 2>/dev/null || { echo "FAIL: $ROOT does not exist — run run-escalation-test-kanban.sh first"; exit 99; }

STORY_ID=$(cat .hermes/story-id.txt 2>/dev/null || echo "")
[[ -z "$STORY_ID" ]] && { echo "FAIL: no story id captured by runner"; exit 99; }
ROOT_TASK_ID=$(cat .hermes/root-task-id.txt 2>/dev/null || echo "")

FAIL=0
pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "== Hermes Kanban Slice 2 escalation assertions (story=$STORY_ID, root=$ROOT_TASK_ID) =="

# 1. story-root task exists with dev-orchestrator assignee
if [[ -n "$ROOT_TASK_ID" ]] && hermes kanban show "$ROOT_TASK_ID" --json 2>/dev/null | grep -q '"assignee"[[:space:]]*:[[:space:]]*"dev-orchestrator"'; then
  pass "1. story-root task created with --assignee dev-orchestrator"
else
  fail "1. story-root task missing or wrong assignee (id=$ROOT_TASK_ID)"
fi

# 2. ≥6 done tasks (orchestrator + 5 children + deep-research)
done_count=$(hermes kanban list --tenant KanbanSlice2 --status done --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    print(len(d) if isinstance(d, list) else 0)
except Exception:
    print(0)
" 2>/dev/null)
if [[ "$done_count" -ge 6 ]]; then
  pass "2. ≥6 done tasks ($done_count) — orchestrator + 5 children + deep-research"
else
  fail "2. only $done_count done tasks (expected ≥6: orchestrator + stack-detect + health-check + impl + verify + land + deep-research)"
fi

# 3. impl task had ≥3 runs (proves fail-twice-then-succeed)
IMPL_ID=$(hermes kanban list --tenant KanbanSlice2 --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    for t in d:
        if 'impl story' in t.get('title','').lower():
            print(t['id']); break
except: pass
")
if [[ -n "$IMPL_ID" ]]; then
  RUN_COUNT=$(hermes kanban show "$IMPL_ID" --json 2>/dev/null | python3 -c "
import json, sys
try: print(len(json.load(sys.stdin).get('runs', [])))
except: print(0)
")
  if [[ "$RUN_COUNT" -ge 3 ]]; then
    pass "3. impl task had $RUN_COUNT runs (≥3) — escalation chain triggered"
  else
    fail "3. impl task only had $RUN_COUNT runs (expected ≥3 for escalation)"
  fi
else
  fail "3. cannot find impl task to count runs"
fi

# 4. deep-research task was created and completed (key reactive-escalation evidence)
RESEARCH_ID=$(hermes kanban list --tenant KanbanSlice2 --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    for t in d:
        if 'deep-research' in t.get('title','').lower():
            print(t['id']); break
except: pass
")
if [[ -n "$RESEARCH_ID" ]]; then
  RESEARCH_STATUS=$(hermes kanban show "$RESEARCH_ID" --json 2>/dev/null | python3 -c "
import json, sys
try: print(json.load(sys.stdin)['task'].get('status','unknown'))
except: print('unknown')
")
  if [[ "$RESEARCH_STATUS" == "done" ]]; then
    pass "4. [story-deep-research] task created and completed — reactive escalation fired"
  else
    fail "4. [story-deep-research] task exists but status=$RESEARCH_STATUS"
  fi
else
  fail "4. NO [story-deep-research] task created — reactive escalation did NOT fire"
fi

# 5. impl had at least one 'unblocked' event (proves the reactive watcher acted)
if [[ -n "$IMPL_ID" ]]; then
  UNBLOCK_COUNT=$(hermes kanban show "$IMPL_ID" --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(sum(1 for e in d.get('events', []) if e.get('kind') == 'unblocked'))
except: print(0)
")
  if [[ "$UNBLOCK_COUNT" -ge 2 ]]; then
    pass "5. impl received $UNBLOCK_COUNT unblock events (≥2) — reactive watcher fired twice"
  else
    fail "5. impl only received $UNBLOCK_COUNT unblock events (expected ≥2: post-attempt-1 retry, post-deep-research)"
  fi
else
  fail "5. cannot find impl task to count unblock events"
fi

# 6. bd issue closed
if bd show "$STORY_ID" --json 2>/dev/null | grep -q '"status"[[:space:]]*:[[:space:]]*"closed"'; then
  pass "6. bd story $STORY_ID closed"
else
  STATUS=$(bd show "$STORY_ID" --json 2>/dev/null | grep -oE '"status"[[:space:]]*:[[:space:]]*"[a-z_]+"' | head -1)
  fail "6. bd story $STORY_ID NOT closed (status: $STATUS)"
fi

# 7. HEAD commit message matches fix(<id>):
HEAD_MSG=$(git log -1 --pretty=%B 2>/dev/null)
if echo "$HEAD_MSG" | grep -q "fix($STORY_ID):"; then
  pass "7. HEAD commit message matches fix($STORY_ID):"
else
  fail "7. HEAD commit message is '$HEAD_MSG' — expected to start with fix($STORY_ID):"
fi

# 8. .test-result file exists with PASS <HEAD-sha>
TEST_RESULT_FILE=".hermes/sessions/${STORY_ID}.test-result"
if [[ -f "$TEST_RESULT_FILE" ]]; then
  CONTENT=$(head -1 "$TEST_RESULT_FILE")
  HEAD_SHA=$(git rev-parse HEAD 2>/dev/null)
  if [[ "$CONTENT" == "PASS $HEAD_SHA" ]]; then
    pass "8. .test-result exists with 'PASS $HEAD_SHA'"
  else
    fail "8. .test-result content is '$CONTENT' — expected 'PASS $HEAD_SHA'"
  fi
else
  fail "8. .test-result file missing at $TEST_RESULT_FILE"
fi

# 9. working tree clean
if [[ -z "$(git status --porcelain 2>/dev/null)" ]]; then
  pass "9. working tree clean (no uncommitted changes)"
else
  fail "9. working tree has uncommitted changes after lander ran"
fi

# 10. Pi shim invoked at least 2 times (final impl write + Quinn review at land)
if [[ -f .hermes/pi-shim.log ]] && [[ -s .hermes/pi-shim.log ]]; then
  N=$(wc -l < .hermes/pi-shim.log)
  if [[ "$N" -ge 2 ]]; then
    pass "10. Pi shim invoked $N time(s) (≥2) — pi-dispatcher + lander Quinn review wired"
  else
    fail "10. Pi shim only invoked $N time(s) (expected ≥2)"
  fi
else
  fail "10. Pi shim NEVER invoked"
fi

echo
if [[ "$FAIL" == "0" ]]; then
  echo -e "\033[32mAll Slice 2 assertions passed.\033[0m The reactive escalation loop converges fail-twice-then-deep-research-then-succeed end-to-end."
  echo "Next: extend with the other 4 blocker-type branches (TEST_MISMATCH, MISSING_DEPENDENCY, INFRA, STORY_AMBIGUITY) as Slice 2.5."
else
  echo -e "\033[31m$FAIL assertion(s) failed.\033[0m Critical assertions: 3 (impl runs), 4 (deep-research created), 5 (reactive unblocks), 6 (bd closed)."
fi
exit "$FAIL"
