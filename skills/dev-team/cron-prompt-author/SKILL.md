---
name: cron-prompt-author
description: Authoring discipline for Hermes cron job prompts. Load BEFORE you create or edit any prompt in ~/.hermes/cron/jobs.json or the repo's cron/jobs.json. Prevents the recurring failure where Hermes inlines an abbreviated summary of a canonical phase (especially Phase 10c Quinn review) and silently weakens a gate the upstream skill defined as a hard requirement. Trigger phrases — "create a cron job", "schedule a recurring task", "edit cron prompt", "update the pipeline cron", "add this to the kanban cron", "rewrite this cron's prompt", "make hermes cron run X". Also load whenever you are about to invoke `hermes cron create`, `hermes cron edit`, or write/modify a `cron/jobs.json` entry programmatically.
---

# Cron Prompt Authoring — Hermes Discipline

## Trigger

Load this skill **before** authoring or editing any cron job prompt, whether you reach the prompt via `hermes cron create`, `hermes cron edit`, direct edits to `~/.hermes/cron/jobs.json`, or repo `cron/jobs.json`. The risk is asymmetric: the cost of loading this skill is 30 seconds of context, the cost of not loading it is a silently-weak production gate that ships bugs for weeks.

## Why this skill exists

**2026-05-11 incident.** Hermes had previously authored two BMAD Pipeline cron prompts (Crispi Family Plan + FlowInCash-Core Epic 10). Both prompts contained an INLINE "Phase 10c (Quinn Adversarial Review)" section that was a 3-bullet checklist (Security / Correctness / Completeness) instead of the full multi-layer procedure defined in `skills/dev-team/vibe-loop/SKILL.md`.

Result: the cron ran nightly. The pipeline's "Quinn gate" was theatrical — it satisfied the named phase but invoked NEITHER the anti-patterns catalog NOR the bmad-code-review skill NOR the three adversarial reviewer layers NOR the fix loop NOR the catalog-maintenance step. Yesterday's batch shipped with 3 CRITICAL + 6 HIGH bugs (see `dev-team-work-loop/CODE-REVIEW-2026-05-11.md`) — all of which the full Phase 10c would have flagged.

This is a META failure: not a coding bug in production, but a workflow bug where Hermes (writing a cron prompt) summarized a canonical procedure into a one-pager and ended up with a structurally weaker gate. Without this skill, the same failure mode happens every time Hermes authors a new pipeline cron.

## Core principle

**REFERENCE canonical phases. Never INLINE a summary of them.**

When a cron prompt invokes a phase defined in a dev-team skill (vibe-loop / work-loop / health-fix / etc.), the prompt MUST direct the executor to *load and follow* the canonical phase definition. It MUST NOT paraphrase, summarize, or inline a "condensed version" of the phase.

Reason: phase definitions evolve. The anti-patterns catalog grows. The escalation chain changes. Inline summaries drift silently from the canonical and weaken the gate without anyone noticing. A reference to the canonical procedure auto-updates.

## Hard rules for BMAD pipeline cron prompts

Any cron prompt that orchestrates a BMAD pipeline (vibe-loop-style multi-phase coding flow) MUST follow these rules. Violations are a `cron-prompt-author` finding — flag yourself, fix, then proceed.

### Rule 1: Phase 10c is referenced, not inlined

The Phase 10c section in a pipeline cron prompt MUST contain (verbatim or equivalent):

> Phase 10c (Quinn Adversarial Review — MANDATORY HARD GATE): Follow the FULL procedure defined in `/media/bob/C/AI_Projects/hermes-dev-team/skills/dev-team/vibe-loop/SKILL.md` under the section "### Phase 10c / quinn-review". DO NOT substitute an abbreviated checklist. The full procedure is the gate.

It MUST then enumerate the load-bearing steps (load anti-patterns catalog, invoke bmad-code-review with three parallel layers, commit-claim audit, fix loop, catalog maintenance, escalation chain, halt-on-failure, no fabricated findings). A reference template lives in `scripts/strengthen-quinn-in-pipelines.py`'s `NEW_PHASE_10C` constant — copy from there.

**Forbidden Phase 10c shapes:**

- A 2-5 bullet checklist of review categories (Security / Correctness / Completeness, or similar). These look like reviews but skip the reviewer machinery entirely.
- A single sentence like "Run Quinn review on the changes." Without specifying which procedure, Hermes will improvise a weak one.
- A "skip if no findings expected" branch. There is no "skip" — Phase 10c is the gate.

