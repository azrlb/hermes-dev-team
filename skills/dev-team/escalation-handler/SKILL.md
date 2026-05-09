# Escalation Handler

Routes failure classifications from the failure-classifier to the appropriate handler. Goal: get the story DONE — every blocker type has a concrete resolution path.

## Two invocation paths

This skill has two entry paths that share the same recovery ladder:

- **Legacy work-loop path** — called after a story fails 3 attempts and the failure-classifier produces a `blocker` JSON in `bd show {id}`. Inputs come from Beads. See § Legacy work-loop input.
- **Kanban-native path** — called from an `escalate-<task_id>` task spawned by `dev-team/block-watcher`. Inputs come from the blocked task's `kanban_show`. See § Kanban-native invocation.

Both paths fan out into the same § Escalation Ladder below; only the input parsing and the bookkeeping (bd vs kanban) differ. Pick the path based on whether `HERMES_KANBAN_TASK` is set in the environment.

## Legacy work-loop input

Read from Beads issue metadata (`bd show {id} --json`):
```json
{
  "blocker": {
    "blocker_type": "STORY_AMBIGUITY | MISSING_DEPENDENCY | TEST_MISMATCH | HARD_PROBLEM | INFRA",
    "blocker_detail": "specific description",
    "suggested_action": "what should happen",
    "approaches_tried": ["approach 1", "approach 2", "approach 3"]
  }
}
```

## Kanban-native invocation

Spawned by `dev-team/block-watcher` when a sibling task blocks in a tenant whose orchestrator has already completed. Your task title looks like `escalate-<blocked_task_id>` and your body contains:

```
Escalation for blocked task <id>.
blocked_task_id=<id>
blocked_task_title=<title>
block_reason=<verbatim reason from the blocked event>
tenant=<T>
```

### Step 1 — read the blocked task

```python
import os, re
ctx = kanban_show()
body = ctx.get("body", "")
blocked_id = re.search(r'^blocked_task_id=(.+)$', body, re.MULTILINE).group(1).strip()
block_reason = re.search(r'^block_reason=(.+)$', body, re.MULTILINE).group(1).strip()
blocked = kanban_show(blocked_id)
```

Heartbeat before each substantive step.

### Step 2 — classify by matching block_reason against the structured templates

The lander, cross-check, and pi-dispatcher emit terse, factual block reasons (no narrative — see `skills/dev-team/land-the-plane/SKILL.md` § HEAD moved protocol for the no-narrate rule). Match against these templates in priority order:

| Block reason matches… | blocker_type | Recovery branch |
|---|---|---|
| `target test passes at HEAD; orchestrator must reconcile attribution` | **HEAD_MOVED_PASS** | Cherry-pick or amend to attribute the fix to the correct bd_id, then `bd close`. Spawn a `[story-attribute-<id>]` task assigned to `hermes-lander`. |
| `target test still failing at HEAD; substrate race or work lost` | **HEAD_MOVED_FAIL** | Re-spawn `[story-impl-<id>-attempt-N]` (N = next available number). The previous work was lost; redo it. |
| `bd-gate refused close: .test-result missing` (or any cross-check failure pattern) | **VERIFY_MISSING** | Re-spawn `[story-verify-<id>]`. The cross-check upstream failed; redo it. |
| `Quinn REQUEST_CHANGES:` | **QUINN_BLOCK** | Spawn `[story-impl-quinn-fix-<id>-N]` per the Slice 2 pattern. |
| `push failed:` | **PUSH_FAILED** | Retry once with `git pull --rebase` then push; if it fails again, `kanban_block` with `BLOCKER_TYPE=INFRA` so the operator sees it. |
| `BLOCKER_TYPE=STORY_AMBIGUITY ` (or `... ambiguity ...`) | **STORY_AMBIGUITY** | Spawn `[story-rewrite-<id>]` per the Slice 2.5 STORY_AMBIGUITY branch. |
| `BLOCKER_TYPE=TEST_MISMATCH ` | **TEST_MISMATCH** | Spawn `[story-test-review-<id>]` per the Slice 2.5 TEST_MISMATCH branch. |
| `BLOCKER_TYPE=MISSING_DEPENDENCY ` | **MISSING_DEPENDENCY** | Spawn `[prereq-builder-<id>]` per the Slice 2.5 MISSING_DEPENDENCY branch. |
| `BLOCKER_TYPE=INFRA ` | **INFRA** | Spawn `[infra-fix-<id>]` per the Slice 2.5 INFRA branch. |
| `BLOCKER_TYPE=HARD_PROBLEM ` (or default fall-through) | **HARD_PROBLEM** | Spawn `[deep-research-bridge-<id>]` per the Slice 2 HARD_PROBLEM branch. |
| Any non-matching reason | **UNCLASSIFIED** | `kanban_block(reason="escalation-handler: could not classify '<first 80 chars>'; operator review required")`. |

