#!/usr/bin/env bash
# bin/hermes shim for the kanban-lander-head-moved fixture.
#
# Why this exists:
#   The HEAD-moved protocol added to skills/dev-team/land-the-plane/SKILL.md
#   in commit a05df90 (2026-05-09) is currently text in a SKILL doc — not
#   covered by any automated fixture. This shim mimics the protocol in
#   shell so the fixture can exercise the GUARD shape without invoking a
#   real LLM lander. If the SKILL's banned-phrase list or block-reason
#   templates drift, this shim must be updated to match — that's by
#   design (the parallel implementations document each other).
#
# What this shim does:
#   On `dev-team/land-the-plane` invocation:
#     1. Read the [story-land] task body for bd_id, worktree, test_file.
#     2. Walk parents to find the [story-verify] task; pull head_sha
#        from its run metadata.
#     3. Compare verify_head_sha to current HEAD. If different:
#          a. Run vitest at current HEAD against test_file.
#          b. Block with one of two terse, factual reasons (the SKILL's
#             banned-phrase list applies — never narrate, never speculate).
#          c. Exit 0.
#     4. If sha matches, fall through to a no-op completion — this fixture
#        does not exercise the happy-path land flow (Slice 1 covers that).
#
#   For non-shimmed invocations, exec the real hermes binary.

set -uo pipefail

REAL_HERMES=/home/bob/.local/bin/hermes
TASK_ID="${HERMES_KANBAN_TASK:-}"
WORKSPACE="${HERMES_KANBAN_WORKSPACE:-}"

DEV_SKILL=""
for arg in "$@"; do
  case "$arg" in
    dev-team/land-the-plane) DEV_SKILL=land-the-plane; break ;;
  esac
done

if [[ -z "$TASK_ID" || -z "$DEV_SKILL" ]]; then
  exec "$REAL_HERMES" "$@"
fi

# ─── Read the [story-land] task body ──────────────────────────────────────────

TASK_JSON=$("$REAL_HERMES" kanban show "$TASK_ID" --json 2>/dev/null)
BODY=$(echo "$TASK_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); t=d.get('task',d); print(t.get('body',''))" 2>/dev/null)

WORKTREE=$(echo "$BODY" | grep -oE 'worktree=\S+'  | head -1 | cut -d= -f2)
BD_ID=$(echo    "$BODY" | grep -oE 'bd_id=\S+'     | head -1 | cut -d= -f2)
TEST_FILE=$(echo "$BODY" | grep -oE 'test_file=\S+' | head -1 | cut -d= -f2)
[[ -z "$WORKTREE" ]] && WORKTREE="$WORKSPACE"

# ─── Walk parents to find [story-verify] head_sha ─────────────────────────────

PARENT_IDS=$(echo "$TASK_JSON" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(' '.join(d.get('parents', [])))
except Exception:
    pass
" 2>/dev/null)

VERIFY_HEAD_SHA=""
for pid in $PARENT_IDS; do
  PARENT_JSON=$("$REAL_HERMES" kanban show "$pid" --json 2>/dev/null)
  candidate=$(echo "$PARENT_JSON" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    title = d.get('task', {}).get('title', '')
    if 'story-verify' not in title and 'verify' not in title.lower():
        sys.exit(0)
    for r in d.get('runs', []):
        md = r.get('metadata') or {}
        if 'head_sha' in md:
            print(md['head_sha'])
            break
except Exception:
    pass
" 2>/dev/null)
  if [[ -n "$candidate" ]]; then
    VERIFY_HEAD_SHA="$candidate"
    break
  fi
done

if [[ -z "$VERIFY_HEAD_SHA" ]]; then
  "$REAL_HERMES" kanban block "$TASK_ID" \
    "shim could not locate [story-verify] parent's head_sha — fixture setup error"
  exit 0
fi

# ─── HEAD-moved protocol ──────────────────────────────────────────────────────

CURRENT_HEAD=$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null || echo "")
if [[ -z "$CURRENT_HEAD" ]]; then
  "$REAL_HERMES" kanban block "$TASK_ID" "could not read current HEAD from $WORKTREE"
  exit 0
fi

if [[ "$CURRENT_HEAD" == "$VERIFY_HEAD_SHA" ]]; then
  # No HEAD movement — this fixture doesn't exercise the happy-path land.
  "$REAL_HERMES" kanban complete "$TASK_ID" \
    --summary "shim: HEAD matches verify_head_sha (no protocol needed); fixture only tests the moved branch" \
    --metadata "{\"head_sha\":\"$CURRENT_HEAD\",\"bd_id\":\"$BD_ID\"}"
  exit 0
fi

# HEAD has moved. Run the bug's specific test at current HEAD and let the
# result decide the block reason — never narrate, never speculate.

cd "$WORKTREE"
npx vitest run "$TEST_FILE" --reporter=verbose >/tmp/lander-head-moved-vitest.log 2>&1
VITEST_EXIT=$?
if [[ "$VITEST_EXIT" == "0" ]]; then
  TEST_PASSES=true
else
  TEST_PASSES=false
fi

SHORT_OLD="${VERIFY_HEAD_SHA:0:8}"
SHORT_NEW="${CURRENT_HEAD:0:8}"

if [[ "$TEST_PASSES" == "true" ]]; then
  REASON="HEAD moved ${SHORT_OLD}→${SHORT_NEW}; target test passes at HEAD; orchestrator must reconcile attribution"
else
  REASON="HEAD moved ${SHORT_OLD}→${SHORT_NEW}; target test still failing at HEAD; substrate race or work lost"
fi

"$REAL_HERMES" kanban block "$TASK_ID" "$REASON"
exit 0
