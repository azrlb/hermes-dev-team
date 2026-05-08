---
name: vibe-plan
description: "Planning-only half of the hybrid Hermes-plans / Pi-builds architecture. Runs dev-team/vibe-loop phases 0-9 (analyst → architect → stories → bd create) then STOPS without dispatching Pi at runtime. Pair with pi-build-loop.sh for the implementation phase. Use this when running on local Ollama where brain-orchestrated Phase 10 hits a capability ceiling (per eval-7 findings 2026-04-30)."
version: 0.1.0
metadata:
  hermes:
    tags: [autonomous, planning, hybrid, no-runtime-dispatch]
    related_skills: [dev-team/vibe-loop, dev-team/work-loop]
---

# Plan (planning-only half of the hybrid Hermes-plans / Pi-builds architecture)

> **What this is:** the planning half of the dev-team pipeline. Runs the same phases 0-9 as `dev-team/vibe-loop`, then STOPS — the implementation phase (Phase 10+) is handled separately by `pi-build-loop.sh`, which dispatches Pi against the bd issues this skill creates.
>
> **Why split:** brain-orchestrated Phase 10 (Hermes dispatching Pi at runtime via SKILL.md work-loop) hit a capability ceiling across 7 eval rounds (2026-04-30). The brain hallucinated file paths from issue prose, made fake commits, fell into empty-command loops. The hybrid moves the runtime dispatch decision to a bash loop that reads story-file metadata directly — explicit paths from the planning phase, no runtime guessing. See `~/.claude/projects/-home-bob-ai-rig/memory/project_eval_findings.md` Round 6.

## What this skill does

Invokes `dev-team/vibe-loop`'s phases 0-9 (analyst → brief-capture → immersion → product-brief → prd → architecture → epics → story-specs → tdd → beads-filing → checkpoint), then **EXITS** without entering Phase 10.

The output of those phases is:
- `docs/stories/*.md` — story spec files with explicit `## Dev Notes` sections containing Test file paths and Key files to modify
- `src/.../*.test.*` — TDD test files for each story
- bd issues created with notes containing `story_file=<path> | test_file=<path>` (Phase 8 format)
- A clean working tree with discovery artifacts committed

## Invocation

```bash
hermes chat --yolo -s dev-team/vibe-plan -q "Build feature X for project Y"
```

Or, equivalently, run `dev-team/vibe-loop` with the explicit STOP instruction in the prompt:

```bash
hermes chat --yolo -s dev-team/vibe-loop -q "Build feature X. STOP at Phase 9 / planning-only — do not enter Phase 10."
```

Both paths route through the same vibe-loop SKILL.md but exit cleanly at Phase 9.

## Phase 8.5 — Kanban dual-write (Slice 5)

**After each `bd create` in Phase 8, ALSO emit a `kanban_create` for a story-root task** so the kanban-native dev-team takes over execution. Both substrates coexist: bd remains the issue tracker / source of acceptance criteria; kanban is the runtime executor that walks the per-story DAG (stack-detect → health-check → impl → verify → land) per Slices 1–3.

For each bd issue produced in Phase 8, do:

```python
import os, subprocess
# After: bd_id = result of `bd create ...`
# story_file and test_file came from Phase 7 (story-specs / tdd)

kanban_create(
    title=f"story-root for {bd_id}",
    assignee="dev-orchestrator",
    tenant=os.environ.get("HERMES_TENANT", "default"),
    workspace=f"dir:{os.path.abspath('.')}",
    skill="dev-team/kanban-decomposition",
    body=f"""Decompose story {bd_id} for kanban execution.
bd_id={bd_id}
story_file={story_file}
test_file={test_file}
worktree={os.path.abspath('.')}
mode={'greenfield' if not os.path.exists('package.json') else 'brownfield'}""",
)
```

The kanban dispatcher (running locally on `hermes kanban dispatch` ticks, OR daemon-mode via the gateway) then:

1. Spawns dev-orchestrator → invokes `scripts/kanban-decompose-story.sh` → creates 5 children (stack-detect, health-check, impl, verify, land)
2. Children walk the DAG via the Slices 1–3 pattern. Reactive escalation handles failures (Slice 2 / 2.5).
3. Lander commits with `fix(<bd_id>):`, closes bd, pushes (Slice 3 role boundaries enforced).

**Why dual-write instead of replacing bd:** `bd` remains the human-readable issue source (your `_bmad-output/` planning artifacts produce `bd create`s; that's the canonical input). Kanban is just the runtime substrate that EXECUTES each bd issue. They serve different layers; both stay.

**Where this matters for the LivingApp ecosystem:** the same dual-write pattern flows into the Sidecar (PRD §FR-P3, FR-P7). Each Sidecar-detected error or experiment is also a kanban task — the Sidecar inherits the same orchestrator/escalator pattern we proved here on the laptop side.

## How the legacy build phase consumed this (pre-Slice 5)

For backward compatibility with the pre-kanban flow, after this skill exits, you can still run:

```bash
/media/bob/C/AI_Projects/hermes-dev-team/scripts/pi-build-loop.sh /path/to/repo
# or, if install.sh symlinked it to your PATH:
pi-build-loop.sh /path/to/repo
```

The build script:
1. Pulls each ready bd issue via `bd ready --json`
2. Parses `story_file=<path>` from the issue's `notes` field (Phase 8 format)
3. Reads the story spec file — gets explicit "Key files to modify" + Test file path
4. Dispatches Pi (devstral-small-2:24b via Ollama) with the full story content as context
5. Pi runs the issue end-to-end: claim → implement → test → commit → close → push
6. bd-gate v0.4 runs the test command from the story spec on close — independent verification

**With Phase 8.5 dual-write enabled, you can skip pi-build-loop.sh entirely** — kanban handles the dispatch via the dev-team workers.

## Why this works where Phase 10 didn't

| Layer | Vibe-loop Phase 10 (brain dispatches Pi) | Hybrid (pi-build-loop dispatches Pi) |
|---|---|---|
| Where dispatch decision lives | Brain runtime, every iteration | Bash, parsed from bd notes |
| File path source | Brain extracts from issue prose | Story file's "Key files to modify" |
| Test command source | Brain hallucinates a path | Story file's "Test file" line |
| Hallucination surface | High (every dispatch is a fresh guess) | Low (paths read from disk) |
| Brain capability needed | Articulate, orchestrate, recover | Just produce good story specs |
| Failure mode | Wrong-path stubs, fake commits, loops | Pi fails honestly; bd-gate blocks |

## Pre-flight checks (inherited from vibe-loop)

- All Phase 9 checkpoint requirements: stories committed, test files exist, bd sync done
- Working tree clean before Pi build loop runs
- Ollama models have correct num_ctx (Hermes' numctx-verify plugin enforces this at session start)

## When to use which skill

- **`dev-team/vibe-loop`** — full E2E (planning + brain-orchestrated implementation). Use when you have a strong brain model that won't hallucinate paths — currently NOT qwen3:30b on local Ollama, per eval evidence.
- **`dev-team/vibe-plan`** (this skill) — planning only. Pair with `pi-build-loop.sh` for implementation. Recommended when running on the local 3-tier stack (P40 brain, P40 quinn, A4000 hands) where eval evidence shows brain dispatch is unreliable.
- **`dev-team/work-loop`** — DEPRECATED, do not invoke directly.
