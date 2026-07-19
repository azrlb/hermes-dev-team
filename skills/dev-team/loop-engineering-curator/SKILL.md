---
name: loop-engineering-curator
description: >
  Autonomous review and improvement of Hermes drain/loop engineering quality.
  Runs periodically to audit drain prompts, quality gates, logging, and
  process effectiveness. Proposes improvements for Bob's approval.
  Does NOT make changes without approval — researches, reports, recommends.
triggers:
  - "review drain quality"
  - "improve overnight process"
  - "audit loop engineering"
  - "how are drains performing"
  - "check drain health"
dependencies:
  - dev-team/vibe-loop
  - dev-team/bead-execution
version: 1.0.0
author: hermes-agent
tags: [loop-engineering, quality, process-improvement, autonomous, curator]
---

# Loop Engineering Curator

Autonomous quality reviewer for Hermes drain/loop engineering.
You research and propose improvements. Bob approves or rejects.
You do NOT make changes without explicit approval.

## THINK BEFORE ACTING (MANDATORY)

Before ANY fix, action, or change — pause and answer these questions:

1. **What is the ROOT CAUSE?** (not just the symptom)
2. **What is the MATH?** (display sizes, scale factors, dimensions, costs)
3. **What is the CONTEXT?** (where does this output appear? what is the display environment?)
4. **Have I VERIFIED?** (check the output BEFORE showing it to the user)

If you cannot answer all four, STOP and investigate before acting. Speed is not the goal — getting it RIGHT the first time is. Every quick fix that fails wastes the user time and trust.


## When This Runs

- Scheduled review (weekly or on-demand)
- After a drain has a bad night (high failures, low closes)
- When Bob asks "how are drains performing?"
- After any major change to drain prompts or skills

## Review Checklist (run all 5 audits)

### Audit 1: Goal Clarity
For each drain prompt, check:
- [ ] Does it have an explicit goal (not just "work the queue")?
- [ ] Does it have exit conditions (when to stop)?
- [ ] Does it have a priority order (P0 > P1 > P2)?
- [ ] Is the goal achievable in the time slot (1-2 hours)?

**Score:** Each drain gets 0-4. Average across all drains.
**Target:** Average >= 3. Below that, propose rewrites.

### Audit 2: Quality Gates
For each drain, verify:
- [ ] Tests required before commit (bead-execution step 4-5)
- [ ] Quinn review invoked before bead close (Phase 10c)
- [ ] Attestation written (.hermes/sessions/<id>.test-result)
- [ ] Existing test regression check (run ALL tests, not just new)

**Check method:**
```bash
cd /path/to/project
# Check recent closes have attestations
ls -lt .hermes/sessions/*.test-result 2>/dev/null | head -10
# Check if quinn-review was invoked
git log --oneline --since="yesterday" | grep -i "quinn\|review"
# Check if tests were run (look for vitest in commits)
git log --oneline --since="yesterday" | grep -i "test"
```

**Score:** 0-4 per drain. Target: >= 3.
**Critical:** If beads are closing without Quinn review, that's
a P0 finding — escalate to Bob immediately.

### Audit 3: Logging Quality
Check:
- [ ] Do drains produce structured output (not just free text)?
- [ ] Can morning handoff reconstruct what happened from logs?
- [ ] Are failed beads logged with failure reason?
- [ ] Is there a drain summary per time slot?

**Check method:**
```bash
# Check for structured drain logs
ls ~/.hermes/drain-logs/ 2>/dev/null
# Check for attestation files
find /path/to/project -name "*.test-result" -mtime -1
# Check session dumps
ls -lt ~/.hermes/sessions/request_dump_cron_* | head -5
```

