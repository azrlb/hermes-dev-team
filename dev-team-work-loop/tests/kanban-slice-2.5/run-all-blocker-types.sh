#!/usr/bin/env bash
# Convenience: run the Slice 2.5 fixture for all 4 blocker types in sequence
# (HARD_PROBLEM is already covered by Slice 2's deep-research-bridge path).
#
# Each run resets state and asserts independently. Total wall-time ~10-15 min.

set -uo pipefail

cd "$(dirname "$0")"

BLOCKER_TYPES=(STORY_AMBIGUITY TEST_MISMATCH INFRA MISSING_DEPENDENCY)
RESULTS=()

for bt in "${BLOCKER_TYPES[@]}"; do
  echo ""
  echo "================================================================"
  echo "==  Slice 2.5 run: BLOCKER_TYPE=$bt"
  echo "================================================================"

  # Archive prior tasks before each run.
  for tid in $(hermes kanban list --tenant KanbanSlice25 --json 2>/dev/null \
        | python3 -c "import json,sys; print('\n'.join(t['id'] for t in json.load(sys.stdin)))" 2>/dev/null); do
    hermes kanban archive "$tid" >/dev/null 2>&1
  done

  if BLOCKER_TYPE="$bt" bash run-blocker-test.sh > "/tmp/slice25-${bt}.log" 2>&1; then
    if bash assert-blocker-test.sh > "/tmp/slice25-${bt}-assert.log" 2>&1; then
      RESULTS+=("$bt: PASS")
      echo "  ✅ $bt PASS"
    else
      RESULTS+=("$bt: ASSERT_FAIL")
      echo "  ❌ $bt ASSERT_FAIL — see /tmp/slice25-${bt}-assert.log"
    fi
  else
    RESULTS+=("$bt: RUN_FAIL")
    echo "  ❌ $bt RUN_FAIL — see /tmp/slice25-${bt}.log"
  fi
done

echo ""
echo "================================================================"
echo "==  Slice 2.5 summary"
echo "================================================================"
for r in "${RESULTS[@]}"; do
  echo "  $r"
done

PASS_COUNT=$(printf '%s\n' "${RESULTS[@]}" | grep -c ': PASS' || true)
TOTAL=${#BLOCKER_TYPES[@]}
echo ""
echo "  $PASS_COUNT / $TOTAL passed"

[[ "$PASS_COUNT" == "$TOTAL" ]]
