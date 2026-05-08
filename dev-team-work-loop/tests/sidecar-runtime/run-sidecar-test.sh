#!/usr/bin/env bash
# Sidecar runtime acceptance fixture, parametrized by SCENARIO.
#
# Validates the kanban substrate against three LivingApp-Sidecar PRD
# runtime patterns (different scope from build-time dev-team, but same
# substrate):
#
#   SCENARIO=EMAIL   — inbound email auto-handled (PRD §FR-P4.7)
#   SCENARIO=SUPPORT — chat-widget support auto-resolved (PRD §FR-P4)
#   SCENARIO=BUG_FIX — production error auto-remediated (PRD §FR-P3)
#
# Strategy:
#   - One kanban task per scenario, assigned to dev-orchestrator
#     (in production this would be a dedicated profile per role, but
#     for the test the skill name in the task determines behavior via
#     the bin/hermes shim).
#   - The shim short-circuits each skill with canned production-shaped
#     metadata (AUTO_RESOLVED / AUTO_FIXED outcomes).
#   - Dispatcher walks the task to done.
#   - Assertion verifies the right metadata shape was emitted.
#
# Why this matters for the LivingApp ecosystem:
#   The Sidecar PRD describes self-healing (FR-P3), customer support
#   (FR-P4), and growth experiments (FR-P7) as runtime capabilities.
#   These were originally scoped as custom orchestration code. With
#   kanban as the operations substrate, each becomes "create a task,
#   the dispatcher routes it, the right skill handles it, audit row
#   emits, escalation is the same reactive watcher pattern as Slice
#   2 / 2.5." This fixture proves the substrate fits.
#
# Usage:
#   SCENARIO=EMAIL   bash run-sidecar-test.sh
#   SCENARIO=SUPPORT bash run-sidecar-test.sh
#   SCENARIO=BUG_FIX bash run-sidecar-test.sh

set -uo pipefail

SCENARIO="${SCENARIO:-EMAIL}"

case "$SCENARIO" in
  EMAIL)
    SKILL=dev-team/email-handler
    TITLE="inbound email: support@crispi.app forgot password"
    BODY="from=user42@example.com
subject=Forgot my password
body_text=Hi I can't log in, I forgot my password. Can you help?
app_name=crispi
user_id=u_42"
    ;;
  SUPPORT)
    SKILL=dev-team/support-concierge
    TITLE="chat: how do I add a recipe?"
    BODY="session_id=s_abc123
user_id=u_42
app_name=crispi
message_text=How do I add a custom recipe to my pantry?
prior_messages=[]"
    ;;
  BUG_FIX)
    SKILL=dev-team/error-fix
    TITLE="prod error: TransientAPI on Stripe webhook"
    BODY="app_name=fic
error_class=TransientAPI
error_signature=stripe.webhook.timeout.5xx
recent_count=3
sample_log=2026-05-08T01:23:45 ERR stripe webhook timeout (status=502, retry=0)
trace=at processWebhook (src/stripe.ts:42)"
    ;;
  *)
    echo "ERROR: unknown SCENARIO: $SCENARIO" >&2
    echo "Supported: EMAIL, SUPPORT, BUG_FIX" >&2
    exit 2
    ;;
esac

ROOT=/tmp/hermes-kanban-sidecar
rm -rf "$ROOT"
mkdir -p "$ROOT"/{bin,.hermes/sessions}
cd "$ROOT"

echo "$SCENARIO" > .hermes/scenario.txt
echo "$SKILL" > .hermes/expected-skill.txt

# ─── Pi shim — sidecar workers don't actually invoke Pi for these scenarios,
# but we install it for shape-consistency with the other fixtures.
cat > bin/pi <<'SH'
#!/usr/bin/env bash
echo "$(date -Iseconds) ARGS: $*" >> /tmp/hermes-kanban-sidecar/.hermes/pi-shim.log
exit 0
SH
chmod +x bin/pi

# ─── bin/hermes shim — same shared shim as Slices 1/2/2.5 ─────────────────────
SHIM_SRC=/media/bob/C/AI_Projects/hermes-dev-team/dev-team-work-loop/tests/kanban-slice-1/shims/hermes-kanban-shim.sh
cp "$SHIM_SRC" bin/hermes
chmod +x bin/hermes

export PATH="$ROOT/bin:$HOME/.local/bin:$PATH"
export HERMES_TENANT=KanbanSidecar

# ─── Create the sidecar runtime task ──────────────────────────────────────────

TASK_ID=$(hermes kanban create "$TITLE" \
  --assignee dev-orchestrator \
  --tenant "$HERMES_TENANT" \
  --workspace "dir:${ROOT}" \
  --skill "$SKILL" \
  --body "$BODY" \
  --max-runtime 30m \
  --json | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
echo "$TASK_ID" > .hermes/task-id.txt
echo "[run] sidecar task created: $TASK_ID (skill=$SKILL)"

# ─── Polling loop ─────────────────────────────────────────────────────────────

echo "[run] waiting for sidecar task to converge (max 5 min)"
deadline=$(( $(date +%s) + 300 ))
while [[ $(date +%s) -lt $deadline ]]; do
  hermes kanban dispatch 2>&1 | tee -a .hermes/dispatch.log >/dev/null || true

  task_status=$(hermes kanban show "$TASK_ID" --json 2>/dev/null \
    | python3 -c "
import json, sys
try: print(json.load(sys.stdin)['task'].get('status','unknown'))
except: print('unknown')
")
  echo "[run $(date +%H:%M:%S)] $SCENARIO task status: $task_status"

  case "$task_status" in
    done|blocked|crashed|gave_up|timed_out)
      echo "[run] terminal state reached: $task_status"
      break
      ;;
  esac
  sleep 5
done

echo "[run] dispatcher dragged to completion or timeout. Now run ./assert-sidecar-test.sh"
echo "[run] SCENARIO was: $SCENARIO"
echo "[run] task id was: $TASK_ID"
