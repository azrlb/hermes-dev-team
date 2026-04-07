#!/usr/bin/env bash
# Assertions for the Hermes work-loop escalation regression test (v2).
set -uo pipefail

ROOT=/tmp/hermes-escalation-test
cd "$ROOT" 2>/dev/null || { echo "FAIL: $ROOT does not exist — run run-escalation-test.sh first"; exit 99; }

STORY_ID=$(cat .hermes/story-id.txt 2>/dev/null || echo "")
[[ -z "$STORY_ID" ]] && { echo "FAIL: no story id captured by runner"; exit 99; }

FAIL=0
pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=$((FAIL+1)); }

echo "== Hermes escalation regression assertions (story=$STORY_ID) =="

# 1. Pi shim was actually invoked (proves orchestrator went through Step 7)
if [[ -f .hermes/pi-shim.log ]] && [[ -s .hermes/pi-shim.log ]]; then
  N=$(wc -l < .hermes/pi-shim.log)
  pass "1. Pi shim invoked $N time(s) — orchestrator dispatched via Step 7"
else
  fail "1. Pi shim NEVER invoked — orchestrator bypassed Step 7 (wrote code inline?)"
fi

# 2. claude -p shim was reached (proves escalation chain fired)
if [[ -f .hermes/claude-shim.log ]] && grep -q -- "ARGS: -p" .hermes/claude-shim.log; then
  pass "2. Escalation reached 'claude -p'"
else
  fail "2. claude -p was never invoked — escalation chain didn't fire after Pi stalled"
fi

# 3. The story's test file was re-run AFTER the claude -p line (Verify & Resume)
if awk '
  /claude -p/ { seen=1; next }
  seen && /(vitest|test_single_cmd).*tricky-parser\.test\.ts/ { found=1; exit }
  END { exit !found }
' run.log; then
  pass "3. Test file re-run after claude -p (Verify & Resume executed) — THE FIX WORKS"
else
  fail "3. No test re-run after claude -p — Verify & Resume block did NOT execute (THE BUG)"
fi

# 4. Tests pass at the end (independent re-run)
if npx vitest run src/__tests__/tricky-parser.test.ts --reporter=basic >/tmp/esc-final.log 2>&1; then
  pass "4. Final test run passes"
else
  fail "4. Final test run fails — claude -p shim didn't apply the fix"
fi

# 5. Story is closed in beads
if bd show "$STORY_ID" --json 2>/dev/null | grep -q '"status"[[:space:]]*:[[:space:]]*"closed"'; then
  pass "5. Story $STORY_ID is closed"
else
  STATUS=$(bd show "$STORY_ID" --json 2>/dev/null | grep -oE '"status"[[:space:]]*:[[:space:]]*"[a-z_]+"' | head -1)
  fail "5. Story $STORY_ID NOT closed (status: $STATUS)"
fi

# 6. Pi session file exists (proves Step 7 passed --session)
if compgen -G ".hermes/sessions/*.jsonl" >/dev/null; then
  N=$(ls .hermes/sessions/*.jsonl | wc -l)
  pass "6. Pi session file(s) created ($N) — --session wiring in place"
else
  fail "6. No pi session file — Step 7 didn't pass --session .hermes/sessions/{story_id}.jsonl"
fi

# 7. No story left in_progress
INPROG=$(bd list --status=in_progress --json 2>/dev/null | grep -c '"id"' || true)
if [[ "$INPROG" == "0" ]]; then
  pass "7. No stories left in_progress"
else
  fail "7. $INPROG stories still in_progress"
fi

# 8. Wall-time/log sanity
LINES=$(wc -l < run.log)
if [[ "$LINES" -gt 10 ]]; then
  pass "8. run.log has content ($LINES lines)"
else
  fail "8. run.log suspiciously short ($LINES lines)"
fi

echo
if [[ "$FAIL" == "0" ]]; then
  echo -e "\033[32mAll assertions passed.\033[0m The Verify & Resume fix is working end-to-end."
else
  echo -e "\033[31m$FAIL assertion(s) failed.\033[0m Critical assertions: 1, 2, 3, 5."
fi
exit "$FAIL"
