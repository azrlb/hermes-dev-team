#!/usr/bin/env bash
# Convenience: run all 3 sidecar runtime scenarios in sequence.
# Total wall-time ~3-5 min (each shimmed scenario takes ~30-60s).

set -uo pipefail

cd "$(dirname "$0")"

SCENARIOS=(EMAIL SUPPORT BUG_FIX)
RESULTS=()

for s in "${SCENARIOS[@]}"; do
  echo ""
  echo "================================================================"
  echo "==  Sidecar runtime: SCENARIO=$s"
  echo "================================================================"

  for tid in $(hermes kanban list --tenant KanbanSidecar --json 2>/dev/null \
        | python3 -c "import json,sys; print('\n'.join(t['id'] for t in json.load(sys.stdin)))" 2>/dev/null); do
    hermes kanban archive "$tid" >/dev/null 2>&1
  done

  if SCENARIO="$s" bash run-sidecar-test.sh > "/tmp/sidecar-${s}.log" 2>&1; then
    if bash assert-sidecar-test.sh > "/tmp/sidecar-${s}-assert.log" 2>&1; then
      RESULTS+=("$s: PASS")
      echo "  ✅ $s PASS"
    else
      RESULTS+=("$s: ASSERT_FAIL")
      echo "  ❌ $s ASSERT_FAIL — see /tmp/sidecar-${s}-assert.log"
    fi
  else
    RESULTS+=("$s: RUN_FAIL")
    echo "  ❌ $s RUN_FAIL — see /tmp/sidecar-${s}.log"
  fi
done

echo ""
echo "================================================================"
echo "==  Sidecar runtime summary"
echo "================================================================"
for r in "${RESULTS[@]}"; do
  echo "  $r"
done

PASS_COUNT=$(printf '%s\n' "${RESULTS[@]}" | grep -c ': PASS' || true)
TOTAL=${#SCENARIOS[@]}
echo ""
echo "  $PASS_COUNT / $TOTAL passed"

[[ "$PASS_COUNT" == "$TOTAL" ]]
