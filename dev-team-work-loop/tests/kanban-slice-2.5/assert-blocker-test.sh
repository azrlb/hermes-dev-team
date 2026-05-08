#!/usr/bin/env bash
# Slice 2.5 assertions — verifies the BLOCKER_TYPE-specific branch fired.

set -uo pipefail

ROOT=/tmp/hermes-kanban-slice2.5
cd "$ROOT" 2>/dev/null || { echo "FAIL: $ROOT does not exist — run run-blocker-test.sh first"; exit 99; }

STORY_ID=$(cat .hermes/story-id.txt 2>/dev/null || echo "")
BLOCKER_TYPE=$(cat .hermes/blocker-type.txt 2>/dev/null || echo "")
BRANCH_SKILL=$(cat .hermes/branch-skill.txt 2>/dev/null || echo "")
BRANCH_TITLE_PREFIX=$(cat .hermes/branch-title-prefix.txt 2>/dev/null || echo "")
[[ -z "$STORY_ID" || -z "$BLOCKER_TYPE" ]] && { echo "FAIL: missing fixture state"; exit 99; }

FAIL=0
pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "== Slice 2.5 BLOCKER_TYPE=$BLOCKER_TYPE assertions (story=$STORY_ID) =="

# 1. Branch task of the right type was created
BRANCH_ID=$(hermes kanban list --tenant KanbanSlice25 --json 2>/dev/null | python3 -c "
import json, sys
prefix = '$BRANCH_TITLE_PREFIX'
try:
    d = json.loads(sys.stdin.read())
    for t in d:
        if t.get('title', '').lower().startswith(prefix.lower()):
            print(t['id']); break
except: pass
")
if [[ -n "$BRANCH_ID" ]]; then
  pass "1. branch task created (id=$BRANCH_ID, prefix=$BRANCH_TITLE_PREFIX)"
else
  fail "1. NO branch task with prefix '$BRANCH_TITLE_PREFIX' — reactive routing did not fire for $BLOCKER_TYPE"
fi

# 2. Branch task uses the correct skill
if [[ -n "$BRANCH_ID" ]]; then
  ACTUAL_SKILL=$(hermes kanban show "$BRANCH_ID" --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    skills = d['task'].get('skills', [])
    print(skills[0] if skills else '')
except: pass
")
  if [[ "$ACTUAL_SKILL" == "$BRANCH_SKILL" ]]; then
    pass "2. branch task uses skill '$BRANCH_SKILL'"
  else
    fail "2. branch task skill is '$ACTUAL_SKILL' — expected '$BRANCH_SKILL'"
  fi
else
  fail "2. cannot check branch skill — no branch task"
fi

# 3. Branch task completed
if [[ -n "$BRANCH_ID" ]]; then
  BRANCH_STATUS=$(hermes kanban show "$BRANCH_ID" --json 2>/dev/null | python3 -c "
import json, sys
try: print(json.load(sys.stdin)['task'].get('status','unknown'))
except: print('unknown')
")
  if [[ "$BRANCH_STATUS" == "done" ]]; then
    pass "3. branch task completed"
  else
    fail "3. branch task status=$BRANCH_STATUS"
  fi
else
  fail "3. cannot check branch status — no branch task"
fi

# 4. Block reason carried the BLOCKER_TYPE token
IMPL_ID=$(hermes kanban list --tenant KanbanSlice25 --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read())
    for t in d:
        if 'impl story' in t.get('title','').lower():
            print(t['id']); break
except: pass
")
if [[ -n "$IMPL_ID" ]]; then
  REASONS=$(hermes kanban show "$IMPL_ID" --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    blocks = [e.get('payload', {}).get('reason', '') for e in d.get('events', []) if e.get('kind') == 'blocked']
    print('\n'.join(blocks))
except: pass
")
  if echo "$REASONS" | grep -q "BLOCKER_TYPE=$BLOCKER_TYPE"; then
    pass "4. block reason carried BLOCKER_TYPE=$BLOCKER_TYPE token"
  else
    fail "4. block reason did NOT carry BLOCKER_TYPE=$BLOCKER_TYPE: $REASONS"
  fi
else
  fail "4. cannot find impl task to inspect block reasons"
fi

# 5. impl converged after branch (≥3 runs)
if [[ -n "$IMPL_ID" ]]; then
  RUN_COUNT=$(hermes kanban show "$IMPL_ID" --json 2>/dev/null | python3 -c "
import json, sys
try: print(len(json.load(sys.stdin).get('runs', [])))
except: print(0)
")
  if [[ "$RUN_COUNT" -ge 3 ]]; then
    pass "5. impl had $RUN_COUNT runs (≥3) — converged after branch"
  else
    fail "5. impl only had $RUN_COUNT runs"
  fi
fi

# 6. bd closed (full convergence)
if bd show "$STORY_ID" --json 2>/dev/null | grep -q '"status"[[:space:]]*:[[:space:]]*"closed"'; then
  pass "6. bd story $STORY_ID closed — full convergence"
else
  fail "6. bd story $STORY_ID NOT closed"
fi

# 7. HEAD commit fix(<id>): + working tree clean
HEAD_MSG=$(git log -1 --pretty=%B 2>/dev/null)
if echo "$HEAD_MSG" | grep -q "fix($STORY_ID):"; then
  pass "7. HEAD commit message matches fix($STORY_ID):"
else
  fail "7. HEAD commit message is '$HEAD_MSG' — expected fix($STORY_ID):"
fi

if [[ -z "$(git status --porcelain 2>/dev/null)" ]]; then
  pass "8. working tree clean"
else
  fail "8. working tree dirty"
fi

echo
if [[ "$FAIL" == "0" ]]; then
  echo -e "\033[32mAll Slice 2.5 assertions passed for BLOCKER_TYPE=$BLOCKER_TYPE.\033[0m"
else
  echo -e "\033[31m$FAIL assertion(s) failed for BLOCKER_TYPE=$BLOCKER_TYPE.\033[0m"
fi
exit "$FAIL"
