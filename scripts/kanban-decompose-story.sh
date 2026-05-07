#!/usr/bin/env bash
# kanban-decompose-story.sh
#
# Deterministic decomposer for the dev-orchestrator profile. The orchestrator
# LLM (qwen3:30b) is unreliable at producing exact assignee strings, so the
# orchestrator's main action is to invoke this script — which hardcodes the
# six valid profile names and the parent→child link structure.
#
# Used by: skills/dev-team/kanban-decomposition/SKILL.md
#
# Required env vars:
#   HERMES_TENANT       — kanban tenant (passed through to children)
#   HERMES_KANBAN_TASK  — the story-root task id (set by dispatcher)
#
# Required args (positional):
#   $1 BD_ID            — beads issue id (e.g. KanbanSlice1-zy6)
#   $2 STORY_FILE       — absolute path to story spec markdown
#   $3 TEST_FILE        — absolute path to failing TDD test
#   $4 WORKTREE         — absolute path to the per-epic git worktree
#   $5 EPIC_SLUG        — epic identifier (used in child task titles)
#
# On success, prints JSON to stdout with the five created task ids:
#   {"stack_detect": "t_...", "health_check": "t_...", "story_impl": "t_...",
#    "story_verify": "t_...", "story_land": "t_..."}
#
# Caller pattern from the orchestrator:
#   ids=$(bash $REPO/scripts/kanban-decompose-story.sh "$bd_id" "$story_file" \
#         "$test_file" "$worktree" "$epic_slug")
#   then call kanban_complete with those ids in metadata.task_graph and
#   in created_cards.

set -euo pipefail

if [[ $# -lt 5 ]]; then
  echo "usage: $0 BD_ID STORY_FILE TEST_FILE WORKTREE EPIC_SLUG [TEST_SINGLE_CMD]" >&2
  exit 2
fi

BD_ID="$1"
STORY_FILE="$2"
TEST_FILE="$3"
WORKTREE="$4"
EPIC_SLUG="$5"
# Optional 6th arg: explicit test_single_cmd to override whatever stack-detect
# emits. Embedded in impl/verify/land task bodies so the verifier has an
# authoritative source independent of stack-detect's heuristics. Slice 1 uses
# this to sidestep the known stack-detect bug where Vitest projects get a
# Jest-style --testPathPattern flag.
TEST_SINGLE_CMD="${6:-}"

: "${HERMES_TENANT:?HERMES_TENANT must be set}"

WS="dir:${WORKTREE}"
T="${HERMES_TENANT}"

# ─── 1 of 5: stack-detect ─────────────────────────────────────────────────────
STACK_DETECT_ID=$(hermes kanban create "stack-detect for ${EPIC_SLUG}" \
  --assignee hermes-detector \
  --tenant "$T" \
  --workspace "$WS" \
  --skill dev-team/stack-detect \
  --body "Run dev-team/stack-detect against ${WORKTREE}. Read package.json + config files. Emit metadata.test_single_cmd, metadata.test_cmd, metadata.build_cmd, metadata.lint_cmd, metadata.tsc_cmd on completion so children can read them." \
  --json | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

# ─── 2 of 5: health-check ─────────────────────────────────────────────────────
HEALTH_CHECK_ID=$(hermes kanban create "health-check for ${EPIC_SLUG}" \
  --assignee hermes-health-check \
  --tenant "$T" \
  --workspace "$WS" \
  --skill dev-team/health-fix \
  --body "Run dev-team/health-fix on ${WORKTREE} in scope=blocking-only mode. Complete with metadata.outcome=PASS|PARTIAL|FAIL." \
  --json | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

# ─── 3 of 5: story implementation (parents = stack_detect + health_check) ─────
TSC_LINE=""
[[ -n "$TEST_SINGLE_CMD" ]] && TSC_LINE="test_single_cmd=${TEST_SINGLE_CMD}"

STORY_IMPL_ID=$(hermes kanban create "impl story ${BD_ID}" \
  --assignee pi-coder \
  --tenant "$T" \
  --workspace "$WS" \
  --skill dev-team/pi-dispatcher \
  --parent "$STACK_DETECT_ID" \
  --parent "$HEALTH_CHECK_ID" \
  --body "Implement story ${BD_ID} per spec at ${STORY_FILE}.

bd_id=${BD_ID}
story_file=${STORY_FILE}
test_file=${TEST_FILE}
worktree=${WORKTREE}
${TSC_LINE}

Read AGENTS.md for project conventions. Use the test_single_cmd above (if set) as your authoritative test command — it overrides any value from stack-detect's metadata. Make all tests pass. Do NOT modify the test file." \
  --json | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

# ─── 4 of 5: independent test re-run (parent = story_impl) ────────────────────
STORY_VERIFY_ID=$(hermes kanban create "verify story ${BD_ID}" \
  --assignee hermes-verifier \
  --tenant "$T" \
  --workspace "$WS" \
  --skill dev-team/cross-check \
  --parent "$STORY_IMPL_ID" \
  --body "Re-run the story's test file independently of Pi's claim.

bd_id=${BD_ID}
test_file=${TEST_FILE}
worktree=${WORKTREE}
${TSC_LINE}

If a 'test_single_cmd=' line is present above, use it directly — it is authoritative. Otherwise read parent's metadata.test_single_cmd. Run \${test_single_cmd} ${TEST_FILE}. On PASS, write ${WORKTREE}/.hermes/sessions/${BD_ID}.test-result with: PASS <HEAD-sha>. Complete with metadata.outcome=VERIFIED|MISMATCH|FAIL." \
  --json | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

# ─── 5 of 5: convergent landing (parent = story_verify) ───────────────────────
STORY_LAND_ID=$(hermes kanban create "land story ${BD_ID}" \
  --assignee hermes-lander \
  --tenant "$T" \
  --workspace "$WS" \
  --skill dev-team/land-the-plane \
  --parent "$STORY_VERIFY_ID" \
  --body "Convergent landing for story ${BD_ID}.

bd_id=${BD_ID}
worktree=${WORKTREE}

Read HEAD message + bd status + push state BEFORE acting. Skip any step that's already done. Steps: stage non-test files (explicit list, no git add -A), commit with 'fix(${BD_ID}):' prefix (if not already), write .hermes/sessions/${BD_ID}.test-result if missing, run source-changed pre-check (reject metadata-only commits), run per-commit Quinn (deepseek-r1:32b via 'quinn' provider, --no-tools), bd close, git pull --rebase + git push." \
  --json | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

# ─── Emit JSON manifest ───────────────────────────────────────────────────────
cat <<JSON
{
  "stack_detect": "${STACK_DETECT_ID}",
  "health_check": "${HEALTH_CHECK_ID}",
  "story_impl":   "${STORY_IMPL_ID}",
  "story_verify": "${STORY_VERIFY_ID}",
  "story_land":   "${STORY_LAND_ID}"
}
JSON