The first matching row wins. Do NOT improvise classifications outside this table — if the reason doesn't match, fall through to UNCLASSIFIED.

### Step 3 — spawn the recovery task

For each classified blocker type, create a free-standing recovery task. **Do NOT call `kanban_link`** with the blocked task as a parent — `blocked` is a non-terminal-but-not-runnable state, so linking would keep the recovery stuck in `todo` forever. Capture the relationship in body + metadata for audit:

```python
recovery = kanban_create(
    title=f"[{recovery_prefix}-{blocked_id}]",
    assignee=recovery_assignee,
    tenant=ctx["task"]["tenant"],
    workspace=blocked.get("task", {}).get("workspace_path", ""),
    skill=recovery_skill,
    body=f"""Recovery for blocked task {blocked_id}.
recovers_blocked_task={blocked_id}
parent_block_reason={block_reason}
bd_id={extract_bd_id_from(blocked)}
worktree={blocked.get("task", {}).get("workspace_path", "")}
test_file={extract_test_file_from(blocked)}
""",
)
```

The `recovery_prefix`, `recovery_assignee`, and `recovery_skill` come from the table above (e.g., `story-impl-attempt-2` / `pi-coder` / `dev-team/pi-dispatcher`). The recovery task's worker reads its `parent_block_reason` from the body to choose its strategy. The original blocked task is left blocked — it's an audit artifact at this point; recovery flows through the new sibling.

### Step 4 — complete your own escalator task

```python
kanban_complete(
    summary=f"escalation-handler: classified as {blocker_type}, spawned {recovery['id']}",
    metadata={
        "blocked_task_id": blocked_id,
        "blocker_type": blocker_type,
        "block_reason": block_reason,
        "recovery_task_id": recovery["id"],
        "recovery_skill": recovery_skill,
    },
)
```

### Idempotency

If a recovery task with the same title prefix already exists in the tenant (any status), skip the spawn and complete with `metadata.outcome="already_recovered"`. The block-watcher's per-block dedupe normally prevents this, but a manual re-trigger or duplicate watcher run could reach here.

### What you do NOT do (kanban-native path)

- ❌ **Modify code**, even to apply an obvious one-line fix. Recovery tasks own that work.
- ❌ **`bd close` or `bd update`.** That's the lander's job after the recovery completes.
- ❌ **Touch the blocked task's status.** Do not unblock; the dispatcher transitions the blocked task back to `ready` automatically when its child recovery completes (per Slice 2's reactive contract).
- ❌ **Spawn more than one recovery per escalator invocation.** One escalator → one recovery task.

## Escalation Ladder

> The branches below describe legacy work-loop bookkeeping (Beads + Telegram). The kanban-native path uses the same five core types via § Kanban-native invocation Step 3, but with `kanban_create` and parent-link bookkeeping in place of `bd dep add` + Telegram. The HEAD_MOVED_*, QUINN_BLOCK, VERIFY_MISSING, and PUSH_FAILED rows in the kanban table above are kanban-only extensions that do not appear in the legacy ladder.

### STORY_AMBIGUITY
**Cause:** Acceptance criteria say X but test expects Y, or spec is unclear.
**Action:**
1. Route story to BMAD for clarification/rewrite
2. Update Beads: `bd update {id} --status=open --notes "Escalated: STORY_AMBIGUITY. BMAD rewrite requested. Detail: {blocker_detail}"`
3. Telegram: "🔄 {id} escalated — story ambiguity. BMAD rewrite queued."

