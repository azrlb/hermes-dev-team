---
name: loop-prompt-author
description: Authoring discipline for Hermes whenever you are about to produce instructions that will be executed by another agent or by future-self in a dev-team pipeline. Load BEFORE you (a) create or edit any cron prompt, (b) START a vibe-loop session (greenfield projects, full pipeline), (c) START a work-loop session (brownfield projects), (d) spawn a subagent to do pipeline phase work (Pi to implement a story, reviewer to run Quinn, etc.), or (e) write any planning doc, story spec, or hand-off file that paraphrases phase procedures defined in dev-team skills. Prevents the recurring failure where Hermes inlines an abbreviated summary of a canonical phase (especially Phase 10c Quinn review in vibe-loop OR Step 10 Quinn review in work-loop) and silently weakens a gate the upstream skill defined as a hard requirement. Trigger phrases — "create a cron job", "schedule a recurring task", "edit cron prompt", "start the vibe-loop", "start vibe-loop for X", "begin the work-loop", "kick off the brownfield loop", "run the pipeline on X", "spawn pi to implement story X", "delegate this phase to a subagent", "write the story spec", "draft the hand-off". Also load whenever you are about to invoke `hermes cron create`, `hermes cron edit`, write/modify a `cron/jobs.json` entry, OR construct a multi-paragraph prompt for another agent.
---

# Loop Prompt Authoring — Hermes Discipline

## Trigger

Load this skill **before** authoring ANY instructions that another agent (or future-self) will execute as part of a dev-team pipeline. The risk is asymmetric: the cost of loading this skill is 30 seconds of context, the cost of NOT loading it is a silently-weak production gate that ships bugs for weeks.

Load this skill when you are about to:

1. **Create or edit a cron job prompt** — `hermes cron create`, `hermes cron edit`, direct edits to `~/.hermes/cron/jobs.json`, or repo `cron/jobs.json`.
2. **Start a vibe-loop session** (greenfield project, full pipeline) — manually or via the `dev-team/vibe-loop` skill. Even when you intend to follow the SKILL.md as written, the moment you produce ANY custom instruction within the loop (subagent dispatch, checkpoint file, story spec), this discipline applies.
3. **Start a work-loop session** (brownfield project) — same as above for `dev-team/work-loop`.
4. **Spawn a subagent** to do pipeline phase work — invoking Pi to implement a story, delegating to a code-review agent, dispatching a domain-specific helper. ANY prompt you write to direct another agent's behavior on a phase falls under this discipline.
5. **Write a planning artifact** that paraphrases phase procedures — story specs, hand-off files, architecture docs, checkpoint files. If the document describes "what happens in Phase X," it must reference the canonical Phase X definition, not paraphrase it.

## Why this skill exists

**2026-05-11 incident.** Hermes had previously authored two BMAD Pipeline cron prompts (Crispi Family Plan + FlowInCash-Core Epic 10). Both prompts contained an INLINE "Phase 10c (Quinn Adversarial Review)" section that was a 3-bullet checklist (Security / Correctness / Completeness) instead of the full multi-layer procedure defined in `skills/dev-team/vibe-loop/SKILL.md`.

Result: the cron ran nightly. The pipeline's "Quinn gate" was theatrical — it satisfied the named phase but invoked NEITHER the anti-patterns catalog NOR the bmad-code-review skill NOR the three adversarial reviewer layers NOR the fix loop NOR the catalog-maintenance step. The 2026-05-11 batch shipped with 3 CRITICAL + 6 HIGH bugs (see `dev-team-work-loop/CODE-REVIEW-2026-05-11.md`) — all of which the full Phase 10c would have flagged.

This is a META failure: not a coding bug in production, but a workflow bug where Hermes (writing instructions) summarized a canonical procedure into a one-pager and ended up with a structurally weaker gate. **The same failure mode can happen any time Hermes writes instructions for another agent or future-self, not just in cron prompts.** Without this skill, the failure recurs every time Hermes authors a new pipeline cron, dispatches a subagent for a phase, writes a story spec, or hands off to a future session.

## Core principle

**REFERENCE canonical phases. Never INLINE a summary of them.**

