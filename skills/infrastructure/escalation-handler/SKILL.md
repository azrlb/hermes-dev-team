# Escalation Handler

Routes failure classifications from the failure-classifier to the appropriate handler. Goal: get the story DONE — every blocker type has a concrete resolution path.

## Trigger

Called by the work-loop skill after a story fails 3 attempts and the failure-classifier produces a blocker classification.

## Input

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

## Escalation Ladder

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
4. If fix unknown, escalate to Bob via Telegram: "🔧 {id} — infra issue: {blocker_detail}. Suggested: {suggested_action}"

### HARD_PROBLEM
**Cause:** Task is understood but requires an approach beyond current capability.
**Action:**
1. Send Telegram to Bob with full actionable context:
   ```
   🚨 {id} blocked after 3 attempts.
   Blocker: {blocker_detail}
   Approaches tried:
   - {approach_1}
   - {approach_2}
   - {approach_3}
   Suggested: {suggested_action}
   Action needed: clarify approach, adjust test, or defer.
   ```
2. Update Beads: `bd update {id} --status=open --notes "Escalated: HARD_PROBLEM. Awaiting Bob's decision. Detail: {blocker_detail}"`
3. Do NOT auto-retry — Bob decides: rewrite story, adjust test, defer, or manual fix.

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
