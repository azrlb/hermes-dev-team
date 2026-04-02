# Story Implementer

Orchestrates a single BMAD story from handoff to landing. Reads the story via story_read tool, validates, invokes Pi tdd-coder, validates via quinn-validator, and lands.

This is the single-story focused counterpart to work-loop. Use work-loop for batch/queue processing. Use story-implementer when handed a specific story to implement.

## Trigger

- **Telegram:** Bob sends a story file path or Beads ID
- **Work-loop:** Delegates individual story execution here
- **Direct:** `hermes chat -q "implement stories/S2.1-log-drain-receiver.md"`

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `STORY_BUDGET_USD` | `2.00` | Per-story budget cap |
| `APPROVALS_MODE` | `manual` | Landing autonomy: manual, smart, off |

## Steps

### 1. Read Story

Use the Pi `story_read` tool (or parse directly) to extract:
- `story_id`, `title`, `epic`
- `acceptance_criteria` (list of ACs with test references)
- `test_file` (derived from first AC test path)
- `context_files`, `depends_on`, `touches`
- `dev_mode` (autonomous vs interactive)
- `expected_outcome` (pass vs fail for trap stories)

If the story has a Beads issue, read metadata for checkpoints and failed approaches.

### 2. Pre-Flight Validation

| Check | On Fail |
|-------|---------|
| Story file exists and has valid frontmatter | Abort with error |
| Test file exists | Abort — tests must be pre-written |
| All context_files exist | Abort with missing file list |
| Dependencies resolved (if Beads issue) | Skip — blocked |
| expected_outcome is "pass" | If "fail", this is a trap story — expect escalation |

### 3. Determine Model Tier

Read story complexity from Beads metadata `model_tier` field, or classify:
- Simple (utility function, straightforward CRUD): Tier 1-2 (Gemini Flash)
- Standard (new endpoint, service with logic): Tier 3 (Claude Sonnet)
- Complex (architectural, concurrency, multi-file): Tier 4 (Claude Opus)

### 4. Build Context

Assemble the Pi prompt from:
- Story content (full markdown body)
- Test file path
- Checkpoints from prior attempts (if retrying)
- Failed approaches (if retrying) — what NOT to do
- AGENTS.md conventions
- Relevant context_files content

Set environment:
- `STORY_ID={story_id}`
- `STORY_BUDGET_USD={budget}`

### 5. Use Brownfield Scanner

Before invoking Pi, run `brownfield_scan` with keywords from the story title and touches:
- If existing patterns found → include in Pi's context as "follow this pattern"
- If no patterns → note "greenfield implementation"

### 6. Invoke Pi (tdd-coder → quinn-validator chain)

```json
{
  "chain": [
    {
      "agent": "tdd-coder",
      "task": "Story: {story_content}\nTests: {test_file}\nPattern: {brownfield_results}\nCheckpoints: {prior_checkpoints}\nFailed approaches: {failed_approaches}"
    },
    {
      "agent": "quinn-validator",
      "task": "Validate full suite after: {previous}"
    }
  ]
}
```

### 7. Evaluate Result

**tdd PASS + quinn PASS:** → Land the Plane (Step 8)

**tdd FAIL:**
- attempts < 3: Checkpoint to Beads, retry with failed approach context
- attempts >= 3: Run failure-classifier, route to escalation-handler

**quinn FAIL (regression):**
- Pass Quinn's failure output back to tdd-coder for targeted fix
- Max 2 regression fix attempts, then escalate

### 8. Review Diff

Before landing, run `review_diff` with the story file:
- Check all ACs are addressed
- Check conventions are followed
- If issues found, warn but don't block (log to audit)

### 9. Land the Plane

Run `node scripts/land-the-plane.js {story_id}` with appropriate flags:
```bash
node scripts/land-the-plane.js {story_id} \
  --cost {session_cost} \
  --tests {passed}/{total} \
  --duration {seconds}
```

Respect graduated autonomy:
- `manual`: Ask Bob for approval before landing
- `smart`: Auto-land if pattern is graduated, else ask
- `off`: Auto-land, notify only

### 10. Report

Telegram: `"{story_id} PASS | ${cost} | {duration}s | {tests}/{total} | {commit_sha}"`

## Error Handling

- Pi crash: read .result marker file as fallback
- bd CLI failure: log and continue (story still lands via git)
- Push failure: retry once, then alert Bob
- Test timeout: escalate as INFRA

## Dependencies

- Pi subagents: tdd-coder.md, quinn-validator.md
- Pi extensions: story-reader, brownfield-scanner, diff-reviewer, beads-checkpoint, budget-enforcer
- Scripts: land-the-plane.js
- Hermes skills: escalation-handler (on failure)
- Beads CLI (bd)
