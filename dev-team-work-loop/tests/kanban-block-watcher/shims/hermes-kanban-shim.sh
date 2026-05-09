#!/usr/bin/env bash
# bin/hermes shim for the kanban-block-watcher fixture.
#
# Mimics the LLM bodies of two new skills as deterministic shell, so the
# fixture can exercise the watcher → escalator → recovery chain without
# burning real model credits:
#
#   dev-team/block-watcher        — polls tenant, creates escalate-* tasks
#   dev-team/escalation-handler   — classifies block_reason, spawns recovery
#
# These shims are PARALLEL implementations of the SKILL.md docs. If a
# SKILL is updated (e.g. classification table grows, exit conditions
# change), this shim must be updated to match — by design.
#
# Behavior is bounded by env vars so the fixture can drive timing:
#   HERMES_SHIM_WATCHER_MAX_POLLS=4      — cap polls so test exits fast
#   HERMES_SHIM_WATCHER_POLL_SECS=1      — short poll for tests
#   HERMES_SHIM_ESCALATOR_QUIET_OK=1     — escalator exits silently if no match

set -uo pipefail

REAL_HERMES=/home/bob/.local/bin/hermes
TASK_ID="${HERMES_KANBAN_TASK:-}"

DEV_SKILL=""
for arg in "$@"; do
  case "$arg" in
    dev-team/block-watcher)      DEV_SKILL=block-watcher; break ;;
    dev-team/escalation-handler) DEV_SKILL=escalation-handler; break ;;
  esac
done

if [[ -z "$TASK_ID" || -z "$DEV_SKILL" ]]; then
  exec "$REAL_HERMES" "$@"
fi

TASK_JSON=$("$REAL_HERMES" kanban show "$TASK_ID" --json 2>/dev/null)

