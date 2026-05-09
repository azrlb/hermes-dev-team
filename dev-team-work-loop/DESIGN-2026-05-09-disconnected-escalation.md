# Design — Disconnected Escalation Gap

**Status:** PROPOSAL — not yet implemented
**Date:** 2026-05-09
**Surfaced by:** the 2026-05-08 dev-team eval session (mimo-v2.5-pro vs mimo-v2.5)
**Decision needed before:** the next eval run, or before deploying the dev-team to autonomous 24/7 production work

---

## TL;DR

When a `[story-land]` (or any other) child task **blocks** in the kanban dev-team's per-story sub-graph, **nothing reacts**. The Slice 2 / Slice 2.5 reactive escalation logic only fires while the dev-orchestrator parent task is still in flight. The current eval-runner pattern (and the Slice 1 fixture pattern that inspired it) marks the story-root **`done` immediately after decomposition**, which removes the orchestrator from the graph. After that point, blocked children sit untouched — there is nobody home to read the block reason and pick a recovery branch.

Result observed in the Pro eval: 5 blocked landers, all with hallucinated reasons, none triaged or escalated. The block-watcher loop the runner runs (counting `bd_close >= 10`) is just a polling timer — it doesn't read block reasons or react.

This design proposes a **block-watcher worker** as the cleanest fix.

---

## The gap, in one diagram

```
Today:
   story-root (DONE after decomposition)            ← orchestrator marked done; nobody home
      ├── stack-detect    → done
      ├── health-check    → done
      ├── story-impl      → done
      ├── story-verify    → done
      └── story-land      → BLOCKED                 ← nobody reacts; just sits there
```

What Slice 2 / Slice 2.5 was *supposed* to do:

```
Intended:
   story-root (RUNNING — orchestrator alive)
      ├── stack-detect    → done
      ├── health-check    → done
      ├── story-impl      → done
      ├── story-verify    → done
      └── story-land      → BLOCKED
            ↓
   orchestrator wakes, reads block reason, classifies into 1 of 5 blocker types,
   creates a recovery sibling (e.g. story-impl-quinn-fix-N), continues
```

But "orchestrator alive" doesn't happen with the Slice 1 bypass pattern, which the eval runner inherited. So the intended reactive logic never fires.

---

## Three options

### Option A — keep the orchestrator alive across the sub-graph

Don't mark the story-root `done` after decomposition. Leave it
`running`. When all children reach terminal state, mark it done.

**Mechanic:**
- The dispatcher reclaims a stale claim after 15 min if the orchestrator's heartbeat lapses
- The reclaimed orchestrator wakes up, reads child task states, decides next steps
- This is essentially "polling the orchestrator on a 15-min cycle to react to child blocks"

**Pros:** Single architectural concept (orchestrator owns its sub-graph).
Matches what the SKILL.md docs already describe.

**Cons:**
- 15-min reaction lag is too slow for autonomous production
- Heartbeat / reclaim mechanics weren't designed for this lifecycle
- Burns LLM calls on every orchestrator wake-up cycle, even if no child blocked
- Would require refactoring kanban-decomposition skill to handle being re-spawned mid-graph

**Cost estimate:** 4–6 hours of careful skill rework + dispatcher behavior verification.

### Option B — block-watcher worker (RECOMMENDED)

Add a dedicated watcher task that the runner spawns alongside the
story-root tasks. The watcher's job: poll for blocked tasks in this
tenant, and when it sees one, spawn an `escalate-<task_id>` task
assigned to `dev-orchestrator` with the `dev-team/escalation-handler`
skill (or its kanban-native successor). The orchestrator wakes,
reads the block reason via `kanban_show`, picks a recovery branch
from the 5 known blocker types, and acts.

**Mechanic:**

```
[block-watcher] task (new)
  - assignee: dev-orchestrator (or a new dedicated profile)
  - skill: dev-team/block-watcher (NEW — to be authored)
  - workspace: same as story-root
  - body: "Watch tenant <T> for blocked tasks. For each new block, create
          an escalate-<id> task assigned to dev-orchestrator with the
          escalation-handler skill. Skip blocks that already have an
          escalator. Heartbeat every 30s. Exit when no non-terminal
          tasks remain in tenant."
  - max-runtime: same as runner timeout
```

**Pros:**
- Reaction lag is the watcher's poll interval (e.g. 30 s, configurable)
- Decoupled from any individual story's lifecycle — works across all 10 stories
- Each escalate-* task is a normal kanban task with all the substrate's
  guarantees (heartbeat, retry budget, audit emission)
- Watcher is reusable: same pattern works for the sidecar's runtime
  ops (Epic E-K territory in the LivingApp Sidecar PRD addendum)

