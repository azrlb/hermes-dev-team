#!/usr/bin/env bash
# Sidecar runtime acceptance assertions — verifies the right outcome
# metadata was emitted for the SCENARIO that ran.

set -uo pipefail

ROOT=/tmp/hermes-kanban-sidecar
cd "$ROOT" 2>/dev/null || { echo "FAIL: $ROOT does not exist — run run-sidecar-test.sh first"; exit 99; }

SCENARIO=$(cat .hermes/scenario.txt 2>/dev/null || echo "")
EXPECTED_SKILL=$(cat .hermes/expected-skill.txt 2>/dev/null || echo "")
TASK_ID=$(cat .hermes/task-id.txt 2>/dev/null || echo "")
[[ -z "$SCENARIO" || -z "$TASK_ID" ]] && { echo "FAIL: missing fixture state"; exit 99; }

FAIL=0
pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "== Sidecar runtime assertions (SCENARIO=$SCENARIO, task=$TASK_ID) =="

# 1. Task exists and uses the right skill
TASK_JSON=$(hermes kanban show "$TASK_ID" --json 2>/dev/null)
ACTUAL_SKILL=$(echo "$TASK_JSON" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    skills = d['task'].get('skills', [])
    print(skills[0] if skills else '')
except: pass
")
if [[ "$ACTUAL_SKILL" == "$EXPECTED_SKILL" ]]; then
  pass "1. task uses skill '$EXPECTED_SKILL'"
else
  fail "1. task skill is '$ACTUAL_SKILL' — expected '$EXPECTED_SKILL'"
fi

# 2. Task reached terminal state (done, not blocked/crashed)
ACTUAL_STATUS=$(echo "$TASK_JSON" | python3 -c "
import json, sys
try: print(json.load(sys.stdin)['task'].get('status','unknown'))
except: print('unknown')
")
if [[ "$ACTUAL_STATUS" == "done" ]]; then
  pass "2. task converged to done"
else
  fail "2. task status=$ACTUAL_STATUS — expected done"
fi

# 3. Outcome metadata was emitted
LATEST_SUMMARY=$(echo "$TASK_JSON" | python3 -c "
import json, sys
try: print(json.load(sys.stdin).get('latest_summary',''))
except: pass
")
if [[ -n "$LATEST_SUMMARY" ]]; then
  pass "3. summary emitted: '$LATEST_SUMMARY'"
else
  fail "3. no summary on the closing run"
fi

# 4. Per-scenario metadata shape — the canonical fields the sidecar
#    needs for downstream (audit log, dashboard, weekly reporter)
RUN_METADATA=$(echo "$TASK_JSON" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for r in d.get('runs', []):
        md = r.get('metadata', {}) or {}
        if md:
            print(json.dumps(md))
            break
except: pass
")

case "$SCENARIO" in
  EMAIL)
    REQUIRED_FIELDS="classification outcome draft_text"
    ;;
  SUPPORT)
    REQUIRED_FIELDS="intent outcome reply_text"
    ;;
  BUG_FIX)
    REQUIRED_FIELDS="error_class skill_matched outcome regression_check"
    ;;
  *)
    REQUIRED_FIELDS=""
    ;;
esac

ALL_PRESENT=true
for f in $REQUIRED_FIELDS; do
  if echo "$RUN_METADATA" | grep -q "\"$f\""; then
    :
  else
    ALL_PRESENT=false
    fail "4. metadata field '$f' missing"
  fi
done
if [[ "$ALL_PRESENT" == "true" ]]; then
  pass "4. metadata has all required fields ($REQUIRED_FIELDS)"
fi

# 5. The outcome is a successful auto-handle (not escalated)
OUTCOME=$(echo "$RUN_METADATA" | python3 -c "
import json, sys
try: print(json.load(sys.stdin).get('outcome', ''))
except: pass
")
case "$OUTCOME" in
  AUTO_RESOLVED|AUTO_FIXED|RESOLVED)
    pass "5. outcome=$OUTCOME — sidecar auto-handled the request"
    ;;
  *)
    fail "5. outcome='$OUTCOME' — expected AUTO_RESOLVED or AUTO_FIXED"
    ;;
esac

echo
if [[ "$FAIL" == "0" ]]; then
  echo -e "\033[32mAll sidecar runtime assertions passed for SCENARIO=$SCENARIO.\033[0m"
else
  echo -e "\033[31m$FAIL assertion(s) failed for SCENARIO=$SCENARIO.\033[0m"
fi
exit "$FAIL"