### Rule 2: Other canonical phases also get references, not summaries

Same principle applies to:

- **Phase 7b (TDD Tests)** — refer to vibe-loop SKILL.md. Don't summarize the test-writing discipline; it has nuances about real-library-exception injection that an inline summary always drops.
- **Phase 11 (E2E Validation)** — refer to vibe-loop SKILL.md. Don't paraphrase the health-fix invocation rules; they handle classification of critical-vs-non-critical failures that a summary blurs.
- **Phase 12 (Deploy)** — refer to vibe-loop SKILL.md. Deploy procedures include rollback windows and post-deploy smoke checks that inlining will drop.
- **health-fix / learned-fixes** skill invocations — refer to the skill name + path. Don't inline.

When in doubt: REFERENCE.

### Rule 3: The cron prompt's job is orchestration, not procedure

A pipeline cron prompt is the orchestrator. It says:
- WHICH stories / epics / repos to work on
- WHAT business outcomes to deliver
- WHEN / WHERE / WHO (for Telegram reports)

It is NOT the place to redefine HOW phases work. HOW lives in the dev-team skills. The cron tells the executor "follow the dev-team pipeline for [scope]"; the skills tell the executor what each phase does.

A correctly-shaped cron prompt for a BMAD pipeline is ~3-5 KB — most of it is scope/context, with phase references. An incorrectly-shaped one is 5-10 KB — most of it is summary of phases that already live in the skills.

### Rule 4: Self-check before writing

Before saving a new cron prompt or pushing an edit, ask yourself:

1. Does my Phase 10c section reference `vibe-loop/SKILL.md` and enumerate the load-bearing steps? If no → STOP, fix.
2. Have I inlined a summary of any phase that's already defined in a dev-team skill? If yes → replace summary with reference.
3. Did I list specific load-bearing items inline (anti-patterns catalog, fix loop, escalation chain) for Phase 10c so the executor doesn't drop them under context pressure? If no → add them.
4. Have I cited the canonical path (`/media/bob/C/AI_Projects/hermes-dev-team/skills/dev-team/vibe-loop/SKILL.md`) so the executor can find the full procedure from any working directory? If no → add absolute path.

If any check fails: do NOT save the prompt. Iterate.

## Reference template — BMAD pipeline cron prompt skeleton

Use this skeleton when authoring a new pipeline cron. Replace the bracketed sections.

