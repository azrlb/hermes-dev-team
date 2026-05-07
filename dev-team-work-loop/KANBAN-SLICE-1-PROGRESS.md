# Kanban Migration — Slice 1 Progress Report

**Date:** 2026-05-06
**Plan:** `~/.claude/plans/okay-lets-plan-theintergration-rustling-hedgehog.md`
**ADR (Sidecar context):** `/media/bob/C/AI_Projects/LivingApp-Sidecar/docs/adr/004-adopt-hermes-kanban-runtime-substrate.md`

## TL;DR

Slice 1 wiring is **proven**: the kanban dispatcher correctly fans out a 5-task graph (stack-detect → health-check → impl → verify → land) when given a deterministic decomposer. End-to-end completion is **not yet proven** — local qwen3:30b throughput exceeds the kanban claim TTL (~15 min), causing workers to be reclaimed mid-LLM-turn, respawned, and stuck in a loop.

## What works

- **Six profiles provisioned** at `~/.hermes/profiles/{dev-orchestrator, hermes-detector, hermes-health-check, pi-coder, hermes-verifier, hermes-lander}/` via `scripts/setup-kanban-profiles.sh` (idempotent, clones from `default`).
- **Deterministic decomposer** (`scripts/kanban-decompose-story.sh`) creates the 5-task graph with correct assignees, parent links, skill pins, and workspace `dir:<path>` threading. This bypasses the LLM-orchestrator drift problem (qwen3:30b unreliably names assignees when authoring `kanban_create` calls itself).
- **Stack-detect, health-check, and impl workers all completed cleanly in run #6** (~48 min total). Their structured handoff (summary + metadata) propagated correctly between tasks.
- **The cross-check/verifier skill correctly caught a wrong-runner mismatch** in run #6 — exactly its designed purpose. Stack-detect emitted a Jest-style `--testPathPattern` flag for a Vitest project; verifier blocked with diagnosis.
- **Bare-remote Git push works** from the `[story-land]` workspace (verified by setup phase of runs #6/#7).

## What's broken

### Bug 1 — Stack-detect emits wrong test_single_cmd for Vitest

Pre-existing bug in `skills/dev-team/stack-detect/SKILL.md` (not authored by Slice 1). The skill emits `npx vitest run --testPathPattern` regardless of test runner, but `--testPathPattern` is a Jest flag that Vitest rejects.

**Workaround applied (Slice 1):** decomposer now accepts an optional 6th arg `TEST_SINGLE_CMD` and embeds it as a `test_single_cmd=...` line in the impl/verify/land task bodies. Cross-check skill prefers body-explicit value over parent metadata.

**Proper fix (deferred):** update stack-detect skill to detect Vitest specifically and emit `npx vitest run` (path is positional, no flag).

### Bug 2 — Worker claim TTL shorter than worker run time

The kanban dispatcher's default claim TTL is ~15 minutes. Local qwen3:30b workers running real LLM analysis (stack-detect reading `package.json`, health-check running lint+tsc) regularly exceed that. Symptoms:

- Worker spawned at T+0
- Claim expires at T+15m
- Dispatcher reclaims, spawns a new worker
- Old worker keeps running (no SIGTERM until OS reaps later)
- Multiple workers now compete for the same task and same local model server
- Task makes negative progress

In run #7, three concurrent pi-coder workers were running on the same task simultaneously (PIDs 44879, 47130, 49020) by the time the fixture timed out.

**Possible fixes (not implemented):**
- Increase task `--max-runtime` from default (whatever it is) to 60m+ via the decomposer.
- Have the worker shell more aggressively check whether its claim is still valid before continuing LLM turns.
- Pre-shim more workers (stack-detect, health-check) so they finish in seconds rather than minutes — the original Slice 1 spirit.

## Run-by-run summary

| Run | Outcome | Time | Notes |
|---|---|---|---|
| #1 | Failed: orchestrator used `hermes-detector` / `hermes-health-check` profiles that didn't exist yet | ~3 min | Fixed by adding 2 more profiles to setup script |
| #2 | Failed: parser bug `task_id` vs `id`; orchestrator only created 1 child | ~5 min | Fixed parser; tightened SKILL.md |
| #3 | Failed: orchestrator added `-worker` suffix to assignee names | ~5 min | Tried to fix via SKILL.md emphasis |
| #4 | Failed: same drift; orchestrator can't run bash helpers (toolset restriction) | ~3 min | Pivoted to deterministic helper invoked by runner |
| #5 | Wiring proven, workers spawned, GPU-queued | ~5 min | 5-min timeout too aggressive for real LLM work |
| #6 | **Stack-detect ✅, health-check ✅, impl ✅, verify BLOCKED on stack-detect bug**, land todo | ~60 min | First evidence the chain runs; surfaced Bug 1 |
| #7 | Stack-detect ✅, health-check ✅, impl reclaimed×3 (Bug 2) | ~60 min | Surfaced claim-TTL issue |

## Architectural finding worth preserving

The canonical `~/.hermes/skills/devops/kanban-orchestrator/SKILL.md` says verbatim:

> *"Your restricted toolset usually doesn't even include terminal/file/code/web for implementation."*

Implication: the dev-orchestrator profile can ONLY use `kanban_*` tools — it cannot invoke deterministic shell helpers. **Slice 2's reactive escalation logic must be expressed entirely as `kanban_create` calls, not as scripts/Python that the orchestrator shell-execs.** Each escalation strategy is a sibling task, not a function call.

## Files added (committed in this session)

```
skills/dev-team/kanban-decomposition/SKILL.md   — orchestrator playbook (Slice 1: invokes the helper)
skills/dev-team/pi-dispatcher/SKILL.md          — bash-wrapping Pi worker
skills/dev-team/cross-check/SKILL.md            — independent test re-run + .test-result writer
skills/dev-team/land-the-plane/SKILL.md         — convergent landing
scripts/setup-kanban-profiles.sh                — idempotent provisioner for the 6 profiles
scripts/kanban-decompose-story.sh               — deterministic 5-child graph creator
dev-team-work-loop/tests/kanban-slice-1/run-happy-path.sh
dev-team-work-loop/tests/kanban-slice-1/assert-happy-path.sh
dev-team-work-loop/KANBAN-SLICE-1-PROGRESS.md   — this file
dev-team-work-loop/KANBAN-SLICE-1-NEXT-SESSION.md — startup handoff for tomorrow
```

Plan file at `~/.claude/plans/okay-lets-plan-theintergration-rustling-hedgehog.md` updated with the same findings.
