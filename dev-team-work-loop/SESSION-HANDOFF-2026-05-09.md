# Session Handoff — 2026-05-09 (early hours)

**Read first.** This session ran late on 2026-05-08 and into the early
hours of 2026-05-09. It started from the 2026-05-08 handoff and shifted
direction after a few questions.

---

## What this session accomplished

### 1. Kanban fragility fix + version floor bump (hermes-dev-team)

Per the 2026-05-08 handoff's punch list:

- Floor bumped: `scripts/setup-kanban-profiles.sh` `REQUIRED_VERSION` 0.12.0 → 0.13.0
- Wait-for-terminal-state preamble added to `assert-happy-path.sh` and
  `assert-real-story.sh` so assertion 7 (lander idempotency) doesn't
  race the dispatcher
- Both fixtures re-ran 8/8: slice-1 in ~2 min, real-story in ~6 min
- Committed `c58ffea` on `dev`; pushed

### 2. Repo housekeeping (hermes-dev-team)

- `HERMES_OVERNIGHT_RUNS.pdf`, `docs/MODEL_DEV_TEAM_EVAL.md`,
  `mempalace.yaml` — committed `297b5a1` and pushed
- `.gitignore` updated to ignore `.claude/` and `_output/`
- Stale `Check Hermes results` scratch file deleted

### 3. FlowInCash-Core cleanup (no commits — preserve only)

The repo had ~30 stale `.js` stub files in `packages/auth/src/` plus
huge `.ts` deletions (1403 lines removed across mtls.ts, jwt.ts,
session-management.ts, rls/middleware.ts, service-token.ts, etc.) —
the staged work would have gutted the auth package.

Diagnosed as a re-run of the Story-1.1 stub generator that the
project's `.gitignore` was originally written to defend against.
Resolution:

- `git stash push -u -m "pre-cleanup snapshot 2026-05-08 — broken stub regen..."`
  preserves the broken work (recoverable via `git stash list`)
- `git reset --hard origin/main` restored the working tree
- Untracked `.beads/metadata.json.bak.*` and `.hermes/` removed

FlowInCash-Core is now clean and untouched. **The eval framework
intentionally does not target FlowInCash-Core anymore** — see the eval
framework section below.

### 4. Built hermes-model-eval synthetic eval framework

Major architectural shift away from targeting FlowInCash-Core
(production code) for evals. New framework lives entirely inside
`hermes-model-eval/` with a self-contained synthetic auth library at
`challenges/auth-security/sample-app/`.

- Phase A: 36 files (16 source, 10 failing tests, 10 story specs,
  package.json/tsconfig/vitest.config/AGENTS.md/README) committed in
  one squash. 10 deliberate bugs across T1, T2, T3, T5 of the rubric.
  T4 (test discipline) intentionally dropped — dev-team is TDD-first
  by design, can't measure unprompted test-writing
- Phase B: 3 orchestration scripts —
  - `scripts/swap-model.sh` (toggle worker + Quinn model with backup/restore)
  - `scripts/run-devteam-eval.sh` (stage sample-app, init git + bare
    remote, create 10 bd issues + 10 kanban story-roots, dispatch loop)
  - `scripts/score-eval.sh` (per-bug pass/fail, tier rollup, T5 scope
    diff size, total diff stat)
- Phase C: docs rewritten (top-level `README.md`,
  `challenges/auth-security/HOW-TO-RUN.md`); legacy single-agent flow
  retired (`prompt.txt`, `run-eval.sh`, `grade-eval.sh`,
  `reset-challenge.sh` deleted)
- Phase D: dry-run validated — orchestration steps 1–4 (stage, install,
  init, create issues + tasks) execute clean; zero credits spent
- Phase E (runs): ran twice with Quinn pinned to `anthropic/claude-sonnet-4.6`
  via Nous Portal:

| Run | Worker model | Stories landed | Wall time | Notes |
|---|---|---|---|---|
| Pro | `xiaomi/mimo-v2.5-pro` | **5 / 10** | 5422 s (90 m cap) | 5 landers blocked with hallucinated reasons |
| non-Pro | `xiaomi/mimo-v2.5` | **10 / 10** | 5416 s (90 m cap) | All landed cleanly; runner idle-polled to timeout |

Result: **non-Pro outperformed Pro 2:1 on lander reliability.**

