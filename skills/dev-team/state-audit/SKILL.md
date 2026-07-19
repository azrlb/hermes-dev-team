---
name: state-audit
description: "Reconstruct project state after disruption — forensic investigation from git, sessions, planning docs, and beads"
version: 1.0.0
metadata:
  hermes:
    tags: [recovery, audit, state, git, sessions]
    related_skills: [beads-decomposition, skill-creation-trigger]
---

# State Audit — Reconstructing Project State After Disruption

When the user says "where did we leave off?" or "we had power 
outages and I don't know what was saved," do a forensic 
investigation BEFORE touching any code or beads.

## THINK BEFORE ACTING (MANDATORY)

Before ANY fix, action, or change — pause and answer these questions:

1. **What is the ROOT CAUSE?** (not just the symptom)
2. **What is the MATH?** (display sizes, scale factors, dimensions, costs)
3. **What is the CONTEXT?** (where does this output appear? what is the display environment?)
4. **Have I VERIFIED?** (check the output BEFORE showing it to the user)

If you cannot answer all four, STOP and investigate before acting. Speed is not the goal — getting it RIGHT the first time is. Every quick fix that fails wastes the user time and trust.


## When to Use

- User says "where did we leave off?" or "what's the status?"
- After power outages, crashes, or session disruptions
- Before starting work on a project that hasn't been touched recently
- When user is confused about what exists vs what doesn't
- When beads/planning docs seem out of sync with reality

## The Investigation (do ALL of these, in order)

### 0. Cron Job Health (what ran while you were away)

Before touching code, check which automated jobs ran and which missed:

```bash
# List all jobs — look at last_run_at and last_status
hermes cron list

# Key signals:
# - last_run_at is stale (days old) = computer was off, jobs missed
# - last_status "error" = check last_delivery_error for why
# - last_status "ok" = job ran fine
# - Empty last_run_at = job never ran
```

This tells you whether the overnight drains produced work or if
there's a gap. If drains missed, offer to trigger catch-up runs.

### 0b. Production Health (are live services up?)

Quick check on Railway-deployed services before reporting status:

```bash
curl -s -o /dev/null -w "%{http_code}" https://crispi-app-production.up.railway.app/
curl -s https://livingapp-sidecar-production.up.railway.app/ready
```

A 200 on both means infrastructure is healthy. Report this first —
Bob wants to know if anything is broken before diving into details.

### 1. Git History (what was actually committed)

```bash
# Full log since the last known date
cd /path/to/project && git log --oneline --since="2026-06-22" --all

# With dates for timeline reconstruction
git log --oneline --since="2026-06-22" --format="%h %ai %s" --all

# What files changed
git log --oneline --since="2026-06-22" --name-only --all | grep -v "^[a-f0-9]" | sort -u

# Specific commits of interest
git show <commit-hash> --stat
```

### 2. Session Search (what was discussed/decided)

```bash
# Search for the topic across sessions
session_search(query="topic keywords", limit=5, sort="newest")

# If you find a session, scroll into it for context
session_search(session_id="found-id", around_message_id=12345, window=10)
```

### 3. Planning Documents (what was planned)

Check these directories for decision docs, UX artifacts, PRDs:
- `_bmad-output/planning-artifacts/` — sequencing decisions, UX designs
- `.hermes/sessions/` — test attestations
- `_output/` — reports, harness results

Read the most recent docs to understand the CURRENT plan.

### 4. Beads (what's tracked as work)

```bash
# Current open beads
bd list --status=open

# Full state as JSON
bd list --status=all --json

# Check for stale notes
bd list --status=open --json | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data if isinstance(data, list) else data.get('beads', data.get('items', []))
for i in items:
    notes = i.get('notes','') or ''
    if 'DO NOT' in notes or 'deferred' in notes.lower():
        print(f\"{i.get('id','?')} | STALE: {notes[:100]}\")
"
```

### 5. Code State (what actually exists)

```bash
# Check package structure
ls packages/

# Check for key files mentioned in planning docs
ls packages/ingest/src/adapters.ts
ls packages/cashflow/src/tiered-light-evaluator.ts

# Run tests to see current health
npx vitest run 2>&1 | tail -5
```

### 6. Story Spec Reconciliation (what was planned vs what was built)

For a thorough audit, delegate a reconciliation to a subagent:

```python
delegate_task(
    goal="Reconcile story specs against actual codebase implementation.",
    context="Project: {path}\nStory specs: docs/stories/\nCode: packages/*/src/",
    toolsets=["terminal", "file"]
)
```

See `dev-team/bead-execution/references/story-reconciliation-pattern.md`
for the full pattern. Key insight: "PARTIAL" usually means architecture
evolved (Python→TS, path changes), not work incomplete.

## Presenting Findings — Plain English Blockers Breakdown

When Bob asks about "blocked" issues, do NOT just dump the bd output.
Categorize every blocked/deferred/open bead into three buckets:

