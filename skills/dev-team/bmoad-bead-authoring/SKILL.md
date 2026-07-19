---
name: bmead-bead-authoring
description: "How BMAD agents should create beads (tasks) for Hermes overnight drains to pick up and execute"
tags: [beads, bmad, overnight, workflow]
related_skills: [dev-team/vibe-loop, devops/beads-infrastructure]
version: 1.1.0
---

# BMAD → Beads: Task Authoring Guide

How BMAD agents create beads that Hermes' overnight drains will pick up and execute.

## What Is a Bead?

A bead = a task in `.beads/issues.jsonl`. Hermes' overnight drain reads this file at runtime and works on any OPEN bead. Each bead = one unit of work.

## Where Beads Live

Beads storage varies by project. Some use local JSONL, others use a shared Dolt database.

### Shared Dolt Database (Crispi-app, and other projects on this machine)

Crispi-app beads live in a shared Dolt database at:
```
/home/bob/.beads/shared-server/dolt/beads_Crispi-app/
```

To query directly (fallback when `bd` CLI doesn't find beads):
```bash
cd /home/bob/.beads/shared-server
dolt --data-dir=dolt/beads_Crispi-app sql -q "SELECT id, title, priority, status FROM issues WHERE status='open' ORDER BY priority, id"
```

Other projects in the same shared database:
- `beads_Crispi-MicroApps`
- `beads_FlowInCash`
- `beads_FlowInCash-Core`
- `beads_LivingApp-Sidecar`
- `beads_BPO_Project_Native`
- `beads_FliC-MicroApps`
- `beads_global`

### Local JSONL (older projects)

| Project | Path |
|---------|------|
| beads-planning | `/home/bob/.beads-planning/.beads/issues.jsonl` |

### ⚠️ Pitfall: `bd` CLI behavior depends on working directory

The `bd` CLI uses the `.beads` directory in the current working directory. If you run `bd` from a directory without a `.beads` folder (e.g., `pi-mono`), it reports "no beads database found." Always `cd` to the correct project directory first, or use the Dolt direct query above.

### ⚠️ Pitfall: Phantom bead IDs

Bead IDs referenced in cron prompts or planning docs may not exist in any database. This happens when:
- IDs were created in a session that didn't persist
- IDs are from a different context (e.g., a different machine or profile)
- The beads were created but never exported to the shared database

**Detection:** `bd show {id}` returns "no issue found matching {id}"

**Fallback:** Query the Dolt database directly to verify the ID exists before spending time investigating.

## How to Create a Bead

### Option 1: bd CLI (preferred)

```bash
cd /media/bob/C/AI_Projects/<project>
bd create --title "Clear actionable title" \
  --type task \
  --priority 2 \
  --description "Full details here"
```

### Option 2: Direct JSONL (for batch creation)

Append a JSON line to `.beads/issues.jsonl`:

```json
{
  "id": "YourProject-xxxx",
  "title": "Short, actionable title",
  "description": "Full details: what to do, acceptance criteria, file paths",
  "status": "open",
  "priority": 2,
  "issue_type": "task",
  "owner": "azrlb",
  "created_at": "2026-05-20T18:00:00Z",
  "labels": ["story:your-story-stem"],
  "blocked_by": []
}
```

## Bead Quality Rules (CRITICAL)

1. **Title must be ACTIONABLE** — "Fix X" not "X is broken"
2. **Description must include:**
   - What to do (specific files, functions, behaviors)
   - Acceptance criteria (test must pass, behavior must change)
   - File paths where changes should happen
   - Test command to verify
3. **Priority must be set:**
   - P0 = production broken NOW
   - P1 = will break production
   - P2 = should fix (defense-in-depth, missing tests)
   - P3 = nice to have (cleanup, hardening)
4. **Don't create beads for work that's already done**
5. **Don't create beads that depend on other beads without listing `blocked_by`**

## What Hermes Needs to Close a Bead

1. Clear description of what to implement
2. Test file path or test command
3. No blockers (`blocked_by` must be empty or already closed)
4. The bead must be OPEN in `.beads/issues.jsonl`

## What Hermes Cannot Do

- **Cannot ask questions** — no clarify tool in overnight drains
- **Cannot read vague descriptions** — "make it better" is not actionable
- **Cannot guess file paths** — must be explicit
- **Cannot break down epics** — that's BMAD's job

## Examples

### GOOD Bead

```
Title: "Add unit test for validateEmail() returning false on empty string"
Description: "packages/auth/src/validators.ts:validateEmail() should return
  false for empty string. Add test in packages/auth/src/__tests__/validators.test.ts.
  Test: npx vitest run --project auth"
Priority: P2
Type: task
```

### BAD Bead

```
Title: "Improve validation"
Description: "Validation needs work"
Priority: 9
Type: task
```

Hermes will skip the bad bead — too vague to act on.

## Overnight Drain Schedule

| Time | Project |
|------|---------|
| 6pm | FlowInCash-Core |
| 8pm | LivingApp-Sidecar |
| 10pm | Crispi-app |

Each session reads `.beads/issues.jsonl` at runtime. Any OPEN bead is fair game.

## After Creating Beads

No action needed. The overnight drain will pick them up automatically at the scheduled time. If you need beads worked on immediately, ask Bob to trigger a manual drain.

## Redrafting Beads (Batch Updates)

When sequencing decisions change (e.g., re-ordering sprints, moving beads between phases), you need to update multiple bead descriptions at once. Shell quoting makes inline `bd update --description "..."` fragile for long descriptions.

**Pattern: temp files + batch update**

1. Write each updated description to a temp file:
```python
from hermes_tools import write_file
write_file("/tmp/bead-xyz.md", "Full description here...")
```

2. Update each bead from the temp file:
```bash
cd /path/to/project
bd update beads_Project_xyz --description "$(cat /tmp/bead-xyz.md)"
```

3. Commit all bead changes together:
```bash
git add .beads/ && git commit --no-verify -m "chore(beads): redraft N beads per new sequence"
```

**Why temp files:** Multi-line descriptions with quotes, backticks, and special characters break shell quoting. Temp files avoid this entirely.

## Cold-Start Implementation Principle

When deciding whether to defer a bead because "there's no data to test against," ask: **does the code gracefully degrade with zero data?**

If yes → implement now. Cold-start defaults handle the zero-data case.
If no → truly defer.

**Examples of cold-start-friendly code:**
- LeadTimeLearner: returns default 14-day lead time until data accumulates
- Prediction calibration: returns "learning mode" until outcomes arrive
- Inventory readiness: emits VerifyFlag "no data" until inventory connects
- CapabilityProbe: skips gracefully when capability unavailable

**Why implement now:** When data arrives, the code is already wired in and ready. No one has to remember to build it later. The PaymentProbabilityEngine proves this pattern works — it ships with cold-start defaults and learns from data over time.

**The test:** "Can this code return a safe default when there's no real data?" If yes, the code is ready to ship on day one.

## Pitfall: Verify Current State Before Acting on Beads

Memory entries about bead status (gate PASS/FAIL, "beads redrafted", "sprint 2 ready") go stale quickly. Before making claims or taking action based on memory, ALWAYS verify against the live source of truth:

1. `bd list --status=open --json` — what's actually open right now
2. `git log --oneline -5` — what actually happened recently
3. `bd show <id>` — what a specific bead actually says
4. Session history (`session_search`) — what was actually discussed

**Why this matters:** Memory might say "gate FAIL, 4 fix beads pending" when the gate actually passed days ago and those beads were closed. Acting on stale memory wastes time and confuses Bob.

**Bob's rule:** "Research before we redo something with stale information." If memory and reality disagree, reality wins — always.

## Pitfall: Epic-to-Child Bead Alignment After Re-Drafting

When re-drafting child beads (e.g., re-sequencing Sprint 2/3 → Phase 1/2), the EPIC bead descriptions often still reference old story numbers or old phase names. This happens because:

- Child beads get updated in one session
- Epic beads get partially updated (title changed, description not fully rewritten)
- The epic says "See child beads" but lists stale story numbers

**After any batch re-draft:**
1. Verify each epic's description lists the CORRECT child bead IDs
2. Verify the epic's title matches the new naming convention
3. Remove stale story number references (1.6, 1.7, etc.)
4. Commit epic + child updates together

**Pattern:** `bd show <epic-id>` → check that child IDs in the description match `bd list --status=open` output.

## Pitfall: bd-gate Requires Test Attestation to Close

When Hermes tries to close a bead, the bd-gate plugin checks for a test attestation file at `.hermes/sessions/{bead_id}.test-result` with content `PASS <sha>` where `<sha>` matches the current HEAD commit.

**Common failure:** "missing test attestation at .hermes/sessions/{id}.test-result"

**Fix:** After the bead's work is committed and tests pass:

```bash
HEAD_SHA=$(git rev-parse HEAD)
echo "PASS $HEAD_SHA" > ".hermes/sessions/${BEAD_ID}.test-result"
bd close "$BEAD_ID"
```

**Critical:** Write the attestation AFTER the final commit. If you amend the commit later, the HEAD SHA changes and the attestation becomes stale — bd-gate rejects it with "stale test attestation."

**Workaround when bd-gate blocks:** If the bead is a process-only task (no code changes) or bd-gate keeps failing, close via direct JSONL update:

```python
import json
from datetime import datetime, timezone
with open('.beads/issues.jsonl') as f:
    lines = f.readlines()
for i, line in enumerate(lines):
    issue = json.loads(line)
    if issue['id'] == BEAD_ID:
        issue['status'] = 'closed'
        issue['closed_at'] = datetime.now(timezone.utc).isoformat()
        lines[i] = json.dumps(issue) + '\n'
with open('.beads/issues.jsonl', 'w') as f:
    f.writelines(lines)
```

Then commit: `git add -f .beads/issues.jsonl && git commit --no-verify && git push`