### 5. Two architectural gaps surfaced + addressed

**Gap 1 — Lander hallucination.** Pro's lander confabulated narratives
about "fix already at HEAD via mega-commit" when working-tree state
didn't match expectations. Quinn never caught these because Quinn only
runs on actual commits, and the lander self-blocked before committing.

**Status: FIXED** in `skills/dev-team/land-the-plane/SKILL.md`. The
"On startup" section now requires the lander to:

1. Re-run the bug's specific test against current HEAD when HEAD has moved
2. Block with one of two **terse, factual** reasons based on the test
   result — never narrate, never speculate about what other workers did
3. Banned-phrase list in the SKILL: "the fix is already at HEAD via...",
   "another worker committed...", "mega-commit absorbed...", etc.

The objective-signal block reasons feed directly into Gap 2's recovery
routing (see below).

**Gap 2 — Disconnected escalation.** When the story-root is marked
`done` after decomposition (the Slice 1 bypass pattern, inherited by
the eval runner), the orchestrator isn't around to react when a child
blocks. The Slice 2/2.5 reactive escalation logic never fires.

**Status: DESIGN PROPOSED** in
`dev-team-work-loop/DESIGN-2026-05-09-disconnected-escalation.md`.
Three options analyzed (alive-orchestrator, block-watcher worker,
runner-side hook); **Option B (block-watcher)** recommended with
sub-task list and acceptance criteria. Cost estimate: ~2–3 hours of
implementation. Not implemented tonight — needs a focused architectural
session, not a midnight patch.

### 6. Plugin landscape reviewed + documented

In response to questions about LCM, self-evolution, and the plugin
extension points, the eval `README.md` now has a **Follow-ups to
evaluate** section covering all four:

- `hermes-lcm` (Lossless Context Management — Stephen Schoettler)
- `hermes-agent-self-evolution` (NousResearch DSPy + GEPA, Phase 1 only)
- Memory Provider plugin interface (Honcho already inherited; broader
  interface stable since v0.13.0)
- Context Engine plugin interface (LCM is the canonical plugin)

Plus a concrete first-experiment plan in
`hermes-model-eval/docs/SELF-EVOLUTION-PHASE-1.md` — pick
`escalation-handler` as the first GEPA target; ~$25 budget; clear
keep-vs-discard criteria; ties to the kanban-block-watcher proposal.

### 7. LivingApp-Sidecar PRD addendum + repo cleanup

PRD addendum drafted at
`LivingApp-Sidecar/_bmad-output/planning-artifacts/PRD-ADDENDUM-2026-05-08-plugins-and-kanban.md`.
Captures:

- New §2.4 (Plugin Architecture & Operations Substrate) — ready to paste
- New Epic E-K (Sidecar Kanban Operations) — full spec, acceptance,
  story estimate
- Inline notes for E-D, E-E, E-F, E-I
- Decisions Log entries 10–14 (plugin architecture, eval-time pinning)
- PM cross-reference checklist

Marked PENDING INTEGRATION; the BMad PM merges into PRD.md v3 during
the next focused PRD revision. Trigger: paired with the parallel
LivingApp-Platform PRD addendum (still to be authored).

LivingApp-Sidecar repo cleanup (similar pattern to FlowInCash-Core but
with real work to commit):

- `.beads/issues.jsonl` (31 new beads issues) — committed `b26f173`
- `.gitignore` additions for `.beads/dolt-backup.json`, `.beads.embedded.bak/` — same commit
- `.pi/skills/bmad-agent-dev/SKILL.md` (bd prime/ready + story label rules) — `c35d1a0`
- ADR 004 + research appendix (kanban substrate decision) — `444fc49`
- PRD addendum — `18b4195`
- 3 MB `.beads.embedded.bak/` migration backup deleted
- Cosmetic markdown reformats in `_bmad-output/project-context.md` and `qa-review-epic1.md` — discarded
- All 4 commits pushed to `origin/main`

---

## Where things stand at session end

### Hermes config — IMPORTANT

Currently the 6 dev-team profiles are set to:

- Worker: `xiaomi/mimo-v2.5` (non-Pro — set during eval, not restored)
- Quinn: `anthropic/claude-sonnet-4.6` (set during eval, not restored)

