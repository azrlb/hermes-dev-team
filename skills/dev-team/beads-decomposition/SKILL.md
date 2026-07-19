---
name: beads-decomposition
description: "Decompose epic beads into child story beads with UX-informed specs"
version: 1.1.0
metadata:
  hermes:
    tags: [beads, planning, flowincash-core, decomposition]
    related_skills: [dev-team/vibe-loop, bmad-tea]
---

# Beads Decomposition

Breaking an epic bead into actionable child story beads with
proper acceptance criteria, dependencies, and UX-informed specs.

## THINK BEFORE ACTING (MANDATORY)

Before ANY fix, action, or change — pause and answer these questions:

1. **What is the ROOT CAUSE?** (not just the symptom)
2. **What is the MATH?** (display sizes, scale factors, dimensions, costs)
3. **What is the CONTEXT?** (where does this output appear? what is the display environment?)
4. **Have I VERIFIED?** (check the output BEFORE showing it to the user)

If you cannot answer all four, STOP and investigate before acting. Speed is not the goal — getting it RIGHT the first time is. Every quick fix that fails wastes the user time and trust.


## When to Use

- An epic bead says "See child beads" but no children exist
- A new feature area needs work items broken out
- After a sequencing decision (party-mode roundtable) changes the plan

## Steps

### 1. Read the Source Documents

Before writing any beads, read these:
- The sequencing decision doc (e.g. `cashflow-engine-sequencing-decision-*.md`)
- The UX artifacts (EXPERIENCE.md, DESIGN.md, HTML mockups)
- The PRD section covering the feature area
- The architecture doc (ADRs relevant to the stories)

**PITFALL:** Do NOT use old story numbers from previous sequencing.
Always check the sequencing decision doc for the current plan.
Old Sprint 2/3 numbers (1.6, 1.7, 1.8, 1.9, 1.10, 1.11, 1.12, 1.13)
may have been re-assigned to different phases.

### 2. Identify the Child Stories

From the epic description and source docs, list each story.
For each story, determine:
- What it builds (one-sentence summary)
- What FR/ADR it maps to
- What dependencies it has on other stories or Phase 0 work
- What UX design elements it implements

### 3. Write Each Bead

For each child story, create a bead with:

```
Title: Story X.Y — <name> (<FR/ADR references>)

Description should include:
- Phase label (Phase 1 Breadth, Phase 2 Depth, etc.)
- Re-sequencing note if applicable ("RE-SEQUENCED from Sprint N")
- WHAT: one paragraph explaining the feature
- KEY DESIGN PRINCIPLE: quote from UX spec if applicable
- CURRENT STATE: what exists now in the codebase (check with search_files)
- PLAN: numbered implementation steps
- ACCEPTANCE: numbered acceptance criteria (5-8 items)
- DEPENDS ON: specific bead IDs or Phase 0 items
- LABELS: phase-N, epic:bead-id, story:X.Y, fr:FR-N
- TEST: exact vitest/npm test command
```

**PITFALL:** Do NOT copy old descriptions blindly. Verify current
codebase state with `search_files` before writing "CURRENT STATE."

### 4. Update the Epic Bead

The epic bead must:
- Have the correct phase/title (not old Sprint numbers)
- List ALL child bead IDs in the description
- Reference the correct source documents
- Match the current sequencing decision

**CRITICAL:** Verify the epic's child bead references match reality.
Run `bd list --status=open --json` and check that every child ID
listed in the epic actually exists as an open bead.

### 5. Verify and Commit

```bash
# List all open beads — verify child count matches epic
bd list --status=open --json | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data if isinstance(data, list) else data.get('beads', data.get('items', []))
for i in items:
    print(f\"{i.get('id','?')} | P:{i.get('priority','?')} | {i.get('title','?')[:60]}\")
"

# Commit
git add .beads/issues.jsonl
git commit -m "chore(beads): decompose <epic-id> into N child stories"
git push
```

### 5b. Synchronize Existing Beads with Latest Plan (after re-sequencing)

When a planning decision changes the work order (re-sequencing,
priority shift, UX-driven reorder), existing beads MUST be updated:

1. Read the latest sequencing decision doc
2. For EVERY bead in the affected area, check:
   - Does the `notes` field conflict with the new plan?
   - Does the `labels` list reference the wrong epic?
   - Is the title using old story numbers?
   - Are "DO NOT IMPLEMENT" notes still accurate?
3. Update any stale beads with `bd update <id> --notes "..." --title "..."`
4. Commit the synchronization: `git commit -m "chore(beads): sync bead notes/labels with <decision-doc>"`

**This step is NOT optional.** Stale bead notes cause agents to
skip work that should be started, or start work that should wait.
(Discovered 2026-06-23: 7 beads had stale "DO NOT IMPLEMENT NOW"
notes from before the Phase 1/2 re-sequencing, causing confusion
about what was actually buildable.)

### 6. Cross-Check with UX Artifacts

Verify each bead's acceptance criteria reference the correct
UX design elements. If the UX agent created EXPERIENCE.md
sections, each bead should cite which sections it implements.

## Pitfalls

- **Old story numbers:** The most common mistake. Always check
  the sequencing decision doc, not memory or old bead titles.
- **Missing acceptance criteria:** Every bead needs 5-8 numbered
  acceptance criteria. If you can't write 5, the story is too
  big or too vague — split it or clarify.
- **Orphaned epic references:** Epic says "See child beads" but
  children don't exist. Always verify after creating children.
- **Stale CURRENT STATE:** The codebase changes. Always verify
  what exists before writing "ABSENT" or "EXISTS" in descriptions.
- **Stale "DO NOT IMPLEMENT" notes (CRITICAL — caused confusion
  2026-06-23):** When a planning decision changes (re-sequencing,
  priority shift, UX-driven reorder), EXISTING beads can carry
  stale `notes` fields that contradict the new plan. The notes
  say "DO NOT IMPLEMENT NOW" but the sequencing decision says
  "start Phase 1." ALWAYS check the LATEST sequencing decision
  doc before trusting a bead's notes field. If the notes conflict
  with the latest plan, UPDATE the bead notes immediately.
- **Bead labels lag behind re-sequencing:** After a re-sequence,
  beads may still carry old epic labels (e.g. `epic:Core-b0b`
  when they should be `epic:Core-lxm`). Check and update labels
  when re-sequencing.
- **UX design documents may define work not yet filed as beads:**
  After a UX agent creates design artifacts (EXPERIENCE.md,
  DESIGN.md), scan the decision log for explicit "Action: file
  a bead" items. These are often never filed and represent the
  most important work items. (Discovered 2026-06-23: UX agent's
  .decision-log.md line 33 said "file a Phase-0/1 bead for
  bank-transaction translation" — never filed. It was the #1
  priority item.)
- **Verify bead sync after power outages or session breaks:**
  When sessions are interrupted (power outage, context
  compression, etc.), the bead state in Dolt may be out of
  sync with the JSONL export. Always run `bd list --status=open`
  after reconnection to get the true current state. The JSONL
  file can be stale.

## Verification

After decomposition, confirm:
1. Every child bead listed in the epic exists and is open
2. Every child bead has acceptance criteria
3. Dependencies are correctly set (no circular deps)
4. No old story numbers appear in new descriptions
5. Epic title matches current phase (not old Sprint number)
