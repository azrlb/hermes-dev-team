---
name: block-watcher
description: Disconnected-escalation watcher. Polls a tenant for blocked tasks; for each new block, spawns an `escalate-<task_id>` task assigned to dev-orchestrator with the dev-team/escalation-handler skill. Idempotent, heartbeat-bounded, debounced exit. Designed by DESIGN-2026-05-09-disconnected-escalation.md (Option B). Required when the story-root is marked done after decomposition (Slice 1 bypass) — without this watcher, blocked children just sit there.
version: 0.1.0
metadata:
  hermes:
    tags: [kanban, dev-team, watcher, escalation, gap-2]
    related_skills: [dev-team/escalation-handler, dev-team/kanban-decomposition, dev-team/land-the-plane]
---

# Block-Watcher — Reactive Escalation for Disconnected Sub-Graphs

> You are a kanban worker on a `[block-watcher]` task. Your job is to bridge the gap left by Slice 1's "mark story-root done after decomposition" pattern: when a child task blocks, nobody in the orchestrator role is alive to react. You poll the tenant, spot new blocks, and create `escalate-<task_id>` tasks that an alive orchestrator handles via `dev-team/escalation-handler`.

## Why this skill exists (read this first)

The Slice 1 fixture and the eval runner both mark each `[story-root]` task **`done` immediately after decomposition** so the dispatcher never tries to re-spawn the orchestrator. That's safe — orchestrators that re-spawn mid-graph have a re-entrancy problem. But it leaves the sub-graph *headless*: the Slice 2 / Slice 2.5 reactive-escalation logic only fires while the orchestrator is alive on a `running` task. With the orchestrator gone, blocked children just sit there.

Observed in the 2026-05-08 eval: 5 of 10 lander tasks blocked with hallucinated reasons. None were triaged. The runner's polling loop only counted `bd close >= 10` and idle-spun until timeout.

This watcher fixes the gap by being a *separate, alive* kanban worker that translates blocks into routable escalator tasks.

## Role boundaries — what you ONLY do

You are the **block-watcher**. Your ONLY tools are `kanban_*`. You do NOT:

