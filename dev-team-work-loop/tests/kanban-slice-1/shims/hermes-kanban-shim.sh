#!/usr/bin/env bash
# bin/hermes shim for the Slice 1 happy-path fixture.
#
# Why this exists:
#   Slice 1 is a wiring test, not a model-speed test. The doc author for
#   yesterday's session called this out explicitly:
#     "shim the slow LLM workers (stack-detect, health-check) so they
#      complete in seconds. ... matches the spirit of Slice 1 (test
#      wiring, not local-model speed)"
#   We extend that to all 5 dev-team workers — local LLM throughput on
#   the current rig (P40 + devstral, 1-2 min/turn) is too slow + memory-
#   tight for end-to-end acceptance. With shims, the dispatcher still
#   drives everything; we just bypass the LLM bodies.
#
# How it works:
#   This shim is installed at $ROOT/bin/hermes (which precedes the real
#   hermes on PATH). The dispatcher invokes us as:
#     hermes -p <profile> --skills kanban-worker --skills <dev-team-skill> chat -q "work kanban task <id>"
#   plus env vars HERMES_KANBAN_TASK / HERMES_KANBAN_WORKSPACE / etc.
#
#   We detect the dev-team skill in $@, and short-circuit each one with
#   the canned outcome that real worker would have produced. For non-
#   shimmed invocations (e.g. `hermes kanban complete` calls from this
#   shim itself), we exec the real binary at $REAL_HERMES.

set -uo pipefail

REAL_HERMES=/home/bob/.local/bin/hermes
TASK_ID="${HERMES_KANBAN_TASK:-}"
WORKSPACE="${HERMES_KANBAN_WORKSPACE:-}"

# Detect which dev-team skill is bundled in args
DEV_SKILL=""
for arg in "$@"; do
  case "$arg" in
    dev-team/stack-detect)         DEV_SKILL=stack-detect;         break ;;
    dev-team/health-fix)           DEV_SKILL=health-fix;           break ;;
    dev-team/pi-dispatcher)        DEV_SKILL=pi-dispatcher;        break ;;
    dev-team/cross-check)          DEV_SKILL=cross-check;          break ;;
    dev-team/land-the-plane)       DEV_SKILL=land-the-plane;       break ;;
    dev-team/deep-research-bridge) DEV_SKILL=deep-research-bridge; break ;;
    dev-team/story-rewrite)        DEV_SKILL=story-rewrite;        break ;;
    dev-team/story-test-review)    DEV_SKILL=story-test-review;    break ;;
    dev-team/infra-fix)            DEV_SKILL=infra-fix;            break ;;
    dev-team/prereq-builder)       DEV_SKILL=prereq-builder;       break ;;
    dev-team/email-handler)        DEV_SKILL=email-handler;        break ;;
    dev-team/support-concierge)    DEV_SKILL=support-concierge;    break ;;
    dev-team/error-fix)            DEV_SKILL=error-fix;            break ;;
  esac
done

# Not a recognized dev-team kanban-worker bootstrap → fall through
if [[ -z "$TASK_ID" || -z "$DEV_SKILL" ]]; then
  exec "$REAL_HERMES" "$@"
fi

# Pull bd_id / worktree / test_file from the task body. The kanban show JSON
# nests the task fields under a "task" key — d['task']['body'].
BODY=$("$REAL_HERMES" kanban show "$TASK_ID" --json 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); t=d.get('task',d); print(t.get('body',''))" 2>/dev/null)
WORKTREE=$(echo "$BODY" | grep -oE 'worktree=\S+' | head -1 | cut -d= -f2)
BD_ID=$(echo    "$BODY" | grep -oE 'bd_id=\S+'    | head -1 | cut -d= -f2)
TEST_FILE=$(echo "$BODY" | grep -oE 'test_file=\S+' | head -1 | cut -d= -f2)
[[ -z "$WORKTREE" ]] && WORKTREE="$WORKSPACE"
[[ -z "$WORKTREE" ]] && WORKTREE=/tmp/hermes-kanban-slice1

cd "$WORKTREE" 2>/dev/null || cd /tmp/hermes-kanban-slice1