```
You are running the BMAD vibe-loop pipeline for [PROJECT — Epic/scope].

PROJECT: [/media/bob/C/AI_Projects/PROJECT-PATH]
CURRENT BRANCH: [branch]
TARGET: [main / feature/X / etc]

SCOPE — [Epic N / Story batch]:
[1-3 paragraphs of business context: what this delivers, why it matters,
which packages/files are touched, what depends on this]

STORIES IN SCOPE:
- Story X.Y (BEAD-id) — short description, AC reference
- Story X.Z (BEAD-id) — short description, AC reference
[continue]

PIPELINE PROCEDURE:

Follow the FULL vibe-loop pipeline as defined in:
/media/bob/C/AI_Projects/hermes-dev-team/skills/dev-team/vibe-loop/SKILL.md

Each phase below is named for navigation; execute the FULL procedure
from the SKILL.md, not an abbreviated version inlined here.

Phase 2 (Brownfield Immersion) — scan codebase, understand existing
scaffolds and patterns relevant to this epic.

Phase 3 (Feature Brief) — single feature brief summarizing the epic.

Phase 4 (Feature Spec) — lean spec referencing existing story specs.

Phase 5 (Architecture) — document wiring between affected packages.

Phase 6 (Epics Mapping) — FR coverage map.

Phase 7a (Stories) — DO NOT regenerate; story specs already exist at
[docs/stories/ path]. Reference them as-is.

Phase 7b (TDD Tests) — follow vibe-loop SKILL.md. Write tests first.
Tests MUST inject real library/external exception classes and use
captured real payloads where applicable — not synthetic self-generated
inputs. See references/ai-coder-antipatterns.md AP-TEST-2, AP-TEST-3.

Phase 8 (Beads Filing) — file `bd create` for each story with
story_file metadata, label `[epic-N]`, and the correct priority.

Phase 9 (Discovery Commit) — commit planning artifacts.

Phase 10 (Implementation) — implement in dependency order:
[ordered story list]

Phase 10b (Pattern Capture) — capture reusable patterns learned.

Phase 10c (Quinn Adversarial Review — MANDATORY HARD GATE):

Follow the FULL Phase 10c procedure defined in
/media/bob/C/AI_Projects/hermes-dev-team/skills/dev-team/vibe-loop/SKILL.md
under the section "### Phase 10c / quinn-review". DO NOT substitute an
abbreviated 3-category checklist. The full procedure is the gate.

Specifically, you MUST:
1. LOAD /media/bob/C/AI_Projects/hermes-dev-team/skills/dev-team/vibe-loop/references/ai-coder-antipatterns.md
   into the review context.
2. COLLECT diff + full source files touched.
3. INVOKE bmad-code-review skill with three parallel reviewer layers
   (Blind Hunter / Edge Case Hunter / Acceptance Auditor). Each layer
   gets the anti-patterns catalog. Each performs the commit-claim audit.
4. SUBAGENT FAILURE HANDLING per the SKILL.md escalation chain (parent
   model → deepseek-r1:32b → inline → HALT). Never fabricate findings.
5. TRIAGE findings: Critical/High → P0, Medium → P1, Low → P2. File
   each as a beads issue with the `quinn-review` label.
6. RUN THE FIX LOOP: for each P0/P1, claim → Pi fix → verify → land.
7. ANTI-PATTERNS CATALOG MAINTENANCE: any finding that doesn't match an
   existing entry → APPEND new entry to references/ai-coder-antipatterns.md
   before closing this phase. Catalog grows monotonically.
8. REPORT before proceeding to Phase 11.

This phase CANNOT be skipped or abbreviated.

Phase 11 (E2E Validation) — follow vibe-loop SKILL.md.

Phase 12 (Deploy) — follow vibe-loop SKILL.md, or "N/A — library" if
this project is not a deployed service.

Phase 13 (Completion Report) — deliver to Telegram per SKILL.md.

CONSTRAINTS:
- Test suite: [count] tests, all passing. Do not break this.
- [Other project-specific constraints — DO NOT touch X package; Y is in flight]

DELIVERY: Telegram
```

## What to do if you discover a cron prompt that violates these rules

1. Run `scripts/strengthen-quinn-in-pipelines.py` if the violation is the Phase 10c abbreviation. Script is idempotent and safe to re-run; it adds the canonical reference.
2. If the violation is a different phase's abbreviation, follow the same pattern: replace the inline summary with a reference + enumerate load-bearing steps.
3. Append a new entry to this skill's `## Known violations` log below citing the cron job id, the bug, and the fix.
4. If the cron is in `~/.hermes/cron/jobs.json` only (live-only, not in repo), file a separate issue to promote it into `cron/jobs.json` so it's version-controlled and future drift is detectable in git diffs.

## Known violations (incident log)

### 2026-05-11 — Crispi Family Plan + FlowInCash-Core Epic 10 BMAD Pipelines

- **Crons:** `548f363200b8` (Crispi), `536e0749002d` (FC Epic 10)
- **Bug:** Both contained inline 3-category Phase 10c (Security / Correctness / Completeness) instead of referencing vibe-loop SKILL.md.
- **Impact:** Yesterday's batch shipped 3 CRITICAL + 6 HIGH findings (see `dev-team-work-loop/CODE-REVIEW-2026-05-11.md`). The full Phase 10c would have caught all of them via the anti-patterns catalog grep.
- **Fix:** `scripts/strengthen-quinn-in-pipelines.py` ran, replaced both with the canonical reference. Live file backed up at `~/.hermes/cron/jobs.json.bak-pre-quinn-strengthen-*`.
- **Follow-up:** promote both jobs into repo `cron/jobs.json` so future drift surfaces in git diffs.

## Related skills

- `skills/dev-team/vibe-loop/SKILL.md` — the canonical pipeline definition. Cron prompts reference it.
- `skills/dev-team/vibe-loop/references/ai-coder-antipatterns.md` — the catalog Quinn applies (and the proactive-prevention version of the same content for Pi coding phases).
- `scripts/sync-cron-jobs.py` — merges repo `cron/jobs.json` into live `~/.hermes/cron/jobs.json`.
- `scripts/strengthen-quinn-in-pipelines.py` — one-shot fix script for the 2026-05-11 incident; safe to re-run after future cron drifts.
