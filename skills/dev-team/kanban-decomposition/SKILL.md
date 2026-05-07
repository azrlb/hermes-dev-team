---
name: kanban-decomposition
description: Dev-team-specific orchestrator playbook layered on top of the canonical kanban-orchestrator skill. Slice 1 implementation — invokes a deterministic shell helper to create the 5-child sub-graph (stack-detect, health-check, story-impl, story-verify, story-land) with hardcoded valid assignee names. Reactive escalation, Quinn fan-out, and epic-end logic arrive in later slices.
version: 0.2.0
metadata:
  hermes:
    tags: [kanban, dev-team, orchestration, decomposition]
    related_skills: [kanban-orchestrator, kanban-worker, dev-team/pi-dispatcher, dev-team/cross-check, dev-team/land-the-plane]
---

# Kanban Decomposition — Dev-Team Build Half (Slice 1)

> The canonical kanban lifecycle and "decompose, don't execute" rule are auto-loaded into every orchestrator profile via `~/.hermes/skills/devops/kanban-orchestrator/SKILL.md`. This skill is the dev-team-specific playbook for the build half (Phase 10) of the BMAD pipeline.

## Liveness — heartbeat to keep your kanban claim

The kanban dispatcher reclaims any task whose claim has been silent for **15 minutes**. Even though decomposition is mostly fast (one shell-out to the helper script), heartbeat before that call so the dashboard sees liveness:

```python
import os
kanban_heartbeat(
    task_id=os.environ["HERMES_KANBAN_TASK"],
    note="invoking kanban-decompose-story.sh helper",
)
```

If anything in your decomposition takes more than 2 minutes, heartbeat every ~3 minutes with a concrete progress note. Skip heartbeats only if the whole run will finish in under 2 minutes.

## Your job, in three steps

You're spawned as a worker on a `[story-root]` task assigned to the `dev-orchestrator` profile. Your task body looks like:

```
Decompose story <bd-id> for kanban execution.
bd_id=<id>
story_file=<absolute-path>
test_file=<absolute-path>
worktree=<absolute-path>
mode=greenfield|brownfield
```

### Step 1 — parse the body

Call `kanban_show()`, read the body, extract these five values:

- `bd_id` (e.g. `KanbanSlice1-zy6`)
- `story_file` (absolute path)
- `test_file` (absolute path)
- `worktree` (absolute path — the per-epic git worktree the runner pre-created)
- An `epic_slug` derived from `bd_id` (use `bd_id` itself if no other slug is provided)

### Step 2 — invoke the deterministic helper

Run this exact bash command. **Do NOT call `kanban_create` yourself for the children.** The helper hardcodes the six valid profile assignee strings and the parent→child link structure; doing this from prose is a known failure mode (`pi-coder` becomes `impl-worker`, etc., and the dispatcher rejects the tasks as non-spawnable terminal lanes).

```bash
bash /media/bob/C/AI_Projects/hermes-dev-team/scripts/kanban-decompose-story.sh \
  "$bd_id" "$story_file" "$test_file" "$worktree" "$epic_slug"
```

The helper emits JSON to stdout:

```json
{
  "stack_detect": "t_aaaaaaaa",
  "health_check": "t_bbbbbbbb",
  "story_impl":   "t_cccccccc",
  "story_verify": "t_dddddddd",
  "story_land":   "t_eeeeeeee"
}
```

If the helper exits non-zero, `kanban_block(reason="decomposer failed: <stderr tail>")`. Do not improvise alternative decompositions.

### Step 3 — complete your own task

Parse the helper's JSON, then:

```python
kanban_complete(
    summary=f"decomposed story {bd_id} into stack-detect → health-check → impl → verify → land",
    metadata={
        "bd_id": bd_id,
        "epic_slug": epic_slug,
        "worktree": worktree,
        "task_graph": ids,   # the parsed JSON dict
    },
    created_cards=[
        ids["stack_detect"], ids["health_check"],
        ids["story_impl"], ids["story_verify"], ids["story_land"],
    ],
)
```

That's the entire skill for Slice 1.

## What this skill does NOT do

- **Reactive next-attempt-on-block.** If `[story-impl]` blocks, this orchestrator does NOT create `[story-impl-attempt-2]`. The story stalls. Slice 2.
- **Per-blocker-type branching** (STORY_AMBIGUITY/MISSING_DEPENDENCY/TEST_MISMATCH/INFRA/HARD_PROBLEM). Slice 2.
- **`[epic-gate]` and Quinn 3-layer fan-out.** Slice 3.
- **`[e2e-validation] / [deploy] / [report]`.** Slice 4.

## Profile roster (six valid assignees)

The helper script hardcodes these. You don't need to use them yourself in Slice 1, but here's the reference for understanding what gets created:

| Profile | Skill loaded per task | What it does |
|---|---|---|
| `dev-orchestrator` | `dev-team/kanban-decomposition` (this) | Decomposes story-roots; never assigned children |
| `hermes-detector` | `dev-team/stack-detect` | One-shot stack detection |
| `hermes-health-check` | `dev-team/health-fix` | Pre-flight health check |
| `pi-coder` | `dev-team/pi-dispatcher` | Subprocesses Pi to write code |
| `hermes-verifier` | `dev-team/cross-check` | Independent test re-run |
| `hermes-lander` | `dev-team/land-the-plane` | Convergent commit + Quinn + bd close + push |

## References

- `scripts/kanban-decompose-story.sh` — the helper this skill invokes
- `~/.hermes/skills/devops/kanban-orchestrator/SKILL.md` — canonical orchestrator playbook (auto-loaded; composes WITH this skill)
- `~/.hermes/skills/devops/kanban-worker/SKILL.md` — canonical worker conventions (auto-loaded)
- `dev-team/work-loop/SKILL.md` — pre-kanban canonical Phase 10 reference
- `/home/bob/.claude/plans/okay-lets-plan-theintergration-rustling-hedgehog.md` — full migration plan (this skill is Slice 1)