- ❌ Modify code, tests, or any file outside the kanban substrate
- ❌ `git`, `bd`, `pi`, or any state-changing tool other than kanban
- ❌ Decide what the recovery should be — you only spawn escalator tasks; the orchestrator (via `dev-team/escalation-handler`) classifies the block reason and picks the recovery branch
- ❌ Modify the blocked task itself (don't unblock, comment, or reassign)
- ❌ Spawn an escalator for a task you've already escalated (idempotency)
- ❌ Spawn an escalator for yourself or another `[block-watcher]` / `escalate-*` task

What you DO:
- ✅ Poll `kanban_list(tenant=...)` on a fixed interval
- ✅ For each newly blocked, non-watcher, non-escalator task without an existing `escalate-<id>` sibling, `kanban_create` an escalator
- ✅ Heartbeat every poll with one-line status
- ✅ Exit cleanly when two consecutive polls show all non-watcher tasks terminal, or when `max_runtime_seconds` elapses

## Liveness — heartbeat every poll

The kanban dispatcher reclaims any task whose claim has been silent for **15 minutes**. The watcher's poll cycle is much shorter (default 30s), so heartbeating every poll is sufficient and trivial:

```python
import os
kanban_heartbeat(
    task_id=os.environ["HERMES_KANBAN_TASK"],
    note=f"poll #{n}: blocked={blocked} terminal={terminal} escalators_spawned={spawned}",
)
```

Good notes give counts and the most recent action. Bad notes: `"still polling"`, empty, sub-second intervals.

## Your job, the loop

You're spawned on a `[block-watcher]` task with body of this shape:

```
Watch tenant <T> for blocked tasks.
tenant=<T>
poll_interval_seconds=30
max_runtime_seconds=5400
```

Defaults if a field is missing: `poll_interval_seconds=30`, `max_runtime_seconds=5400` (90 min). The `tenant` field is required — `kanban_block` if absent.

### On startup

```python
import os, re, time
ctx  = kanban_show()
body = ctx.get("body", "")

m_tenant = re.search(r'^tenant=(.+)$', body, re.MULTILINE)
if not m_tenant:
    kanban_block(reason="block-watcher requires tenant=<T> in body")
    return
tenant = m_tenant.group(1).strip()

poll = int((re.search(r'^poll_interval_seconds=(\d+)', body, re.MULTILINE) or _default(30)).group(1))
maxr = int((re.search(r'^max_runtime_seconds=(\d+)', body, re.MULTILINE)  or _default(5400)).group(1))

self_id = os.environ["HERMES_KANBAN_TASK"]
start   = time.time()
spawned = []           # [(blocked_id, escalator_id), ...]
quiet_polls = 0        # consecutive polls with no non-watcher activity
```

### The poll loop

Each iteration:

1. **Heartbeat** with current counts.
2. **List the tenant.** `tasks = kanban_list(tenant=tenant)`.
3. **Filter blocked tasks** that need escalation:
   - status == "blocked"
   - title does NOT start with `"escalate-"` (don't escalate escalators)
   - skills does NOT contain `"dev-team/block-watcher"` (don't escalate watchers)
   - id != self_id
4. **For each candidate block:** check whether an `escalate-<id>` task already exists in the tenant (any status). Use `kanban_list(tenant=tenant)` results — match `task.title.startswith(f"escalate-{candidate.id}")`. If found, skip (idempotency).
5. **Spawn the escalator** for each new candidate. **Do NOT call `kanban_link`** — a blocked task is non-terminal forever, so linking it as a parent keeps the escalator stuck in `todo`. Use the body/metadata for the audit trail:
   ```python
   block_reason = next(
       (e["payload"]["reason"] for e in candidate["events"] if e["kind"] == "blocked"),
       "<no reason captured>",
   )
   esc = kanban_create(
       title=f"escalate-{candidate['id']}",
       assignee="dev-orchestrator",
       tenant=tenant,
       workspace=candidate.get("workspace_path") or candidate.get("workspace") or "",
       skill="dev-team/escalation-handler",
       body=(
           f"Escalation for blocked task {candidate['id']}.\n"
           f"blocked_task_id={candidate['id']}\n"
           f"blocked_task_title={candidate['title']}\n"
           f"block_reason={block_reason}\n"
           f"tenant={tenant}\n"
       ),
   )
   spawned.append((candidate["id"], esc["id"]))
   ```
6. **Compute exit condition:** count non-watcher, non-self tasks in non-terminal states (`ready`, `todo`, `running`, `triage`). If count is 0, increment `quiet_polls`; otherwise reset to 0. Exit cleanly when `quiet_polls >= 2` (debounce: avoids racing the dispatcher between cycles).
7. **Time budget:** if `time.time() - start >= maxr`, exit cleanly with a "max_runtime reached" summary.
8. **Sleep** `poll_interval_seconds` and loop.

### Exit (clean completion)

```python
kanban_complete(
    summary=f"block-watcher: {len(spawned)} escalators spawned over {int(time.time()-start)}s",
    metadata={
        "tenant": tenant,
        "escalators_created": [{"blocked": b, "escalator": e} for b, e in spawned],
        "polls": poll_count,
        "runtime_seconds": int(time.time() - start),
        "exit_reason": exit_reason,    # "tenant_drained" | "max_runtime"
    },
)
```

### Exit (fatal error)

If `kanban_list` or `kanban_create` raises after retries, `kanban_block(reason=...)` with the exception class + last-line message. Don't loop on a broken substrate.

## Idempotency rules (precise)

- **One escalator per blocked task per tenant lifetime.** The check is title-prefix `escalate-<task_id>`. If a prior watcher run already spawned one and finished, *don't* spawn a duplicate. Block events are append-only — the same task may show multiple blocked events over its life, but the title-uniqueness rule guarantees one escalator regardless.
- **Don't escalate yourself.** Filter `task.id == self_id` and `dev-team/block-watcher` in `task.skills`.
- **Don't escalate escalators.** If an escalator itself blocks, that's a meta-issue for the operator, not a recursive watcher problem. Filter `task.title.startswith("escalate-")`.

## Exit conditions, in priority order

1. **Two consecutive quiet polls** (`nonterm == 0` for both) → `kanban_complete` with `exit_reason="tenant_drained"`. Debounce protects against the dispatcher gap between completing a child and spawning the next.
2. **`max_runtime_seconds` elapsed** → `kanban_complete` with `exit_reason="max_runtime"`. Watcher should never outlive the runner.
3. **Fatal substrate error** → `kanban_block`. Don't try to recover by spinning.

The watcher does NOT exit because all bd issues are closed — that's a different signal (some stories may close without ever blocking, others may stay open with blocks). Bind the exit to kanban tenant state only.

## What this skill does NOT do

- **Decide recovery actions.** That's the escalation-handler's job (kanban-native section). The watcher only routes the signal.
- **Run the escalator inline.** Each `escalate-*` task is dispatched normally by the kanban dispatcher; the orchestrator picks it up.
- **Touch other tenants.** Watcher is tenant-scoped; one watcher per tenant.
- **Provide an opinion on the block reason.** It copies the reason verbatim into the escalator body.

## Profile / spawn convention

The watcher task is spawned by the runner (eval framework) or the orchestrator (production sidecar) with:

```bash
hermes kanban create "[block-watcher] watch <tenant>" \
  --tenant "<tenant>" \
  --workspace "dir:<worktree>" \
  --assignee dev-orchestrator \
  --skill dev-team/block-watcher \
  --body "Watch tenant <tenant> for blocked tasks.
tenant=<tenant>
poll_interval_seconds=30
max_runtime_seconds=5400"
```

Use `dev-orchestrator` as the assignee — that profile already loads kanban tools. A dedicated profile is unnecessary for this poll-only role.

## References

- `dev-team-work-loop/DESIGN-2026-05-09-disconnected-escalation.md` — design rationale (Option B chosen)
- `skills/dev-team/escalation-handler/SKILL.md` — kanban-native section that the spawned escalators invoke; recovery routing table
- `skills/dev-team/land-the-plane/SKILL.md` § HEAD moved protocol — block-reason templates the escalator routes on
- `dev-team-work-loop/tests/kanban-block-watcher/` — fixture exercising this skill against a synthetic blocked-lander scenario
