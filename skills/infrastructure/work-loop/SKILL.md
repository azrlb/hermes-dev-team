# Work Loop

Orchestrates the full story lifecycle: pick work from Beads → validate → invoke Pi subagents → evaluate → land the plane or escalate.

## Trigger

- **Cron:** Periodic `bd ready` check (configurable interval, e.g. every 15 min)
- **Telegram:** Bob sends a Beads ID (e.g. `LivingApp-S2.1`) → execute that specific issue
- **Telegram:** Bob sends `run ready` → execute all ready issues
- **On-demand:** After completing a story, check for next

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `HERMES_MAX_PARALLEL` | `1` | Max concurrent Pi subagent sessions |
| `STORY_BUDGET_USD` | `2.00` | Per-story budget cap (enforced by budget-enforcer extension) |
| `WORK_LOOP_BUDGET_USD` | `10.00` | Per-work-loop-invocation cumulative budget cap |
| `APPROVALS_MODE` | `manual` | Graduated autonomy phase: `manual`, `smart`, or `off` |

## Steps

### 1. Check Queue

If triggered by Telegram with specific ID(s): use those IDs.
Otherwise: run `bd ready --json` and pick up to `HERMES_MAX_PARALLEL` issues.

If no issues are ready, log "No ready issues" and exit.

### 2. Claim

For each issue picked:
```
bd update {id} --claim
```

### 3. Pre-Flight Validation

For each claimed issue, validate from Beads issue metadata before handing to Pi:

| Check | Source | On Fail |
|-------|--------|---------|
| `story_file` exists on disk | issue metadata or description | `bd update {id} --status=open --append-notes "Pre-flight fail: story_file missing"`, skip |
| `test_file` exists on disk | issue metadata or description | `bd update {id} --status=open --append-notes "Pre-flight fail: test_file missing"`, skip |
| Story frontmatter parseable | story file | `bd update {id} --status=open --append-notes "Pre-flight fail: bad frontmatter"`, skip |
| All `context_files` exist | story frontmatter | `bd update {id} --status=open --append-notes "Pre-flight fail: context_file missing"`, skip |

If validation fails, release the claim and skip to next issue.

### 4. Build Context

Read the Beads issue (`bd show {id} --json`) to assemble Pi's task context:
- `story_file` content (the spec)
- `test_file` path (what tests to pass)
- `checkpoints` from metadata (prior progress, if retrying)
- `failed_approaches` from metadata (what NOT to do)
- `budget_usd` from metadata or `STORY_BUDGET_USD` env var
- Set `STORY_ID={id}` env var for Pi extensions

Determine model tier using the 5-tier routing system:
- Read story complexity from issue metadata `model_tier` field if present
- Otherwise use `model-tier-classifier` skill or default to Tier 3 (Claude Sonnet)

### 5. Check Parallel Safety

If running multiple stories in parallel, check for file overlap between context_files:
- Extract `context_files` from each story's frontmatter
- If any files overlap between parallel candidates → run overlapping stories sequentially
- Non-overlapping stories can run in parallel

### 6. Invoke Pi Subagent

**Single story (chain mode):**
```json
{
  "chain": [
    { "agent": "tdd-coder", "task": "Story: {story_content}\nTests: {test_file}\nCheckpoints: {checkpoints}\nFailed approaches: {failed_approaches}" },
    { "agent": "quinn-validator", "task": "Validate full suite after: {previous}" }
  ]
}
```

Set model for tdd-coder based on tier classification. Quinn always uses the default model.

**Multiple stories (parallel mode):**
```json
{
  "tasks": [
    { "agent": "tdd-coder", "task": "Story S2.1: {context}" },
    { "agent": "tdd-coder", "task": "Story S2.3: {context}" }
  ]
}
```
Then run quinn-validator sequentially for each that passed.

### 7. Evaluate Result

**Chain completed (tdd PASS + quinn PASS):**
→ Proceed to Land the Plane (Step 8)

**tdd-coder FAIL:**
- If attempts < 3: Read checkpoint from Beads, include failed approach context, re-invoke tdd-coder with fresh session (full budget)
- If attempts >= 3: Invoke failure-classifier subagent:
  ```json
  { "agent": "failure-classifier", "task": "Analyze 3 failed attempts for {id}:\n{checkpoint_1}\n{checkpoint_2}\n{checkpoint_3}" }
  ```
  Then route to escalation-handler skill with the classification.

**quinn-validator FAIL (regression):**
- Hand regression context back to tdd-coder (new invocation with Quinn's failure output)
- Max 2 regression fix attempts, then escalate as HARD_PROBLEM

### 8. Land the Plane

**Trigger:** Quinn subagent returns PASS on full suite.

**Graduated autonomy gate:**

| Phase | Behavior |
|-------|----------|
| `manual` | Telegram to Bob: "{id} ready to land. Tests pass. [Approve] [Reject] [View Diff]". Wait for approval. |
| `smart` | Auto-land if story matches a graduated skill pattern. Novel stories → ask for approval. |
| `off` | Auto-land. Telegram notification only. |

**Landing sequence (after approval or auto-approve):**
1. **COMMIT** — auto-committer stages non-test files, `git commit`
2. **UPDATE BEADS** — `bd close {id}` with result metadata + commit SHA
3. **PUSH** — `git pull --rebase && bd sync && git push`
4. **DISCOVER** — File new Beads issues for any tech-debt or bugs found during implementation
5. **REPORT** — Telegram: "{id} PASS | ${cost} | {duration} | {tests_passed}/{tests_total}"
6. **NEXT** — Back to Step 1

### 9. Budget Guard

Track cumulative cost across all stories in this work-loop invocation.
If cumulative cost exceeds `WORK_LOOP_BUDGET_USD`, stop picking new stories.
Per-story budget is enforced by the budget-enforcer Pi extension (not this skill).

## Error Handling

- If Pi subagent crashes without returning: read `.result` marker file as fallback
- If `bd` CLI fails: log error, skip issue, continue with next
- If git push fails: retry once with `git pull --rebase`, then alert via Telegram
- Never leave an issue in `in_progress` without a checkpoint — always write status before exiting

## Dependencies

- Pi subagent definitions: `.pi/agents/tdd-coder.md`, `.pi/agents/quinn-validator.md`, `.pi/agents/failure-classifier.md`
- Pi extensions: `beads-checkpoint.ts`, `failure-classifier.ts`, `budget-enforcer.ts`, `auto-committer.ts`
- Hermes skills: `escalation-handler` (for failure routing)
- External: `bd` CLI, `git`, `npx vitest`
