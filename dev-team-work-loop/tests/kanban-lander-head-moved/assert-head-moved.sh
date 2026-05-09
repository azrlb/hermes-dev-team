#!/usr/bin/env bash
# Assertions for the lander HEAD-moved fixture.
#
# Verifies that for each variant, the lander shim emitted a `blocked` event
# on the [story-land] task with the SKILL-prescribed reason format. The
# reason format is sensitive to the SKILL.md banned-phrase list — any drift
# in either direction (shim or SKILL) should fail this fixture.
#
# Acceptance criteria (from skills/dev-team/land-the-plane/SKILL.md
# § HEAD moved protocol, table at lines 122-126):
#   PASS variant: "HEAD moved <old>→<new>; target test passes at HEAD;
#                  orchestrator must reconcile attribution"
#   FAIL variant: "HEAD moved <old>→<new>; target test still failing at HEAD;
#                  substrate race or work lost"
#
# Banned phrases (must not appear in any block reason):
#   - "the fix is already at HEAD via..."
#   - "another worker committed..."
#   - "my fix was bundled into..."
#   - "mega-commit absorbed..."
#   - "working tree is clean because..."

set -uo pipefail

ROOT=/tmp/hermes-kanban-lander-head-moved
STATE="$ROOT/.fixture-state.txt"

if [[ ! -f "$STATE" ]]; then
  echo "FAIL: $STATE missing — run ./run-head-moved.sh first"
  exit 99
fi

FAIL=0
pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; }
fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; FAIL=$((FAIL+1)); }

# Pull the captured ids and shas. The state file format is one
# "<variant> <key> <value>" triple per line.
get_state() {
  awk -v variant="$1" -v key="$2" '$1==variant && $2==key {print $3; exit}' "$STATE"
}

PASS_LAND_ID=$(get_state pass land_id)
PASS_SHA_A=$(get_state pass sha_a)
PASS_SHA_B=$(get_state pass sha_b)
FAIL_LAND_ID=$(get_state fail land_id)
FAIL_SHA_A=$(get_state fail sha_a)
FAIL_SHA_B=$(get_state fail sha_b)

echo "== Lander HEAD-moved assertions =="
echo "  pass: land=$PASS_LAND_ID sha_a=${PASS_SHA_A:0:8} sha_b=${PASS_SHA_B:0:8}"
echo "  fail: land=$FAIL_LAND_ID sha_a=${FAIL_SHA_A:0:8} sha_b=${FAIL_SHA_B:0:8}"

extract_block_reason() {
  local task_id="$1"
  hermes kanban show "$task_id" --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    for e in d.get('events', []):
        if e.get('kind') == 'blocked':
            payload = e.get('payload') or {}
            print(payload.get('reason', ''))
            break
except Exception:
    pass
"
}

# ── PASS variant ────────────────────────────────────────────────────────────

PASS_REASON=$(extract_block_reason "$PASS_LAND_ID")
echo "  pass reason: $PASS_REASON"

if [[ -z "$PASS_REASON" ]]; then
  fail "1a. PASS variant emitted no block event on $PASS_LAND_ID"
else
  expected_old="${PASS_SHA_A:0:8}"
  expected_new="${PASS_SHA_B:0:8}"
  if echo "$PASS_REASON" | grep -qE "HEAD moved ${expected_old}.${expected_new}"; then
    pass "1a. PASS variant block reason includes HEAD moved ${expected_old}→${expected_new}"
  else
    fail "1a. PASS variant missing 'HEAD moved ${expected_old}→${expected_new}' (got: $PASS_REASON)"
  fi

  if echo "$PASS_REASON" | grep -qE 'target test passes at HEAD; orchestrator must reconcile attribution'; then
    pass "1b. PASS variant uses verbatim block-reason template"
  else
    fail "1b. PASS variant reason did not match SKILL template (got: $PASS_REASON)"
  fi
fi

# ── FAIL variant ────────────────────────────────────────────────────────────

FAIL_REASON=$(extract_block_reason "$FAIL_LAND_ID")
echo "  fail reason: $FAIL_REASON"

if [[ -z "$FAIL_REASON" ]]; then
  fail "2a. FAIL variant emitted no block event on $FAIL_LAND_ID"
else
  expected_old="${FAIL_SHA_A:0:8}"
  expected_new="${FAIL_SHA_B:0:8}"
  if echo "$FAIL_REASON" | grep -qE "HEAD moved ${expected_old}.${expected_new}"; then
    pass "2a. FAIL variant block reason includes HEAD moved ${expected_old}→${expected_new}"
  else
    fail "2a. FAIL variant missing 'HEAD moved ${expected_old}→${expected_new}' (got: $FAIL_REASON)"
  fi

  if echo "$FAIL_REASON" | grep -qE 'target test still failing at HEAD; substrate race or work lost'; then
    pass "2b. FAIL variant uses verbatim block-reason template"
  else
    fail "2b. FAIL variant reason did not match SKILL template (got: $FAIL_REASON)"
  fi
fi

# ── Banned-phrase check (SKILL § HEAD moved protocol) ───────────────────────

BANNED=(
  "the fix is already at HEAD via"
  "another worker committed"
  "my fix was bundled into"
  "mega-commit absorbed"
  "working tree is clean because"
)
banned_hit=0
for phrase in "${BANNED[@]}"; do
  for reason in "$PASS_REASON" "$FAIL_REASON"; do
    if echo "$reason" | grep -Fq "$phrase"; then
      fail "3. banned-phrase regression: '$phrase' in reason: $reason"
      banned_hit=$((banned_hit+1))
    fi
  done
done
if [[ "$banned_hit" == 0 ]]; then
  pass "3. no banned phrases (hallucination guardrail intact)"
fi

echo
if [[ "$FAIL" == "0" ]]; then
  echo -e "\033[32mAll lander HEAD-moved assertions passed.\033[0m"
  echo "Protects skills/dev-team/land-the-plane/SKILL.md §HEAD moved protocol."
else
  echo -e "\033[31m$FAIL assertion(s) failed.\033[0m"
fi
exit "$FAIL"