**YOURS (need Bob's action):**
  Legal decisions (lawyer, compliance), business decisions (launch timing,
  pricing), recruiting (beta families), account setup (Stripe keys, DNS).

**DEFERRED (intentionally parked, NOT stuck):**
  Items marked ❄ deferred — these are post-beta or future-phase work
  that Bob explicitly told the pipeline to wait on. They're not blockers.

**TECHNICAL (drains can do but need prep):**
  Items that need upstream dependencies, infrastructure work, or
  cross-project coordination before the drains can implement them.

**Why this matters:** `bd status` shows a "blocked" count that may
include deferred items, making it look worse than reality. Always
cross-reference with `bd ready` (actual actionable items) and
`bd list` to see status symbols (○ open, ◐ in_progress, ● blocked,
✓ closed, ❄ deferred).

## Presenting Findings — Report Format

Structure the report as:

```
══════════════════════════════════════════════════════
TIMELINE (what happened when)
══════════════════════════════════════════════════════
[DATE] — [what happened, with commit hashes]

══════════════════════════════════════════════════════
CURRENT STATE — WHAT EXISTS
══════════════════════════════════════════════════════
CLOSED (done): [list]
OPEN (pending): [list]
BLOCKED: [list]

══════════════════════════════════════════════════════
GAPS (what's missing)
══════════════════════════════════════════════════════
[things that should exist but don't]

══════════════════════════════════════════════════════
BOTTOM LINE
══════════════════════════════════════════════════════
[plain-English summary of where things stand]
```

## Pitfalls

- **`tsc --noEmit` times out on large TypeScript codebases.** FlowInCash
  (and similar large projects) can take 3+ minutes for a full typecheck.
  The default terminal timeout is 120s, so it appears to hang or fail.
  Workaround: run in background with `terminal(background=true,
  notify_on_complete=true, timeout=300)` and check the result via
  `process(action='poll')`. Alternatively, typecheck specific directories
  with `npx tsc --noEmit src/api/` to narrow scope. Do NOT keep retrying
  the same command — it won't finish faster the second time.

- **Check which git branch is active before reporting status.** A project
  may be on a feature branch (e.g. `fix/typescript-errors`) from the
  last session. `git status` and `git log` reflect only that branch.
  Run `git branch --show-current` first so the report accurately states
  which branch the code is on. Uncommitted changes on a feature branch
  may represent work-in-progress that was interrupted.

- **`bd status` blocked count is misleading.** It may include deferred
  (❄) items in the blocked count, making the project look more stuck
  than it is. Always cross-reference with `bd ready` (shows actual
  actionable items) and `bd list` (shows individual status symbols).
  The symbols are: ○ open, ◐ in_progress, ● blocked, ✓ closed, ❄ deferred.

- **Session search may return nothing.** Power outages or session 
  compression can lose context. Fall back to git log and planning 
  docs. Don't say "I can't find anything" — use what's available.

- **Beads JSONL may be stale.** The `.beads/issues.jsonl` file is 
  an export from Dolt. Always run `bd list` (which reads Dolt directly) 
  rather than relying on the JSONL file. If `bd dolt pull` fails 
  (no remote), the local Dolt DB is the source of truth.

- **Planning docs may not match beads.** The UX agent (or other 
  planning agents) can produce action items in decision logs that 
  were never filed as beads. Always scan decision logs for 
  "Action: file a bead" items.

- **Don't trust notes fields blindly.** Stale "DO NOT IMPLEMENT" 
  notes from before a re-sequencing decision can block work that 
  should start. Always cross-reference notes against the LATEST 
  sequencing decision doc.

- **Present findings BEFORE acting.** Bob wants to understand the 
  state before making decisions. Don't skip to "let me fix this" — 
  show the timeline and gaps first, then ask what to do.

- **ALWAYS check for existing analysis/reports before starting fresh work (2026-07-09):** Before doing new research, analysis, or planning, check if it was ALREADY done in a prior session. Search session history, check `~/Desktop/` for reports, check `_bmad-output/` for planning artifacts. Bob had a comprehensive LLM model analysis report on his Desktop (`llm-analysis-final-report.md`) that recommended switching from MiMo to Gemini 2.5 Flash. A new session started the same analysis from scratch, losing hours of prior work. The fix: ALWAYS search for existing work FIRST. If a report exists, READ IT before doing new analysis. If a plan exists, CHECK IT before creating a new one. Session search + Desktop check + planning artifacts check should be Step 0 of ANY state audit.

## Example Investigation (2026-06-23)

Bob: "we had power outages, where did we leave off?"

Steps taken:
1. `git log --since="2026-06-22" --format="%h %ai %s"` — found 20+ commits
2. `session_search(query="Phase 1 Phase 2 resequence")` — found morning brief
3. Read UX docs (DESIGN.md, EXPERIENCE.md, .decision-log.md)
4. `bd list --status=all --json` — found 50 beads, all closed (stale JSONL)
5. `bd list --status=open` — found 16 open beads (Dolt was source of truth)
6. Cross-referenced git commits with bead closures
7. Identified 4 missing beads (never filed by UX agent)
8. Presented timeline → filed missing beads → updated stale notes

Result: 4 new beads filed, 7 bead notes updated, 2 commits pushed.
