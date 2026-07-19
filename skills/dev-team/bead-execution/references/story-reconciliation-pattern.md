# Story Spec vs Codebase Reconciliation Pattern

When asked "what's left?" or "what's the status?", don't just look at beads.
Do a full reconciliation of story specs against actual code.

## Why

Beads may be closed but code may not exist. Story specs may be stale.
The only truth is the codebase itself.

## Process

1. List all story specs: `ls docs/stories/Story-*.md`
2. For each story, read the spec to understand what should be built
3. Check if the described code/packages/functions exist in the codebase
4. Classify: IMPLEMENTED / PARTIAL / NOT IMPLEMENTED

## Delegation Pattern

Reconciliations are large (50+ stories). Delegate to a subagent:

```python
delegate_task(
    goal="Do a full reconciliation of story specs vs actual implementation.",
    context="Project: {path}\nStory specs: docs/stories/\nCode: packages/*/src/",
    toolsets=["terminal", "file"]
)
```

The subagent reads all specs, checks code exists, classifies each.
Returns summary — no need to do this inline (saves context).

## Classification Rules

- **IMPLEMENTED**: Code exists, matches story spec description, has tests
- **PARTIAL**: Code exists but in different location/language than spec
  (e.g., Python spec but TypeScript implementation)
- **NOT IMPLEMENTED**: Code described in spec does not exist

## Stale Specs vs Missing Code

A "PARTIAL" result usually means the architecture evolved, not that
work is incomplete. Common patterns:

- **Python → TypeScript**: Stories say Python modules, code is TS
  (e.g., Epic 9 RL training: specs say `hermes/python/rl/`,
  actual code in `strategy/src/rl/`)
- **Path divergence**: Stories say `on-device/`, code in `local-model/`
- **Superseded**: Old approach replaced by new platform
  (e.g., Claude SDK replaced by LivingApp-Sidecar)
- **Components built, integration incomplete**: React components exist
  but full wiring/flow not confirmed (check ACs in story spec)

When reconciling, note the REASON for staleness — it tells Bob
whether this is "done differently" vs "not done."

## After Reconciliation: Prioritize Gaps

Bob's preference: "I don't want them in deferred. I wanna get them
all done." When reporting gaps:

1. Classify gaps into tiers (must-do, important, future)
2. Identify which gaps need Bob's decision vs which drains can handle
3. Schedule everything — don't defer unless truly blocked on data
4. Ask Bob to confirm prioritization before scheduling

## When to Use

- Morning handoff: "what's the project status?"
- Sprint planning: "what work remains?"
- User asks: "what's left to do?"
- After major milestone: verify what was actually completed
- User asks: "run reconciliation" or "what actually got done?"
