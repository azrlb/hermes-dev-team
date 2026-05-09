#!/usr/bin/env bash
# Assertions for the kanban-block-watcher fixture.
#
# Acceptance:
#   1. Watcher created exactly one escalate-<blocked_id> task
#   2. Escalator task has the right title and assignee/skill (dev-orchestrator
#      / dev-team/escalation-handler)
#   3. Escalator's metadata captures blocker_type=HEAD_MOVED_PASS and the
#      verbatim block_reason
#   4. Recovery task exists with title [story-attribute-<blocked_id>],
#      assignee=hermes-lander, skill=dev-team/land-the-plane
#   5. Idempotency: a 2nd watcher round did NOT create a duplicate escalator
#      (escalate_count == 1)
#   6. Watcher tasks completed cleanly (status=done, not blocked)

set -uo pipefail

ROOT=/tmp/hermes-kanban-block-watcher
STATE="$ROOT/.fixture-state.txt"

if [[ ! -f "$STATE" ]]; then
  echo "FAIL: $STATE missing — run ./run-block-watcher.sh first"
  exit 99
fi

FAIL=0
pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=$((FAIL+1)); }

get_state() { awk -v key="$1" '$1==key {print $2; exit}' "$STATE"; }

BLOCKED_ID=$(get_state blocked_id)
WATCHER_ID=$(get_state watcher_id)
WATCHER2_ID=$(get_state watcher2_id)
ESCALATE_ID=$(get_state escalate_id)
RECOVERY_ID=$(get_state recovery_id)
ESCALATE_COUNT=$(get_state escalate_count)

echo "== Block-watcher fixture assertions =="
echo "  blocked=$BLOCKED_ID watcher=$WATCHER_ID watcher2=$WATCHER2_ID"
echo "  escalate=$ESCALATE_ID recovery=$RECOVERY_ID escalate_count=$ESCALATE_COUNT"

# ── 1. Exactly one escalator ────────────────────────────────────────────────

if [[ "$ESCALATE_COUNT" == "1" ]]; then
  pass "1. exactly one escalate-* task in tenant (idempotent)"
else
  fail "1. expected 1 escalate-* task, got $ESCALATE_COUNT"
fi

# ── 2. Escalator title + assignee + skill ───────────────────────────────────

if [[ -z "$ESCALATE_ID" || "$ESCALATE_ID" == "MISSING" ]]; then
  fail "2. no escalator task captured (watcher did not spawn)"
else
  ESC_JSON=$(hermes kanban show "$ESCALATE_ID" --json 2>/dev/null)
  ESC_TITLE=$(echo "$ESC_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['task']['title'])" 2>/dev/null)
  ESC_ASSIGNEE=$(echo "$ESC_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['task']['assignee'])" 2>/dev/null)
  ESC_SKILLS=$(echo "$ESC_JSON" | python3 -c "import json,sys; print(','.join(json.load(sys.stdin)['task'].get('skills',[])))" 2>/dev/null)

  if [[ "$ESC_TITLE" == "escalate-${BLOCKED_ID}" ]]; then
    pass "2a. escalator title = escalate-${BLOCKED_ID}"
  else
    fail "2a. escalator title was '$ESC_TITLE' — expected escalate-${BLOCKED_ID}"
  fi
  if [[ "$ESC_ASSIGNEE" == "dev-orchestrator" ]]; then
    pass "2b. escalator assignee = dev-orchestrator"
  else
    fail "2b. escalator assignee was '$ESC_ASSIGNEE'"
  fi
  if [[ "$ESC_SKILLS" == *"dev-team/escalation-handler"* ]]; then
    pass "2c. escalator skill = dev-team/escalation-handler"
  else
    fail "2c. escalator skills was '$ESC_SKILLS'"
  fi
fi

# ── 3. Escalator metadata captures classification ──────────────────────────

if [[ -n "$ESCALATE_ID" && "$ESCALATE_ID" != "MISSING" ]]; then
  ESC_META=$(hermes kanban show "$ESCALATE_ID" --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for r in d.get('runs', []):
        md = r.get('metadata') or {}
        if 'blocker_type' in md:
            print(json.dumps(md)); break
except Exception:
    pass
")
  if echo "$ESC_META" | grep -q '"blocker_type": "HEAD_MOVED_PASS"'; then
    pass "3a. escalator metadata.blocker_type = HEAD_MOVED_PASS"
  else
    fail "3a. escalator metadata missing blocker_type=HEAD_MOVED_PASS (got: $ESC_META)"
  fi
  if echo "$ESC_META" | grep -q "target test passes at HEAD"; then
    pass "3b. escalator metadata captures verbatim block_reason"
  else
    fail "3b. escalator metadata missing block_reason snippet (got: $ESC_META)"
  fi
fi

# ── 4. Recovery task created with right shape ──────────────────────────────

if [[ -z "$RECOVERY_ID" || "$RECOVERY_ID" == "MISSING" ]]; then
  fail "4. no recovery task spawned by escalator"
else
  REC_JSON=$(hermes kanban show "$RECOVERY_ID" --json 2>/dev/null)
  REC_TITLE=$(echo "$REC_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['task']['title'])" 2>/dev/null)
  REC_ASSIGNEE=$(echo "$REC_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['task']['assignee'])" 2>/dev/null)
  REC_SKILLS=$(echo "$REC_JSON" | python3 -c "import json,sys; print(','.join(json.load(sys.stdin)['task'].get('skills',[])))" 2>/dev/null)

  if [[ "$REC_TITLE" == "[story-attribute-${BLOCKED_ID}]" ]]; then
    pass "4a. recovery title = [story-attribute-${BLOCKED_ID}]"
  else
    fail "4a. recovery title was '$REC_TITLE' — expected [story-attribute-${BLOCKED_ID}]"
  fi
  if [[ "$REC_ASSIGNEE" == "hermes-lander" ]]; then
    pass "4b. recovery assignee = hermes-lander"
  else
    fail "4b. recovery assignee was '$REC_ASSIGNEE'"
  fi
  if [[ "$REC_SKILLS" == *"dev-team/land-the-plane"* ]]; then
    pass "4c. recovery skill = dev-team/land-the-plane"
  else
    fail "4c. recovery skills was '$REC_SKILLS'"
  fi
fi

# ── 5. Both watchers exited cleanly (kanban complete) ──────────────────────

for w in "$WATCHER_ID" "$WATCHER2_ID"; do
  [[ -z "$w" ]] && continue
  W_STATUS=$(hermes kanban show "$w" --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['task']['status'])" 2>/dev/null)
  if [[ "$W_STATUS" == "done" ]]; then
    pass "5. watcher $w completed cleanly (status=done)"
  else
    fail "5. watcher $w status was '$W_STATUS' (expected done)"
  fi
done

echo
if [[ "$FAIL" == "0" ]]; then
  echo -e "\033[32mAll block-watcher assertions passed.\033[0m"
  echo "Protects skills/dev-team/{block-watcher,escalation-handler}/SKILL.md"
  echo "and the eval-runner watcher wiring (hermes-model-eval/scripts/run-devteam-eval.sh §step 4b)."
else
  echo -e "\033[31m$FAIL assertion(s) failed.\033[0m"
fi
exit "$FAIL"