Backups exist at `~/.hermes/profiles/<p>/config.yaml.eval-backup` for
all 6 profiles. **To restore your normal Pro+Pro setup:**

```bash
cd /media/bob/C/AI_Projects/hermes-model-eval
./scripts/swap-model.sh restore
```

That copies each backup back over the current config and removes the
backup file. Confirm with `./scripts/swap-model.sh status` afterward.

If you're tempted to leave it on non-Pro for daily dev-team work
based on the eval result, re-run the eval 2–3 more times first — n=1
might be a lucky/unlucky run in either direction.

### Working trees

- **hermes-dev-team:** about to be committed (this session's lander
  fix + design doc + handoff). Will be ahead of `origin/dev` after this commit
- **hermes-model-eval:** runner-exit-condition fix is uncommitted; about to commit
- **LivingApp-Sidecar:** clean, pushed to `origin/main`
- **FlowInCash-Core:** clean, untouched

---

## Tomorrow's options, in priority order

### Highest signal: re-run the eval 2–3 more times to confirm Pro vs non-Pro

Single-run results are noisy. Re-running both variants 2–3 times tells
you whether 5/10 vs 10/10 is the steady state or just one bad/lucky
night. Cost: ~$50 for 3 paired runs.

```bash
./scripts/swap-model.sh save     # if not already
./scripts/swap-model.sh set-quinn anthropic/claude-sonnet-4.6
for slug in mimo-v2.5-pro mimo-v2.5; do
  ./scripts/swap-model.sh set-worker "xiaomi/${slug/-pro/-pro}"
  for i in 2 3 4; do
    ./scripts/run-devteam-eval.sh "${slug}-run${i}"
    ./scripts/score-eval.sh       "${slug}-run${i}"
  done
done
./scripts/swap-model.sh restore
```

### Secondary: implement the block-watcher (Gap 2)

Read `dev-team-work-loop/DESIGN-2026-05-09-disconnected-escalation.md`,
follow Option B's 5 sub-tasks. ~2–3 hours focused. After this, re-run
the eval and watch the Pro hallucinations get caught + routed to
recovery siblings instead of just sitting blocked.

### Tertiary: GEPA-evolve the escalation-handler skill

Per `hermes-model-eval/docs/SELF-EVOLUTION-PHASE-1.md`. Best value
AFTER the block-watcher exists — evolution input data improves once
the skill is actually wired into the kanban dev-team flow.

### Stalled (still on the docket from the prior handoff)

- **Slice 4 — Railway deploy + Telegram report.** Not touched today.
  Still 3–4 hours of work; can probably reduce now that v0.13.0's
  `hermes kanban notify-subscribe` exists for the Telegram half.
- **PRD updates — LivingApp-Platform.** The Sidecar addendum is done;
  Platform's parallel addendum (FR-P3 / FR-P4 / FR-P7 kanban-native
  rewrites) is still pending.

### Untouched: the lander fix needs a fixture

The new HEAD-moved protocol in `land-the-plane/SKILL.md` is text in a
SKILL doc — not yet covered by an automated fixture. A small fixture
in `dev-team-work-loop/tests/kanban-lander-head-moved/` should:

1. Set up a story where verify writes `.test-result PASS sha_A`
2. Force HEAD to move to sha_B before the lander runs
3. Plant the bug fix at sha_B (so the test passes)
4. Assert: lander blocks with reason matching `target test passes at HEAD; orchestrator must reconcile attribution`
5. Plant variant where the fix is NOT at sha_B (test still fails)
6. Assert: lander blocks with reason matching `target test still failing at HEAD; substrate race or work lost`

~30 min to write; would catch SKILL.md regressions.

---

## Quick start tomorrow

```bash
cd /media/bob/C/AI_Projects/hermes-dev-team
cat dev-team-work-loop/SESSION-HANDOFF-2026-05-09.md       # this file
cat dev-team-work-loop/DESIGN-2026-05-09-disconnected-escalation.md   # if working on Gap 2

# Restore Hermes config to normal Pro+Pro setup if not already
cd /media/bob/C/AI_Projects/hermes-model-eval
./scripts/swap-model.sh status              # check current state
./scripts/swap-model.sh restore             # if backups still exist

# Pick from the priority list above. Re-run eval is the cheapest
# next step that gives you the most data.
```