case "$DEV_SKILL" in
  stack-detect)
    "$REAL_HERMES" kanban complete "$TASK_ID" \
      --summary "stack-detect (shim): vitest TypeScript project" \
      --metadata '{"test_single_cmd":"npx vitest run","test_cmd":"npx vitest run","build_cmd":"npx tsc --noEmit","lint_cmd":"true","tsc_cmd":"npx tsc --noEmit"}'
    ;;

  health-fix)
    "$REAL_HERMES" kanban complete "$TASK_ID" \
      --summary "health-fix (shim): no errors found" \
      --metadata '{"outcome":"PASS"}'
    ;;

  pi-dispatcher)
    # Slice 2 fail-then-succeed mode: HERMES_SHIM_FAIL_FIRST=N means block
    # the first N spawns of this task. We count BLOCKED events on this task
    # (not the runs list — that includes the currently-open run, off-by-one).
    # Default 0 = always succeed (Slice 1 behavior).
    FAIL_FIRST="${HERMES_SHIM_FAIL_FIRST:-0}"
    BLOCK_COUNT=$("$REAL_HERMES" kanban show "$TASK_ID" --json 2>/dev/null \
      | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(sum(1 for e in d.get('events', []) if e.get('kind') == 'blocked'))
except: print(0)
" 2>/dev/null || echo 0)
    if [[ "$BLOCK_COUNT" -lt "$FAIL_FIRST" ]]; then
      # Block — let the reactive watcher decide the next strategy.
      # HERMES_SHIM_BLOCKER_TYPE controls which classification the shim emits
      # (default HARD_PROBLEM = Slice 2 behavior — routes to deep-research-bridge).
      # Other values exercise the Slice 2.5 branches: STORY_AMBIGUITY,
      # TEST_MISMATCH, MISSING_DEPENDENCY, INFRA. The watcher parses the
      # `BLOCKER_TYPE=X` token from the block reason to route.
      BLOCKER_TYPE="${HERMES_SHIM_BLOCKER_TYPE:-HARD_PROBLEM}"
      ATTEMPT=$((BLOCK_COUNT + 1))
      "$REAL_HERMES" kanban block "$TASK_ID" \
        "BLOCKER_TYPE=$BLOCKER_TYPE pi-dispatcher (shim): tests still failing on attempt $ATTEMPT — escalate"
      exit 0
    fi

    # Invoke bin/pi shim (which writes src/add.ts and emits a pi-shim.log line —
    # that's what assertion 8 checks for).
    if [[ -x "$WORKTREE/bin/pi" ]]; then
      ("$WORKTREE/bin/pi" 2>&1 || true) | tail -5
    elif command -v pi >/dev/null 2>&1; then
      (pi 2>&1 || true) | tail -5
    fi
    HEAD_SHA=$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null || echo "")
    SUCCESS_ATTEMPT=$((BLOCK_COUNT + 1))
    "$REAL_HERMES" kanban complete "$TASK_ID" \
      --summary "pi-dispatcher (shim): wrote src/add.ts via Pi (attempt $SUCCESS_ATTEMPT)" \
      --metadata "{\"head_sha\":\"$HEAD_SHA\",\"bd_id\":\"$BD_ID\",\"test_file\":\"$TEST_FILE\",\"attempt\":$SUCCESS_ATTEMPT}"
    ;;

  deep-research-bridge)
    # Slice 2 escalation strategy (HARD_PROBLEM): wraps scripts/escalator.py
    # in production. For the test fixture, emit canned research findings so
    # we don't actually run the multi-tier chain (which would call real LLMs).
    "$REAL_HERMES" kanban complete "$TASK_ID" \
      --summary "deep-research-bridge (shim): canned findings — root cause is X, suggest approach Y" \
      --metadata "{\"bd_id\":\"$BD_ID\",\"phase_reached\":6,\"result\":\"PASS\",\"approaches_tried\":[\"different-prompt\",\"web-research\",\"deepseek-r1\"],\"next_nudge\":\"apply approach Y on the next attempt\"}"
    ;;

  story-rewrite)
    # Slice 2.5 branch (STORY_AMBIGUITY): BMAD-SM rewrites the story spec
    # so the impl agent has unambiguous acceptance criteria. In production,
    # invokes a `bmad-sm` profile to read the original story + write a
    # corrected version. For the fixture, emit canned rewritten content.
    "$REAL_HERMES" kanban complete "$TASK_ID" \
      --summary "story-rewrite (shim): rewrote story with explicit AC" \
      --metadata "{\"bd_id\":\"$BD_ID\",\"original_ambiguity\":\"AC mentions 'add' but test expects integer math vs floating point\",\"rewritten_ac\":\"add(a,b) returns a+b for all numeric inputs (int and float)\"}"
    ;;

  story-test-review)
    # Slice 2.5 branch (TEST_MISMATCH): pi-quinn reviews the test file to
    # decide whether the test is correct. In production, invokes Quinn with
    # bmad-code-review-acceptance against the test file. For the fixture,
    # emit a canned finding (the test is fine, the impl was wrong).
    "$REAL_HERMES" kanban complete "$TASK_ID" \
      --summary "story-test-review (shim): test reviewed — test is correct, impl needs fix" \
      --metadata "{\"bd_id\":\"$BD_ID\",\"test_file\":\"$TEST_FILE\",\"test_correctness\":\"VALID\",\"finding\":\"test correctly asserts add(a,b)==a+b; impl should not skip the case for negatives\"}"
    ;;

  infra-fix)
    # Slice 2.5 branch (INFRA): hermes-health attempts an automated infra
    # fix (npm install, restart service, etc.) for known infra issues. In
    # production, runs deterministic shell helpers. For the fixture, emit
    # canned success metadata.
    "$REAL_HERMES" kanban complete "$TASK_ID" \
      --summary "infra-fix (shim): re-ran npm install, dependencies resolved" \
      --metadata "{\"bd_id\":\"$BD_ID\",\"fix_kind\":\"missing-module\",\"fix_applied\":true,\"diagnostic\":\"node_modules was incomplete; re-installed\"}"
    ;;

  prereq-builder)
    # Slice 2.5 branch (MISSING_DEPENDENCY): builds a required prerequisite
    # before the impl can proceed. In production, this is a real story-shape
    # task (e.g. "build the auth middleware first"). For the fixture, emit
    # canned built-the-thing metadata.
    "$REAL_HERMES" kanban complete "$TASK_ID" \
      --summary "prereq-builder (shim): built the missing helper module" \
      --metadata "{\"bd_id\":\"$BD_ID\",\"prereq_kind\":\"helper-module\",\"prereq_built\":true,\"artifacts\":[\"src/lib/util.ts\"]}"
    ;;

  email-handler)
    # Sidecar runtime (FR-P4.7): inbound email handler. In production,
    # reads Postmark payload, drafts reply, emits via Resend. For the
    # fixture, emit canned auto-resolution metadata.
    "$REAL_HERMES" kanban complete "$TASK_ID" \
      --summary "email-handler (shim): support email auto-resolved" \
      --metadata "{\"classification\":\"support\",\"outcome\":\"AUTO_RESOLVED\",\"draft_text\":\"Thanks for reaching out — your account has been updated. Reply if any issue persists.\",\"resend_message_id\":\"shim-msg-$$\"}"
    ;;

  support-concierge)
    # Sidecar runtime (FR-P4): chat-widget support. In production, pulls
    # user context via app HTTP API + matches against domain skills.
    # For the fixture, demonstrate two outcomes based on
    # HERMES_SHIM_SUPPORT_OUTCOME env var: AUTO_RESOLVED (default) or
    # ESCALATED (kanban_block to operator).
    SUPPORT_OUTCOME="${HERMES_SHIM_SUPPORT_OUTCOME:-AUTO_RESOLVED}"
    if [[ "$SUPPORT_OUTCOME" == "ESCALATED" ]]; then
      "$REAL_HERMES" kanban block "$TASK_ID" \
        "support-concierge (shim): novel issue, no skill match — escalating to operator review"
    else
      "$REAL_HERMES" kanban complete "$TASK_ID" \
        --summary "support-concierge (shim): chat resolved via skill match" \
        --metadata "{\"intent\":\"how-to\",\"outcome\":\"AUTO_RESOLVED\",\"reply_text\":\"To do X, go to Settings → Y → Z. Let me know if that works!\",\"satisfaction_pending\":true}"
    fi
    ;;

  error-fix)
    # Sidecar runtime (FR-P3): production error remediation. In
    # production, classifies + matches skill + applies fix + verifies.
    # For the fixture, demonstrate two outcomes based on
    # HERMES_SHIM_ERROR_OUTCOME env var: AUTO_FIXED (default — known
    # skill match) or NO_MATCH (escalate to deep-research-bridge).
    ERROR_OUTCOME="${HERMES_SHIM_ERROR_OUTCOME:-AUTO_FIXED}"
    if [[ "$ERROR_OUTCOME" == "NO_MATCH" ]]; then
      "$REAL_HERMES" kanban block "$TASK_ID" \
        "BLOCKER_TYPE=HARD_PROBLEM error-fix (shim): no matching skill — escalate to deep-research"
    else
      "$REAL_HERMES" kanban complete "$TASK_ID" \
        --summary "error-fix (shim): TransientAPI error remediated by skill" \
        --metadata "{\"error_class\":\"TransientAPI\",\"skill_matched\":\"transient-api-retry-with-backoff\",\"outcome\":\"AUTO_FIXED\",\"remediation_diff\":\"retried with exponential backoff, succeeded on attempt 2\",\"regression_check\":\"PASSED\"}"
    fi
    ;;

  cross-check)
    HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
    LOG=/tmp/cross-check-$$.log
    npx vitest run "$TEST_FILE" 2>&1 | tee "$LOG"
    VITEST_EXIT=${PIPESTATUS[0]}
    if [[ "$VITEST_EXIT" == "0" ]]; then
      mkdir -p "$WORKTREE/.hermes/sessions"
      echo "PASS $HEAD_SHA" > "$WORKTREE/.hermes/sessions/$BD_ID.test-result"
      "$REAL_HERMES" kanban complete "$TASK_ID" \
        --summary "cross-check (shim): tests passed" \
        --metadata "{\"outcome\":\"VERIFIED\",\"head_sha\":\"$HEAD_SHA\",\"bd_id\":\"$BD_ID\"}"
      rm -f "$LOG"
    else
      "$REAL_HERMES" kanban block "$TASK_ID" \
        "tests failed under cross-check shim (vitest exit=$VITEST_EXIT, log=$LOG)"
    fi
    ;;

  land-the-plane)
    # Idempotency: only stage + commit if HEAD message doesn't already match
    HEAD_MSG=$(git log -1 --pretty=%B 2>/dev/null)
    if ! echo "$HEAD_MSG" | grep -q "fix($BD_ID):"; then
      git add src/ 2>&1 | head -3 || true
      git -c user.email=test@test -c user.name=test commit \
        -m "fix($BD_ID): add() implementation" 2>&1 | head -5 || true
    fi
    HEAD_SHA=$(git rev-parse HEAD)

    # Source-changed pre-check: HEAD must touch a src/ file
    if ! git show --stat HEAD --diff-filter=AM 2>/dev/null | grep -qE '\bsrc/'; then
      "$REAL_HERMES" kanban block "$TASK_ID" \
        "source-changed pre-check failed: HEAD has no src/ changes"
      exit 0
    fi

    # Per-commit Quinn review (delegates to bin/pi shim, which prints APPROVED
    # when invoked with the Quinn flags)
    if [[ -x "$WORKTREE/bin/pi" ]]; then
      QUINN_OUT=$("$WORKTREE/bin/pi" --no-tools --provider ollama-quinn --model deepseek-r1:32b 2>&1 || true)
      if ! echo "$QUINN_OUT" | grep -q "APPROVED"; then
        "$REAL_HERMES" kanban block "$TASK_ID" "Quinn review failed: $QUINN_OUT"
        exit 0
      fi
    fi

    # Idempotency: write .test-result if missing or stale relative to HEAD
    TEST_RESULT_FILE="$WORKTREE/.hermes/sessions/$BD_ID.test-result"
    if [[ ! -f "$TEST_RESULT_FILE" ]] || ! grep -q "$HEAD_SHA" "$TEST_RESULT_FILE"; then
      mkdir -p "$WORKTREE/.hermes/sessions"
      echo "PASS $HEAD_SHA" > "$TEST_RESULT_FILE"
    fi

    # bd close (idempotent)
    BD_STATUS=$(bd show "$BD_ID" --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    i = d[0] if isinstance(d, list) else d
    print(i.get('status','unknown'))
except Exception:
    print('unknown')
" 2>/dev/null)
    if [[ "$BD_STATUS" != "closed" ]]; then
      bd close "$BD_ID" 2>&1 | head -5 || true
    fi

    # bd close mutates .beads/issues.jsonl. Fold that change into the fix
    # commit via amend so the working tree stays clean for assertion 6.
    # Idempotent: if .beads/ has no changes (e.g. on a reclaim re-run),
    # the amend is skipped.
    if [[ -n "$(git status --porcelain .beads/ 2>/dev/null)" ]]; then
      git add .beads/ 2>&1 | head -3 || true
      git -c user.email=test@test -c user.name=test commit \
        --amend --no-edit 2>&1 | head -3 || true
      HEAD_SHA=$(git rev-parse HEAD)
      # Refresh .test-result for the amended HEAD sha.
      mkdir -p "$WORKTREE/.hermes/sessions"
      echo "PASS $HEAD_SHA" > "$TEST_RESULT_FILE"
    fi

    # Push to bare remote (configured in fixture setup). Force-with-lease is
    # needed because the amend rewrites the fix commit's sha, and the bare
    # remote already accepted the pre-amend version.
    git pull --rebase 2>&1 | head -3 || true
    git push --force-with-lease origin HEAD 2>&1 | head -3 || true

    "$REAL_HERMES" kanban complete "$TASK_ID" \
      --summary "land-the-plane (shim): committed, bd closed, pushed" \
      --metadata "{\"head_sha\":\"$HEAD_SHA\",\"bd_id\":\"$BD_ID\"}"
    ;;
esac

exit 0