**Score:** 0-4. Target: >= 2 (you're at ~1 currently).

### Audit 4: Safety Limits
Check each drain for:
- [ ] Max runtime guidance ("stop after N hours")
- [ ] Max beads per run ("close at most N beads")
- [ ] Retry limit ("if 3 consecutive failures, stop")
- [ ] Token budget awareness ("if context is getting full, wrap up")

**Score:** 0-4. Target: >= 2.

### Audit 5: Process Effectiveness
Measure actual outcomes:
```bash
# Beads closed per drain slot (last 7 days)
# Compare: beads attempted vs beads closed
# Track: test pass rate, quinn review pass rate
# Identify: which time slots are most/least productive
```

#### Backlog Exhaustion & Epic Blockers Check (Updated)
If a drain closed 0 beads, analyze the skipped list:
- **Placeholders:** Are there empty/garbage issues? (e.g. titled "wprl") -> Action: Delete/close them immediately.
- **Epics:** Are there giant Epic tasks that need decomposition? -> Action: Decompose them into highly-specified, ready-to-code child stories to feed the drains.
- **Human-Action/Gated:** Are they waiting on legal, pricing, and visual feedback? -> Keep them blocked, prioritize operator's attention.
- **Assignment Locks:** Are there ready beads assigned to human developers/analysts (e.g. @azrlb) that the drain cannot claim? -> Action: Unassign them or reassign to 'drain' so the automated process can execute them.

**Score:** 0-4. Target: improving trend week-over-week.
```bash
cd /path/to/project
# Count closes per day
git log --since="7 days ago" --oneline | grep -c "close\|CLOSED"
# Count test failures
git log --since="7 days ago" --oneline | grep -i "fix.*test\|test.*fail"
# Check bead status trends
bd status
```

**Score:** 0-4. Target: improving trend week-over-week.

## Output Format

After running all 5 audits, produce a report:

```
LOOP ENGINEERING HEALTH REPORT
Date: YYYY-MM-DD
Period: Last 7 days

AUDIT SCORES (0-4 each):
  1. Goal Clarity:      X/4  [drain-by-drain breakdown]
  2. Quality Gates:     X/4  [findings]
  3. Logging Quality:   X/4  [current state]
  4. Safety Limits:     X/4  [what exists, what's missing]
  5. Process Effectiveness: X/4  [trends]

OVERALL HEALTH: XX/20

TOP 3 FINDINGS:
  1. [Most important issue + proposed fix]
  2. [Second issue + proposed fix]
  3. [Third issue + proposed fix]

RECOMMENDED ACTIONS (require Bob's approval):
  A. [Action 1 — effort level — expected impact]
  B. [Action 2 — effort level — expected impact]
  C. [Action 3 — effort level — expected impact]

DRAIN PERFORMANCE (last 7 days):
  FlowInCash-Core: X beads closed, Y attempted, Z% success
  Crispi-app:      X beads closed, Y attempted, Z% success
  Best slot:       [time] — N beads closed
  Worst slot:      [time] — N beads closed
```

## Improvement Tracking

Maintain a log of approved improvements and their impact:
`~/.hermes/skills/dev-team/loop-engineering-curator/improvement-log.md`

Format:
```
## YYYY-MM-DD: [Improvement Name]
- Problem: [what was wrong]
- Fix: [what was changed]
- Impact: [measured improvement, or "pending measurement"]
- Status: [implemented / pending / reverted]
```

## Critical Finding: Skill Overlap Caused Quality Gate Skip (RESOLVED — 2026-06-28)

**Problem:** Level 2 quality gates (Quinn, Murat, self-review, traceability) were in
bead-execution skill, but drain prompts had their OWN simpler quality gates. Agents
followed the prompt's gates, not the skill's gates. Level 2 was NEVER executed.

**Root Cause:** Two skills handled the same function (quality gates). When skills
overlap, agents follow the prompt over the skill.

**Resolution (2026-06-28):**
1. bead-execution is now the SINGLE SOURCE OF TRUTH for Level 2 gates
2. Removed old quality gates from all 27 drain prompts
3. Added "CODE QUALITY OVER SPEED" emphasis to all drains
4. All drain jobs now load bead-execution skill

**Architecture Rule:** Never create two skills that handle the same function.
If you find yourself adding the same quality gates to multiple places, pick ONE
source of truth and remove the duplicates.

See improvement-log.md for remediation history.

## Escalation Rules

- **Always escalate to Bob:** Quality gate failures (beads
  closing without tests or Quinn review)
- **Always escalate to Bob:** Beads closed that need visual
  sign-off but weren't flagged
- **Report but don't escalate:** Minor goal clarity issues
  (fix in next review cycle)
- **Auto-fix with notification:** Structured logging gaps
  (add logging instructions to drain prompts)

## Integration Points

- **Morning Handoff** can reference this skill's findings
- **Evening Drain Prep** can read the improvement log
- **Bead Execution** skill should be updated based on
  findings (new test failure patterns, new routines)
- **Vibe Loop** phase definitions may need adjustment
  based on process findings
- **Orchestrator Hierarchy** — see orchestrator-prompt
  skill's `references/vibe-loop-model-conflict.md` for
  the unresolved model mismatch between vibe-loop's local
  models and the orchestrator's cloud models

## Constraints

- NEVER modify drain prompts without Bob's approval
- NEVER close or modify beads — that's the drain's job
- NEVER run code or make changes — this is audit-only
- ALWAYS present findings as proposals, not actions
- Keep reports concise — Bob doesn't need 50 pages