case "$DEV_SKILL" in

  block-watcher)
    BODY=$(echo "$TASK_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); t=d.get('task',d); print(t.get('body',''))" 2>/dev/null)
    TENANT=$(echo "$BODY" | grep -oE '^tenant=\S+' | head -1 | cut -d= -f2)
    POLL_INTERVAL="${HERMES_SHIM_WATCHER_POLL_SECS:-1}"
    MAX_POLLS="${HERMES_SHIM_WATCHER_MAX_POLLS:-6}"

    if [[ -z "$TENANT" ]]; then
      "$REAL_HERMES" kanban block "$TASK_ID" "block-watcher requires tenant=<T> in body"
      exit 0
    fi

    spawned=()
    quiet=0
    n_polls=0

    while [[ $n_polls -lt $MAX_POLLS ]]; do
      n_polls=$((n_polls+1))
      LIST_JSON=$("$REAL_HERMES" kanban list --tenant "$TENANT" --json 2>/dev/null || echo '[]')

      # All non-watcher, non-escalator titles for idempotency lookup
      EXISTING_ESCALATORS=$(echo "$LIST_JSON" | python3 -c "
import json, sys
try:
    d = json.loads(sys.stdin.read()) or []
    for t in d:
        title = t.get('title', '')
        if title.startswith('escalate-'):
            print(title)
except Exception:
    pass
" 2>/dev/null)

      # Find blocked tasks that need escalators
      CANDIDATES=$(echo "$LIST_JSON" | python3 -c "
import json, sys, os
self_id = os.environ.get('HERMES_KANBAN_TASK','')
try:
    d = json.loads(sys.stdin.read()) or []
    for t in d:
        if t.get('status') != 'blocked': continue
        if t.get('id') == self_id: continue
        title = t.get('title', '')
        if title.startswith('escalate-'): continue
        # Skip other watchers
        skills = t.get('skills') or []
        if 'dev-team/block-watcher' in skills: continue
        print(t['id'])
except Exception:
    pass
" 2>/dev/null)

      for cand in $CANDIDATES; do
        # Idempotency: skip if escalate-<id> already exists
        if echo "$EXISTING_ESCALATORS" | grep -Fq "escalate-$cand"; then
          continue
        fi

        # Pull the most recent block reason from the task's events
        CAND_JSON=$("$REAL_HERMES" kanban show "$cand" --json 2>/dev/null)
        REASON=$(echo "$CAND_JSON" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    reason = ''
    for e in d.get('events', []):
        if e.get('kind') == 'blocked':
            reason = (e.get('payload') or {}).get('reason','')
    print(reason)
except Exception:
    pass
" 2>/dev/null)
        TITLE=$(echo "$CAND_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('task',{}).get('title',''))" 2>/dev/null)
        WORKSPACE=$(echo "$CAND_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('task',{}).get('workspace_path',''))" 2>/dev/null)

        # No kanban_link — blocked task is non-terminal forever; linking
        # would keep the escalator stuck in todo.
        ESC_BODY="Escalation for blocked task ${cand}.
blocked_task_id=${cand}
blocked_task_title=${TITLE}
block_reason=${REASON}
tenant=${TENANT}"
        ESC_ID=$("$REAL_HERMES" kanban create "escalate-${cand}" \
          --tenant "$TENANT" \
          --workspace "dir:${WORKSPACE:-/tmp}" \
          --assignee dev-orchestrator \
          --skill dev-team/escalation-handler \
          --body "$ESC_BODY" \
          --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
        spawned+=("${cand}:${ESC_ID}")
      done

      # Exit-condition probe: count non-watcher, non-self non-terminal tasks.
      NONTERM=$(echo "$LIST_JSON" | python3 -c "
import json, sys, os
self_id = os.environ.get('HERMES_KANBAN_TASK','')
try:
    d = json.loads(sys.stdin.read()) or []
    n = 0
    for t in d:
        if t.get('id') == self_id: continue
        if t.get('status') in ('ready','todo','running','triage'):
            n += 1
    print(n)
except Exception:
    print(-1)
" 2>/dev/null)
      if [[ "$NONTERM" == "0" ]]; then
        quiet=$((quiet+1))
      else
        quiet=0
      fi

      if [[ "$quiet" -ge 2 ]]; then
        break
      fi

      sleep "$POLL_INTERVAL"
    done

    "$REAL_HERMES" kanban complete "$TASK_ID" \
      --summary "block-watcher (shim): ${#spawned[@]} escalator(s) spawned over ${n_polls} polls" \
      --metadata "$(python3 -c "
import json, sys
spawned_arg = sys.argv[1] if len(sys.argv) > 1 else ''
items = []
if spawned_arg:
    for item in spawned_arg.split(' '):
        if ':' in item:
            b, e = item.split(':', 1)
            items.append({'blocked': b, 'escalator': e})
print(json.dumps({
    'tenant': sys.argv[2],
    'escalators_created': items,
    'polls': int(sys.argv[3]),
    'exit_reason': sys.argv[4],
}))
" "${spawned[*]:-}" "$TENANT" "$n_polls" "$([[ $quiet -ge 2 ]] && echo tenant_drained || echo max_polls)")"
    ;;

  escalation-handler)
    BODY=$(echo "$TASK_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); t=d.get('task',d); print(t.get('body',''))" 2>/dev/null)
    BLOCKED_ID=$(echo "$BODY" | grep -oE '^blocked_task_id=\S+' | head -1 | cut -d= -f2)
    BLOCK_REASON=$(echo "$BODY" | sed -n 's/^block_reason=//p' | head -1)
    TENANT=$(echo "$BODY" | grep -oE '^tenant=\S+' | head -1 | cut -d= -f2)

    if [[ -z "$BLOCKED_ID" || -z "$BLOCK_REASON" ]]; then
      "$REAL_HERMES" kanban block "$TASK_ID" \
        "escalation-handler (shim): missing blocked_task_id or block_reason in body"
      exit 0
    fi

    # Classify (subset of the SKILL's table — fixture-relevant rows only).
    BLOCKER_TYPE=""
    RECOVERY_PREFIX=""
    RECOVERY_ASSIGNEE=""
    RECOVERY_SKILL=""

    if echo "$BLOCK_REASON" | grep -qF "target test passes at HEAD; orchestrator must reconcile attribution"; then
      BLOCKER_TYPE=HEAD_MOVED_PASS
      RECOVERY_PREFIX="story-attribute"
      RECOVERY_ASSIGNEE=hermes-lander
      RECOVERY_SKILL=dev-team/land-the-plane
    elif echo "$BLOCK_REASON" | grep -qF "target test still failing at HEAD; substrate race or work lost"; then
      BLOCKER_TYPE=HEAD_MOVED_FAIL
      RECOVERY_PREFIX="story-impl-attempt-2"
      RECOVERY_ASSIGNEE=pi-coder
      RECOVERY_SKILL=dev-team/pi-dispatcher
    else
      "$REAL_HERMES" kanban block "$TASK_ID" \
        "escalation-handler (shim): could not classify '${BLOCK_REASON:0:80}'"
      exit 0
    fi

    # Look up the blocked task's workspace
    WORKSPACE=$("$REAL_HERMES" kanban show "$BLOCKED_ID" --json 2>/dev/null \
      | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('task',{}).get('workspace_path',''))" 2>/dev/null)

    REC_BODY="Recovery for blocked task ${BLOCKED_ID}.
recovers_blocked_task=${BLOCKED_ID}
parent_block_reason=${BLOCK_REASON}
tenant=${TENANT}
worktree=${WORKSPACE}"
    RECOVERY_ID=$("$REAL_HERMES" kanban create "[${RECOVERY_PREFIX}-${BLOCKED_ID}]" \
      --tenant "$TENANT" \
      --workspace "dir:${WORKSPACE:-/tmp}" \
      --assignee "$RECOVERY_ASSIGNEE" \
      --skill "$RECOVERY_SKILL" \
      --body "$REC_BODY" \
      --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

    "$REAL_HERMES" kanban complete "$TASK_ID" \
      --summary "escalation-handler (shim): classified ${BLOCKER_TYPE}, spawned ${RECOVERY_ID}" \
      --metadata "{\"blocked_task_id\":\"${BLOCKED_ID}\",\"blocker_type\":\"${BLOCKER_TYPE}\",\"block_reason\":\"${BLOCK_REASON//\"/\\\"}\",\"recovery_task_id\":\"${RECOVERY_ID}\",\"recovery_skill\":\"${RECOVERY_SKILL}\"}"
    ;;
esac

exit 0
