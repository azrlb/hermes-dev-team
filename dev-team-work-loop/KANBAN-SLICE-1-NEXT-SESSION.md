# Kanban Migration — Tomorrow's Startup Handoff

**Read this first.** Then read `KANBAN-SLICE-1-PROGRESS.md` for context on what happened yesterday.

## Current state in 30 seconds

- 8 new files committed and pushed to `dev` branch (4 SKILLs, 2 scripts, 2 fixture scripts).
- 6 Hermes profiles provisioned locally (`dev-orchestrator`, `hermes-detector`, `hermes-health-check`, `pi-coder`, `hermes-verifier`, `hermes-lander`).
- Slice 1 wiring **proven** (the dispatcher correctly fans out the 5-task graph). End-to-end completion **blocked** on two distinct bugs.
- All test tasks archived; no orphan workers.

## Pick exactly one of these three paths today

### Path A — Push through to Slice 1 acceptance (recommended)

**Goal:** make `bash dev-team-work-loop/tests/kanban-slice-1/run-happy-path.sh` followed by `assert-happy-path.sh` pass all 8 acceptance assertions.

**Two bugs to fix first:**

1. **Worker claim TTL too short.** The dispatcher reclaims workers at ~15 min (default), but local qwen3:30b workers regularly exceed that. Result: multiple concurrent workers fight over the same task. Fix one of:
   - Add `--max-runtime 90m` to every `hermes kanban create` call inside `scripts/kanban-decompose-story.sh`.
   - OR: shim the slow LLM workers (stack-detect, health-check) so they complete in seconds. Pattern: write `bin/stack-detect-worker` and `bin/health-check-worker` shims that emit canned metadata and `kanban_complete`. This matches the spirit of Slice 1 (test wiring, not local-model speed).

2. **Stack-detect emits wrong test_single_cmd for Vitest.** Already worked around in Slice 1 (decomposer passes the value explicitly), but the underlying skill bug remains. Fix: update `skills/dev-team/stack-detect/SKILL.md` to recognise Vitest (`vitest` in `devDependencies` or `vitest.config.*` present) and emit `npx vitest run` with no flag. Path is positional in Vitest.

**Then re-run:**
```bash
cd /media/bob/C/AI_Projects/hermes-dev-team
bash dev-team-work-loop/tests/kanban-slice-1/run-happy-path.sh
bash dev-team-work-loop/tests/kanban-slice-1/assert-happy-path.sh
```

Expected new failure modes if both bugs fix correctly:
- `[story-land]`'s per-commit Quinn step will run a `pi --no-tools --provider ollama-quinn --model deepseek-r1:32b` review. Cold-start of deepseek-r1 can take 5+ min on the first call. Expect runtime ~75–90 min total.
- bd-gate may reject `bd close` if `.hermes/sessions/<bd-id>.test-result` isn't exactly `PASS <HEAD-sha>`. Verifier writes it; check the format.

### Path B — Move on to Slice 2 design

**Goal:** design the reactive escalation logic for the dev-orchestrator profile, given the constraint that orchestrator profiles CANNOT use bash/terminal tools — only `kanban_*` tools.

**Key constraint discovered yesterday:**

> *"Your restricted toolset usually doesn't even include terminal/file/code/web for implementation."* — `~/.hermes/skills/devops/kanban-orchestrator/SKILL.md`

This means Slice 2's escalation chain (different approach → research → Qwen → deep research → Quinn fix) cannot be a Python/bash function. Each escalation strategy must be a `kanban_create` call to a sibling task.

**Read for context:**
- `~/.claude/plans/okay-lets-plan-theintergration-rustling-hedgehog.md` §Escalation sub-graph
- `skills/dev-team/work-loop/SKILL.md` Step 8 (the canonical inline escalation chain we're porting)
- `scripts/escalator.py` (the existing python implementation Slice 2 will likely wrap)
- `skills/dev-team/escalation-handler/SKILL.md` (the 5 blocker-type branches)

**First Slice 2 deliverable:** decide whether to (a) wrap `escalator.py` in a single `[story-escalation]` task whose worker runs the script (cleanest, smallest delta) or (b) fan each escalation strategy into its own kanban task (matches your draft plan, more visibility, more LLM moving parts).

### Path C — Step back and re-scope

**Goal:** revisit whether kanban-as-runtime-substrate is the right call given what was learned.

**Reasons to consider:**
- Local qwen3:30b throughput vs kanban claim TTL is a real friction. Production setups that use cloud models (Sonnet) wouldn't hit it.
- The orchestrator's no-bash-tools constraint pushes a lot of decision logic into deterministic scripts the LLM just invokes — at which point, what does the LLM add over a plain bash work-loop?
- The existing `scripts/pi-build-loop.sh` already implements most of what Slice 2/3 would re-implement on top of kanban.

**Reasons NOT to step back:**
- Durability across crashes is real and valuable.
- The dashboard at `localhost:9119` is real and valuable for overnight runs.
- Per-commit Quinn + source-changed pre-check + auto-close-on-Pi's-behalf — these would all port cleanly.
- The 8 files committed yesterday already encode the Slice 1 design; throwing it out costs more than fixing it.

If you choose Path C, the plan file (`~/.claude/plans/...`) needs a new section "Decision: shelve kanban migration" with the trade-offs documented. The committed files can stay (they're well-scoped, idempotent, and don't break anything by existing).

## Useful diagnostic commands

```bash
# Watch all kanban tasks in the dev-team tenant scheme
hermes kanban list --tenant KanbanSlice1
hermes kanban watch --kinds completed,blocked,crashed,timed_out

# What's a specific task doing?
hermes kanban show t_<id>

# Force a dispatcher tick (no need to start the gateway)
hermes kanban dispatch

# Kill all dev-team kanban workers
pkill -f "hermes -p (pi-coder|hermes-detector|hermes-health-check|hermes-verifier|hermes-lander).*kanban"

# Reset the test fixture
rm -rf /tmp/hermes-kanban-slice1 /tmp/hermes-kanban-slice1-remote.git
```

## Files to read in priority order

1. `dev-team-work-loop/KANBAN-SLICE-1-PROGRESS.md` — yesterday's state
2. `~/.claude/plans/okay-lets-plan-theintergration-rustling-hedgehog.md` — full migration plan with execution log
3. `dev-team-work-loop/tests/kanban-slice-1/run-happy-path.sh` — fixture (read this before running it)
4. `skills/dev-team/kanban-decomposition/SKILL.md` — the orchestrator playbook
5. `scripts/kanban-decompose-story.sh` — the deterministic decomposer

## Don't redo

- Don't try to make the `dev-orchestrator` LLM produce correct `kanban_create` calls itself. Tried 4 times yesterday, it drifts every time. Use the deterministic helper.
- Don't try to enable bash tools for the orchestrator profile. The canonical kanban-orchestrator skill restricts it for a reason — orchestrators that "just fix this quickly" are an anti-pattern.
- Don't archive `dev-team-work-loop/tests/kanban-slice-1/`. The fixtures are reusable; just `rm -rf /tmp/hermes-kanban-slice1*` to reset state.