### TEST_MISMATCH
**Cause:** Test may be wrong or testing the wrong thing.
**Action:**
1. Create a new Beads issue for Quinn to review the test:
   `bd create --title "Quinn review: {test_file}" --type=task --priority=1`
2. Link original as dependency: `bd dep add {id} {new_id}` (original depends on review)
3. Update original: `bd update {id} --status=open --notes "Escalated: TEST_MISMATCH. Quinn test review created. Detail: {blocker_detail}"`
4. Telegram: "🧪 {id} escalated — test mismatch. Quinn review issue created."

### MISSING_DEPENDENCY
**Cause:** Needs an endpoint, service, or file that doesn't exist yet.
**Action:**
1. Create prerequisite Beads issue:
   `bd create --title "Prerequisite: {suggested_action}" --type=task --priority=0`
2. Block original on new issue: `bd dep add {id} {new_id}`
3. Update original: `bd update {id} --status=open --notes "Escalated: MISSING_DEPENDENCY. Prerequisite {new_id} created. Detail: {blocker_detail}"`
4. Telegram: "🔗 {id} blocked — missing dependency. Created {new_id} as prerequisite."

### INFRA
**Cause:** Tooling or environment issue, not a code problem.
**Action:**
1. Log the infrastructure diagnostic to Beads: `bd update {id} --notes "INFRA issue: {blocker_detail}. Suggested fix: {suggested_action}"`
2. Attempt automated fix if the issue is recognized (e.g., `npm install` for missing module, restart service)
3. If fix applied, re-queue: `bd update {id} --status=open --notes "INFRA fix applied, re-queued"`
4. If fix unknown, invoke **Deep Research & Rearchitect** (work-loop Step 9b) — infra issues often have documented solutions online. Do NOT escalate to Bob.
5. Telegram (notification only): "🔧 {id} — infra issue: {blocker_detail}. Deep Research investigating."

### HARD_PROBLEM
**Cause:** Task is understood but requires an approach beyond current capability at the default model tier.
**Action:**
1. **Do NOT escalate to Bob** — Bob is not a developer and cannot fix code issues. This is a dead end.
2. **Invoke Deep Research & Rearchitect** (work-loop Step 9b) directly:
   - Pass all context: `blocker_detail`, `approaches_tried`, `suggested_action`
   - Deep Research runs root cause archaeology, web research, assumption challenging, alternative architecture, isolated prototyping, and applies via Opus
3. If Deep Research resolves it → close the issue, continue work-loop
4. If Deep Research fails → update Beads with ALL research findings:
   ```
   bd update {id} --status=open --append-notes "HARD_PROBLEM: Deep Research attempted.
   Root cause: {root_cause_analysis}
   Research findings: {web_search_results}
   Assumptions challenged: {list}
   Alternative approaches tried: {list}
   Prototype results: {pass/fail details}
   Tagged for next session continuation."
   ```
   Tag issue with `needs-deep-research-round-2` so the next session continues from accumulated knowledge, not from scratch.
5. Telegram (notification only, not asking for decision):
   ```
   🔬 {id} — Deep Research attempted. {outcome}.
   Root cause: {one_line_summary}
   Next session will continue from findings.
   ```

## Post-Escalation

After escalation:
- The original issue is always set back to `open` status (never left in `in_progress`)
- Work-loop continues to next ready issue — does not block on escalated stories
- When the escalation is resolved (BMAD rewrites story, dependency is built, test is fixed), the issue becomes `ready` again automatically via Beads dependency tracking

## Audit Trail

Log every escalation to platform.db:
```
action: "escalation_{blocker_type}"
target: {story_id}
detail: { blocker_type, blocker_detail, suggested_action, resolution_path }
```

## Dependencies

- Beads CLI (`bd`) for reading classifications and creating/updating issues
- Telegram for Bob notifications
- failure-classifier Pi extension (produces the input)
- work-loop skill (calls this skill)