When the instructions you're writing will trigger a phase defined in a dev-team skill (vibe-loop / work-loop / health-fix / learned-fixes / etc.), the instructions MUST direct the executor to *load and follow* the canonical phase definition. They MUST NOT paraphrase, summarize, or inline a "condensed version" of the phase.

Reason: phase definitions evolve. The anti-patterns catalog grows. The escalation chain changes. Inline summaries drift silently from the canonical and weaken the gate without anyone noticing. A reference to the canonical procedure auto-updates.

## Which skill defines what — quick reference

When your instructions mention a phase, check which loop's SKILL.md defines it and reference accordingly:

| Loop / type | SKILL.md path | What it defines |
|---|---|---|
| **Greenfield (full pipeline)** | `skills/dev-team/vibe-loop/SKILL.md` | Phases 0–13: analyst → brief → PRD → architecture → epics → story specs → TDD → beads → checkpoint → dev → pattern capture → **Phase 10c Quinn** → e2e → deploy → report |
| **Brownfield (existing project)** | `skills/dev-team/work-loop/SKILL.md` | Iterative story-by-story with epic-level adversarial review. **Step 10 Quinn** (mandatory, once-per-epic) lives here. |
| **Health fixes / test repair** | `skills/dev-team/health-fix/SKILL.md` | Progress-based fixing of failing tests/build. |
| **Pattern learning** | `skills/dev-team/learned-fixes/SKILL.md` | Capturing reusable fixes from prior incidents. |
| **AI-coder anti-patterns catalog** | `skills/dev-team/vibe-loop/references/ai-coder-antipatterns.md` | The growing list of patterns Quinn (in either loop) must grep for. Shared by both loops. |

If you're not sure which loop applies, ask first. Vibe-loop = building something from scratch. Work-loop = changing/extending something that exists.

## Hard rules

These apply to all the trigger contexts above. Violations are a `loop-prompt-author` finding — flag yourself, fix, then proceed.

### Rule 1: Quinn review references the canonical, not an inline checklist

The Quinn review step in any pipeline prompt MUST contain (verbatim or equivalent, depending on loop type):

**Greenfield (vibe-loop) — Phase 10c:**
> Phase 10c (Quinn Adversarial Review — MANDATORY HARD GATE): Follow the FULL procedure defined in `/media/bob/C/AI_Projects/hermes-dev-team/skills/dev-team/vibe-loop/SKILL.md` under the section "### Phase 10c / quinn-review". DO NOT substitute an abbreviated checklist. The full procedure is the gate.

**Brownfield (work-loop) — Step 10:**
> Step 10 (Quinn Adversarial Code Review — MANDATORY): Follow the FULL procedure defined in `/media/bob/C/AI_Projects/hermes-dev-team/skills/dev-team/work-loop/SKILL.md` under Step 10 of the epic-completion section. DO NOT substitute an abbreviated checklist. The full procedure is the gate.

Either reference MUST then enumerate the load-bearing items so the executor doesn't drop them under context pressure: load the anti-patterns catalog, invoke `bmad-code-review` with three parallel reviewers, perform commit-claim audit, file P0/P1 findings as beads issues (label `quinn-review` for greenfield or `epic-{N}-review` for brownfield), run the fix loop until all P0/P1 are closed, append new failure modes to the anti-patterns catalog, halt on subagent failure that cannot be escalated.

A reference template for the strengthened Phase 10c lives in `scripts/strengthen-quinn-in-pipelines.py`'s `NEW_PHASE_10C` constant — copy from there.

**Forbidden Quinn-review shapes (either loop):**

- A 2-5 bullet checklist of review categories (Security / Correctness / Completeness, or similar). These look like reviews but skip the reviewer machinery entirely.
- A single sentence like "Run Quinn review on the changes." Without specifying which procedure, the executor improvises a weak one.
- A "skip if no findings expected" branch. There is no "skip" — Quinn review is the gate.

### Rule 2: Other canonical phases also get references, not summaries

Same principle applies to:

- **Vibe-loop Phase 7b (TDD Tests)** — don't summarize the test-writing discipline; it has nuances about real-library-exception injection (anti-pattern AP-TEST-3) that an inline summary always drops.
- **Vibe-loop Phase 11 (E2E Validation)** — don't paraphrase the health-fix invocation rules; they handle classification of critical-vs-non-critical failures that a summary blurs.
- **Vibe-loop Phase 12 (Deploy)** — deploy procedures include rollback windows and post-deploy smoke checks that inlining will drop.
- **Work-loop Step 4-8 (story implementation, test, commit, push)** — the brownfield discipline includes test-discipline notes that don't survive paraphrase.
- **health-fix / learned-fixes** skill invocations — refer to the skill name + path. Don't inline.

When in doubt: REFERENCE.

### Rule 3: The instructions' job is orchestration, not procedure

A pipeline-orchestration prompt is the orchestrator. It says:
- WHICH stories / epics / repos to work on
- WHAT business outcomes to deliver
- WHEN / WHERE / WHO (for cron prompts, this also includes the schedule and delivery target)

It is NOT the place to redefine HOW phases work. HOW lives in the dev-team skills. The prompt tells the executor "follow the dev-team [vibe-loop|work-loop] pipeline for [scope]"; the skills tell the executor what each phase does.

A correctly-shaped pipeline prompt is ~3-5 KB — most of it is scope/context, with phase references. An incorrectly-shaped one is 5-10 KB — most of it is paraphrased phases that already live in the skills.

### Rule 4: Subagent dispatch prompts follow the same discipline

When spawning a subagent to do a phase (e.g., "Pi, implement Story X.Y" or "Reviewer, run Quinn on this diff"), the subagent's prompt MUST reference the canonical phase definition. Telling Pi "implement this story" is not enough — direct Pi to follow the relevant phase of the appropriate loop, citing the SKILL.md path.

Example correct subagent prompt for Pi:
> Implement Story 10.6 (Postpone Stack) per the procedure in `/media/bob/C/AI_Projects/hermes-dev-team/skills/dev-team/vibe-loop/SKILL.md` Phase 10. Follow Phase 7b for test discipline (write tests first, inject real library exceptions, no synthetic self-generated inputs). Story spec: docs/stories/Story-10.6.md.

Example WRONG (inlined-summary) subagent prompt:
> Implement Story 10.6 (Postpone Stack). Write tests first. Make sure tests pass. Run a quick security review on what you wrote. Commit and push.

The first delegates to the canonical procedure. The second invents a weak version.

### Rule 5: Self-check before producing the instructions

Before saving a new cron prompt, sending a subagent prompt, committing a planning doc, or starting a loop with custom phase notes, ask yourself:

1. Does my Quinn-review reference cite the appropriate SKILL.md (vibe-loop for greenfield, work-loop for brownfield) and enumerate the load-bearing steps? If no → STOP, fix.
2. Have I inlined a summary of any phase that's already defined in a dev-team skill? If yes → replace summary with reference.
3. Did I list specific load-bearing items inline (anti-patterns catalog, fix loop, escalation chain) so the executor doesn't drop them under context pressure? If no → add them.
4. Have I cited the canonical path (absolute path under `/media/bob/C/AI_Projects/hermes-dev-team/skills/dev-team/...`) so the executor can find the full procedure from any working directory? If no → add absolute path.
5. For subagent dispatch specifically: am I telling the subagent WHICH skill / phase to follow, not improvising my own version of the work? If no → fix the dispatch prompt.

If any check fails: do NOT save / send / commit. Iterate.

## Reference template — pipeline orchestration prompt skeleton

Use this skeleton when authoring a new cron prompt, manual loop kick-off, or planning doc that drives pipeline work. Replace bracketed sections. Adapt phase numbering for vibe-loop vs work-loop.