**Cons:**
- A new skill (`dev-team/block-watcher`) to author and test
- One extra long-running task per eval run
- Requires the escalation-handler skill to be kanban-aware (currently
  scoped to the legacy work-loop)

**Cost estimate:** 2–3 hours for the watcher skill + a new fixture +
small kanban-aware patch to escalation-handler.

### Option C — runner-side block hook

Cheapest: add a check inside `run-devteam-eval.sh`'s dispatch loop
that, when a NEW block appears, manually creates the escalate-* task.
Eval-only; not part of the dev-team's permanent architecture.

**Pros:** Smallest patch, ~50 lines. Works for the eval framework
immediately.

**Cons:**
- Sidecar production deploys don't run the eval runner — they need a
  proper substrate solution. Option C would have to be re-done as
  Option B for production anyway. Wasted intermediate step.
- Couples eval framework to dev-team escalation logic. Eval framework
  should be substrate-agnostic.

**Cost estimate:** 1 hour. Discouraged because it doesn't generalize.

---

## Recommendation: Option B

Reasons:
1. Cleanest separation of concerns — watcher is its own role, not
   tangled with the orchestrator's decomposition role
2. Same pattern serves the Sidecar's runtime operations (which need
   exactly this when a support-handler or anomaly-investigator blocks)
3. Reaction lag is configurable, not bound to heartbeat reclaim
4. Each escalate-* task is auditable, retryable, dispatchable like
   any other kanban task

---

## Sub-tasks if Option B is chosen

1. **Author `skills/dev-team/block-watcher/SKILL.md`** — body, instructions,
   role boundaries (watcher CANNOT modify code, ONLY creates escalate-*
   tasks); heartbeat every 30 s; idempotency rule (don't double-spawn
   escalators for the same blocked task)
2. **Patch `escalation-handler/SKILL.md`** — add a kanban-aware section:
   when invoked from an escalate-* task, read the blocked task's
   block reason via `kanban_show`, classify into the 5 blocker types
   (extending the list to include "HEAD_MOVED" — see lander hallucination
   fix in `land-the-plane/SKILL.md`), and route to the recovery branch
3. **Update `scripts/run-devteam-eval.sh`** — after creating the 10
   story-roots, also create a `[block-watcher]` task scoped to the
   tenant. The watcher exits when the runner exits
4. **New fixture**: `dev-team-work-loop/tests/kanban-block-watcher/` —
   inject a synthetic "lander blocks with HEAD_MOVED" scenario and
   verify the watcher creates an escalate-* task and the orchestrator
   resolves it
5. **Re-run the auth-security eval** — both Pro and non-Pro — with the
   watcher engaged. Pro's hallucinated blocks should now produce
   escalate-* tasks; the orchestrator's recovery branch should attempt
   re-impl or escalate to operator. Compare scorecards to the
   non-watcher baseline

---

## Constraints / non-goals

- **Don't change Slice 1's semantics.** Slice 1 fixture is the canonical
  "happy path" test. The watcher is opt-in; Slice 1 fixture should not
  spawn it. Only the eval runner and (future) production workflows use it.
- **Don't bypass Quinn.** The watcher creates escalate-* tasks; those
  tasks still go through Quinn at their respective lander steps. The
  watcher itself never commits or modifies code.
- **Don't auto-merge resolutions.** When the orchestrator decides to
  re-impl, the new `story-impl-N` sibling goes through the full
  per-commit Quinn check before landing.

---

## How this connects to the lander hallucination fix

The lander fix (in `land-the-plane/SKILL.md`, 2026-05-09) makes the
lander's block reason **terse and factual** — either "test passes at
HEAD" or "test still failing at HEAD." That's exactly the structured
input the block-watcher's escalation-handler can route on:

| Block reason | Recovery branch |
|---|---|
| `... target test passes at HEAD; orchestrator must reconcile attribution` | Cherry-pick or amend to attribute fix to correct bd_id, then close |
| `... target test still failing at HEAD; substrate race or work lost` | Re-spawn `story-impl` to re-do the work |
| `bd-gate refused close: .test-result missing` | Re-spawn `story-verify` |
| `Quinn REQUEST_CHANGES: ...` | Spawn `story-impl-quinn-fix-N` (Slice 2 pattern) |
| `push failed: ...` | Retry once after `pull --rebase`, then escalate to operator |

So the lander fix and the block-watcher are **two halves of the same
fix**. Lander emits objective signals; watcher routes them; orchestrator
resolves. Without the watcher, the lander's facts go nowhere; without
the lander fix, the watcher would route on hallucinated paragraphs.

Both are needed.