```
You are running the [BMAD vibe-loop | dev-team work-loop] pipeline for [PROJECT — Epic/scope].

PROJECT: [/media/bob/C/AI_Projects/PROJECT-PATH]
LOOP TYPE: [vibe-loop (greenfield, full pipeline) | work-loop (brownfield, iterative)]
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

Follow the FULL pipeline as defined in:
/media/bob/C/AI_Projects/hermes-dev-team/skills/dev-team/[vibe-loop|work-loop]/SKILL.md

Each phase / step below is named for navigation; execute the FULL procedure
from the SKILL.md, not an abbreviated version inlined here.

[Enumerate phases / steps by name, each with a one-line reminder of what
it covers — NOT a paraphrase of the procedure itself.]

For the Quinn review specifically (Phase 10c in vibe-loop, Step 10 in work-loop):

Follow the FULL procedure defined in the loop's SKILL.md. DO NOT substitute
an abbreviated checklist. The full procedure is the gate.

Specifically, you MUST:
1. LOAD /media/bob/C/AI_Projects/hermes-dev-team/skills/dev-team/vibe-loop/references/ai-coder-antipatterns.md
   into the review context.
2. COLLECT diff + full source files touched.
3. INVOKE bmad-code-review skill with three parallel reviewer layers
   (Blind Hunter / Edge Case Hunter / Acceptance Auditor). Each layer gets
   the anti-patterns catalog. Each performs the commit-claim audit.
4. SUBAGENT FAILURE HANDLING per the SKILL.md escalation chain (parent
   model → deepseek-r1:32b → inline → HALT). Never fabricate findings.
5. TRIAGE findings: Critical/High → P0, Medium → P1, Low → P2. File
   each as a beads issue (label `quinn-review` for greenfield,
   `epic-{N}-review` for brownfield).
6. RUN THE FIX LOOP: for each P0/P1, claim → Pi fix → verify → land.
7. ANTI-PATTERNS CATALOG MAINTENANCE: any finding not matching an existing
   entry → APPEND new entry to references/ai-coder-antipatterns.md before
   closing this phase.
8. REPORT before proceeding.

This phase / step CANNOT be skipped or abbreviated.

CONSTRAINTS:
- Test suite: [count] tests, all passing. Do not break this.
- [Other project-specific constraints — DO NOT touch X package; Y is in flight]

DELIVERY: [Telegram | file commit | etc]
```

## What to do if you discover instructions that violate these rules

1. If the violation is in a cron prompt's Phase 10c, run `scripts/strengthen-quinn-in-pipelines.py` — idempotent and safe to re-run; it adds the canonical reference for known cron job IDs.
2. If the violation is elsewhere (subagent prompt mid-stream, planning doc, work-loop Step 10), STOP. Replace the inline summary with a reference + enumerate load-bearing steps before continuing.
3. Append a new entry to this skill's `## Known violations` log below citing the context (cron job id, conversation, document path), the bug, and the fix.
4. If the violation is in a cron job that lives ONLY in `~/.hermes/cron/jobs.json` (not in repo `cron/jobs.json`), file a separate issue to promote it into the repo so future drift surfaces in git diffs.

## Known violations (incident log)

### 2026-05-11 — Crispi Family Plan + FlowInCash-Core Epic 10 BMAD Pipelines (cron context)

- **Crons:** `548f363200b8` (Crispi), `536e0749002d` (FC Epic 10)
- **Loop type:** vibe-loop (greenfield-style, even though FC-Core itself is brownfield — these pipelines drive feature implementation as if greenfield within the Epic scope)
- **Bug:** Both contained inline 3-category Phase 10c (Security / Correctness / Completeness) instead of referencing vibe-loop SKILL.md.
- **Impact:** 2026-05-11 batch shipped 3 CRITICAL + 6 HIGH findings (see `dev-team-work-loop/CODE-REVIEW-2026-05-11.md`). The full Phase 10c would have caught all of them via the anti-patterns catalog grep.
- **Fix:** `scripts/strengthen-quinn-in-pipelines.py` ran, replaced both with the canonical reference. Live file backed up at `~/.hermes/cron/jobs.json.bak-pre-quinn-strengthen-*`.
- **Follow-up:** promote both jobs into repo `cron/jobs.json` so future drift surfaces in git diffs.

## Related skills

- `skills/dev-team/vibe-loop/SKILL.md` — greenfield pipeline (full). Phase 10c lives here.
- `skills/dev-team/work-loop/SKILL.md` — brownfield iterative pipeline. Step 10 Quinn lives here.
- `skills/dev-team/vibe-loop/references/ai-coder-antipatterns.md` — the shared catalog Quinn applies in EITHER loop.
- `scripts/sync-cron-jobs.py` — merges repo `cron/jobs.json` into live `~/.hermes/cron/jobs.json`.
- `scripts/strengthen-quinn-in-pipelines.py` — one-shot fix script for the 2026-05-11 incident; safe to re-run after future cron drifts.
