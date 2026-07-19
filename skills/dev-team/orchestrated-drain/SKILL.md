---
name: orchestrated-drain
description: "Central orchestrator skill for autonomous drains. Routes beads to specialist models, drives iterative loop-and-fix until quality is met, and manages multi-tiered escalation without human intervention for code issues."
version: 1.4.9 # Added references/teaser-video-playback-verification.md — browser QA recipe for teaser in-card video playback (a11y ref click ≠ playback; click role=button wrapper + poll video readyState/currentTime/videoWidth); pointer in Social Growth section.
metadata:
  hermes:
    tags: [drain, orchestrator, routing, delegation, beads, autonomous, quality, escalation]
    category: dev-team
---

# Orchestrated Drain (Fullying Autonomous & Quality-Driven Workflow)

Central orchestrator for autonomous bead processing via cron-triggered drains.
Loads the canonical BMAD methodology from `vibe-loop` and layers drain-specific
operational knowledge on top.

## Prerequisites (LOAD IMMEDIATELY — before any bead work)

This skill depends on the canonical BMAD methodology + drain operational overlay.
Load BOTH before doing anything else:

1. **LOAD** `dev-team/vibe-loop` — canonical BMAD pipeline (phases, quality gates, Quinn review). This is the SOURCE OF TRUTH for methodology. Do not restate it here.
2. **LOAD** `dev-team/vibe-loop/references/drain-delegation` — drain-specific operational overlay (exhaustion check pattern, multi-project discovery, routing table, multi-tiered escalation).

After loading those two, continue with the drain-specific operational logic below.

**What this file adds on top of vibe-loop + drain-delegation:**
- Detailed bead triage checks specific to drain context (lines 30+)
- Accumulated real-world pitfalls with concrete scenarios (lines 300+)
- Social Growth / Auto-Research integration patterns
- Drain schedule reallocation procedures
- Tool constraints specific to cron context
- Live-session deferral logic for daytime drains

**What this file does NOT restate:**
- BMAD phase definitions (in `vibe-loop`)
- Methodology philosophy (in `vibe-loop`)
- Per-bead execution lifecycle (in `bead-execution`)
- Quality gate definitions (in `shared-execution`)

## How It Works (Comprehensive Workflow Phases)

When processing beads, this skill drives a powerful, iterative pipeline:

**⚠ Step 0: EXHAUSTION CHECK (MUST RUN BEFORE ANY OTHER TRAIGE)**
```bash
# Run IMMEDIATELY after pre-flight bd list — before ANY bd show calls
EXHAUSTION_COUNT=$(ls ~/.hermes/drain-logs/$(date +%Y-%m-%d)/<project>-*.json 2>/dev/null | xargs grep -l '"exit_reason": "pool-exhausted"' 2>/dev/null | wc -l)
if [ "$EXHAUSTION_COUNT" -ge 2 ]; then
  echo "Pool exhausted $EXHAUSTION_COUNT times today — skipping per-bead triage"
  # Skip to overflow check, then LOG. Do NOT run bd show on any bead.
fi
```
**Why Step 0:** The per-bead classification is identical each run — same beads, same blockers, same skip reasons. Running `bd show` on every bead when exhaustion is already confirmed wastes tokens and Dolt API calls. Check exhaustion FIRST, then decide whether to triage.

---

1.  **Comprehensive Triage & Contextualization (Analyst/Discovery - default profile):**
    *   **Goal:** Thoroughly understand the bead and confirm its readiness for implementation or intervention by a specialist.
    *   **Process:**
        *   **Read Bead & Context:** Analyze title, description, AC, associated files (`story_file`, `test_file`).
        *   **Dynamic Triage:** Apply intricate checks to determine implementability:
            *   **Multi-Project Bead Discovery (CRITICAL for label-targeted cron jobs):** When the cron job targets a specific label (e.g., `appsumo-fast-track`) rather than a specific project, beads may live across multiple project directories. Search all projects before concluding the pool is empty:
                ```bash
                # Search all project directories for beads matching the target label
                for dir in /media/bob/C/AI_Projects/*/; do
                  if [ -d "$dir/.beads" ]; then
                    result=$(cd "$dir" && bd list --state open --flat --label <target-label> 2>/dev/null)
                    if [ -n "$result" ]; then
                      echo "=== $(basename $dir) ==="
                      echo "$result"
                    fi
                  fi
                done
                ```
                Known project locations: `/media/bob/C/AI_Projects/{FlowInCash,FlowInCash-Core,FlowInCash-CloudComm,FlowInCash-Practice,KidSplit,Crispi-app,FliC-MicroApps,Auto-Claude,LivingApp-Sidecar,LivingApp-Platform,BeadsBoard,Crispi-MicroApps,QChat}`. Also check `/home/bob/.beads-planning/` for planning beads. See `references/project-locations.md` for the full directory map.
            *   **Pre-completion checks:** Is it already `closed` (from `bd show`)? Skip.
            *   **Human Action/Gated:** Is it `human-action`, `blocked-by-parent-epic`, `needs-visual-signoff`, `release-cycle-gated`, or `Owner: TEA/human`? Skip, report reason.
            *   **Blocked Dependencies:** `DEPENDS ON` open blockers? Skip.
            *   **Infrastructure Missing/Cross-Repo:** Code, API, or NPM dependency in another repo? Skip, report details.
                *   **Diagnostic for cross-repo package deps:** If a bead references types/exports from another repo (e.g. `@flowincash/cashflow`), verify installation in the TARGET app before claiming:
                    ```bash
                    grep -r "@scope/package-name" package.json client/package.json 2>/dev/null
                    ls packages/<pkg>/ 2>/dev/null || echo "NOT INSTALLED"
                    ```
                    If not installed, the bead needs a setup/install step first — flag as `dependency-blocked` with the specific missing package.
            *   **Stale Bead/Claim/Plan:** Verify claims against codebase, `git log`. Is the bead describing work already done or a plan never built? Auto-close if done, mark `planning-artifact-never-built` if not.
            *   **"Complete existing code" detection:** When a bead is `IN_PROGRESS`, check for untracked implementation files that need tests:
                ```bash
                git ls-files --others --exclude-standard | grep -E "\.(ts|tsx)$" | grep -v __tests__
                ```
                If untracked service/component files exist but no test files, the bead is in "complete existing code" mode — skip IMPLEMENT, go straight to TEST. This prevents re-implementing code that's already written.
            *   **Large Feature/Epic:** If it's an epic or a feature too large for one drain session, skip and recommend decomposition (Tier 3 escalation path).
        *   **Contextualize:** Read `AGENTS.md` (project conventions), identify testing framework, relevant code patterns (from skill `references/`), and relevant errors from past execution attempts.
        *   **Define "Good":** Establish clear, objective success criteria (e.g., "tests in `{{test_file_path}}` must pass with 0 failures", "Quinn Review PASS on diff", "Murat score >= 70"). This forms the concrete target for the loop.
        *   **CRITICAL:** Avoid silent failures by logging clear reasons for skipping non-implementable beads.

2.  **Classify & Route to Initial Specialist (Orchestrator - architect profile):**
    *   **Goal:** Identify the bead's primary task type and select the most capable initial specialist.
    *   **Process:** Using semantic analysis of the bead description, accumulated context, and the Routing Table (below), select the appropriate specialist profile (`code`, `default`, `automation`, `analysis`, `vision`, `video`).
    *   **Self-Handle Complex Decisions:** If the task is primarily "Design architecture," "Plan a feature," or "Fix a complex bug," the orchestrator (architect profile) handles this directly, leveraging its deep reasoning to generate a detailed plan.

3.  **Iterative Implementation & Quality Assurance Loop (Building/Testing/Review Phases):**
    *   **Goal:** Achieve "error-free, high-quality work" as defined by objective test results and rigorous quality gates. Loop until successful or escalation is exhausted.
    *   **Process:** The orchestrator drives an iterative loop (e.g., up to 5 attempts) for implementation, testing, and quality review.
        1.  **Delegate to Specialist - `profile=<profile_name>`:**
            *   `delegate_task` to the selected specialist (e.g., `code` profile for DeepSeek V3.2) for the `IMPLEMENT` phase.
            *   **Context:** Include the bead's description, `AGENTS.md`, `THINK BEFORE ACTING` principles, `CODE QUALITY OVER SPEED` mandate, detailed "definition of good" (test command, expected success state), relevant code snippets, known pitfalls (from `bead-execution` skill's references), and specific feedback from any prior iteration failures or review findings.
        2.  **Specialist Executes & Reports:** The specialist implements, tests locally, and reports preliminary results (success, failure, errors).
        3.  **Orchestrator's Verification (Independent Quality Check):**
            *   **Independent Test Execution:** The orchestrator will **independently run the associated automated tests** (e.g., `npx vitest run {{test_file_path}}`) and `npx tsc --noEmit` regardless of the specialist's claim.
            *   **Initial Pass/Fail:** If tests fail, or new build/type errors are introduced, the current iteration is marked as a failure.
        4.  **Quality Gates (Enforced by `shared-execution` skill):** If tests pass and no build errors:
            *   The orchestrator will trigger the `QUALITY` phase by invoking `shared-execution`'s quality gates. (Quinn & Murat delegated to `analysis` profile).
            *   Quinn Review (P0/P1 findings), Murat Test Quality (score), and Traceability Check are performed.
        5.  **Loop Decision:**
            *   **SUCCESS:** If all quality gates pass (tests pass, build clean, Quinn reports PASS (no P0), Murat's score acceptable), the loop exits.
            *   **FAILURE:** If any quality gate fails, the orchestrator synthesizes detailed feedback and triggers a `re-delegation` to the original specialist (Step 3.1) with explicit instructions to address the identified issues. The loop restarts.
            *   **Max Retries:** If loop exceeds `N` attempts (e.g., 3-5), the orchestrator escalates to Step 4.

4.  **Multi-Tiered Autonomous Escalation (No Human Dead Ends):**
    *   **Goal:** Resolve persistent blockers autonomously through progressively deeper analysis and intervention by higher-tier specialists, ensuring no code-related issues are passed to Bob.
    *   **Process:** If the iterative loop (Step 3) fails to achieve a "right" outcome after maximum retries, the orchestrator (Opus 4.8) initiates a multi-tiered escalation:
        1.  **Tier 1: Specialist with New Approach (`code`, `default` profiles):**
            *   Re-delegate to the *same specialist*, but with instructions to "try a different approach," potentially referencing new patterns gleaned from prior attempts and diagnostics. The orchestrator synthesizes all prior failed attempts, logs, and quality gate feedback.
        2.  **Tier 2: Diagnosis & Research (`analysis` profile):**
            *   If Tier 1 fails, `delegate_task` to the `analysis` profile (Claude Sonnet 4.6).
            *   **Goal:** "Web search the error," "deep dive into logs," "identify patterns of failure," "research related issues" (e.g., GitHub issues, Stack Overflow, changelogs, specific pitfall documentation from `bead-execution` references).
            *   **Context:** Includes all accumulated failure details, logs, diffs, test output.
            *   Feedback from `analysis` agent (diagnostic report, proposed solutions) is used to reinform Tier 1.
        3.  **Tier 3: Deep Reasoning & Rearchitecture (`architect` profile / Opus 4.8):**
            *   If Tier 1-2 efforts fail because the problem requires fundamental architectural or conceptual shifts, the orchestrator (Opus 4.8) performs **"Deep Research & Rearchitect."** This is the **primary "elevator"** for hard problems.
            *   **Goal:** Analyze all accumulated data (code, tests, error logs, research results), challenge assumptions, propose 2-3 alternative architectures/fixes, prototype in isolation.
            *   **Leverage MoA (Mixture of Agents):** If Opus 4.8 (as `architect`) is still stuck on an exceptionally hard, complex reasoning problem, it will invoke `/moa` with `z-ai/glm-5.2` and `google/gemini-3.5-flash` as advisors to achieve multi-model consensus. Opus 4.8 acts as the aggregator.
            *   The outcome of this is a refined approach or a decomposed plan, which then informs further iterations in Step 3 or leads to Step 4.
        4.  **Tier 4: Structured Blocking Bead (Autonomous Resolution - NOT to Bob for code):**
            *   If *all* autonomous escalation fails to resolve the bead (meaning the combined reasoning of Opus and MoA cannot find a path), the orchestrator will **file a P0 blocker Bead issue**.
            *   This bead includes **ALL accumulated research, failed approaches, proposed alternative architectures, and diagnostic context**, tagged `needs-deep-research-round-2`. This ensures that if the problem is genuinely intractable for the current system, the next autonomous session (or a specific targeted intervention) can pick up from a fully informed state. **Crucially, this is still an autonomous resolution – it "hands off" the problem to a future, more informed autonomous session, not a direct manual escalation to Bob for code issues.**

5.  **Final Commit & Close:**
    *   *Only when* Step 3's iterative loop completes successfully (all tests pass, all quality gates are met consistently), the orchestrator commits the changes (`git add -A && git commit`), writes the attestation (`echo "PASS $(git rev-parse HEAD)" > .hermes/sessions/{{bead_id}}.test-result`), and formally closes the bead in `bd` (handling git push/pull/stash as described in `shared-execution` pitfalls).

## Routing Table

| Task Type | Specialist | Model |
|---|---|---|
| Simple file edit | default | Gemini 3.5 Flash |
| Fix a bug (simple) | default | Gemini 3.5 Flash |
| Fix a bug (complex) | architect | Opus 4.8 |
| Build new feature (code) | code | DeepSeek V3.2 |
| TypeScript error | code | DeepSeek V3.2 |
| Python script | code | DeepSeek V3.2 |
| Write tests | code | DeepSeek V3.2 |
| Refactor code | code | DeepSeek V3.2 |
| Design architecture | architect | Opus 4.8 |
| Plan a feature | architect | Opus 4.8 |
| Review a PR | analysis | Sonnet 4.6 |
| Research a topic | analysis | Sonnet 4.6 |
| Verify video frame | vision | Gemini 3.1 Pro |
| Read a screenshot | vision | Gemini 3.1 Pro |
| Composite video | video | Gemini 3.5 Flash |
| Browser automation | automation | GPT 5.6 Luna |
| UI testing | automation | GPT 5.6 Luna |
| Web scraping | automation | GPT 5.6 Luna |

## 📈 Social Growth & Auto-Research Integration (The "Automation" & "Analysis" Loop)

> **Teaser/landing-page video click-through QA** (beads like Crispi `sw9q`,
> FlowInCash `ajp`/`vuw` — "confirm in-card playback in a real browser"): see
> `references/teaser-video-playback-verification.md`. Key gotcha: clicking the
> accessibility-tree "Play video" ref often does NOT start playback — click the
> actual `role=button` wrapper via `browser_console` and poll the `<video>`
> element's `readyState`/`currentTime`/`videoWidth` to confirm pixels loaded.
> These are fully autonomous browser QA tasks a daytime drain can complete and
> record via `bd comment` (leave the bead OPEN if a human-only creative sub-task
> like audio re-VO remains).
>
> **⚠ Triage FIRST reads the COMMENTS, not just the description.** A teaser/QA
> bead left OPEN often has its automated portion ALREADY DONE by an earlier
> drain — recorded as a `bd comment` (e.g. "Browser click-through check DONE …
> Result: PASS … REMAINING (needs Bob): optional VO re-record"). The bead stays
> OPEN only because a human/creative sub-task is unresolved. Do NOT re-run the
> browser QA. `bd show <id>` prints COMMENTS at the bottom — scan them during
> triage; if the automated work is already logged PASS and only a human sub-task
> remains, skip as `HUMAN ACTION` citing the prior comment's date. Real example
> (2026-07-17): Crispi `sw9q` browser click-through was completed by an earlier
> daytime drain (all 4 cards PASS, readyState 4); only the optional T2 VO
> re-record remained — correctly skipped without re-testing.

When Bob requests mapping, validating, or running a social-media rotation combined with Sidecar metrics analytics and Auto-Research testing:

1. **Verify Sidecar Metric Stream:** Before executing campaign pivots, query your local database or live site (using `sidecar-production-health` logs or target APIs) to extract waitlist registration volumes and conversion ratios (`Clicks-to-Waitlist / Total Views`).
2. **Diagnosis of Stale Campaigns:** If conversion ratios drop below the `3.0%` threshold on a specific teaser referer (e.g. `utm_source=tiktok_T2_Emily`):
    - **Trigger Auto-Research (`deep_research.py`):** Analyze recent local UI/mockup changes, run multiple targeted research queries, challenge structural assumptions, and write an alternative proposal to `.hermes/sessions/[teaser-id].deep-research.md`.
    - **Determine Knob Alignment:**
        - **Placement/Schedule (Algorithmic):** If watch completion is high but impressions are low, autonomously reschedule candidate crons (shift posting slot by 3-5 hours or rotate description metadata tags).
        - **Creative/UX (Composite):** If immediate drop-off occurs on Act 1, log a high-priority P0 Creative Bead requesting mockups modification from Bob's Bmad UX + Claude Code background developers loop.
3. **Automated Teaser bakes:** Ensure that your local python render pipelines (`bake_teaser.py`) can ingest newly generated screen mockups and composite them into the tracked green-screen plates using FFmpeg coordinates cleanly without manual intervention.
4. **Reporting:** Write all metrics drifts, automated schedule changes, and creative requirements directly into the morning handoff summaries.

## Batch Execution (Enhanced for Quality & Iteration)

When processing multiple beads:
1.  **Prioritized Triage:** Perform comprehensive triage (Step 1) on all candidate beads, prioritizing P0 → P1 → P2 → P3.
2.  **Execute Beads Sequentially (with full loop):** For each implementable bead, execute the "Autonomous Bead Execution Cycle" (Steps 1-5 above). This ensures each bead gets its full quality review and iterative fix attempts.
3.  **Don't stop between beads:** Continue processing the next bead as long as implementable beads exist and resource limits allow.
4.  **Summarize ONCE at the very end:** Provide a comprehensive report detailing all processed beads, successful fixes, and any beads that entered the escalation chain (including reasons for status and next steps).

## Drain Schedule Reallocation

When Bob requests moving drain slots between projects (via voice transcription or direct instruction):

1. **Parse intent:** Identify which project to remove and which to add.
2. **Check current state:**
    - List drain jobs targeting the project: `hermes cron list | grep -B1 -A5 <project>`
    - Check bead pools across all projects to determine need:
        ```bash
        for dir in /media/bob/C/AI_Projects/*/; do
          if [ -d "$dir/.beads" ]; then
            count=$(cd "$dir" && bd list --state open --flat 2>/dev/null | wc -l)
            echo "$(basename $dir): $count open beads"
          fi
        done
        ```
3. **Interpret vague directives:** When Bob says "the other two" or similar, compare bead counts to determine which projects have the most need (highest open bead count with fewest drain slots). Cross-reference with `references/project-locations.md` for project context.
4. **Repurpose jobs via `hermes cron edit`:** Change workdir and name — this preserves schedule, skills, and delivery settings:
    ```bash
    hermes cron edit <job_id> --name "<New Name>" --workdir /media/bob/C/AI_Projects/<new-project>
    ```
5. **Verify:** Run `hermes cron list` and grep for the new project name to confirm changes took effect.
6. **Flag issues:** Note any config errors (e.g., provider mismatches) in the report for Bob to address.

**Prefer edit over remove+create:** `hermes cron edit` preserves the job's schedule, skills, delivery target, and repeat settings. Only use `hermes cron remove` + `hermes cron create` when the schedule or other settings also need to change.

## ⚠ Tool Constraints in Cron Context

When running as a scheduled cron job (no user present), certain tools are unavailable:

- **`execute_code` is BLOCKED** — Security approval cannot be obtained without a user. Do NOT attempt `execute_code` for batch processing, log writing, or multi-step logic. Use `terminal` for commands and `write_file` for file creation instead.
- **`delegate_task` works** — Subagent delegation is available in cron context.
- **`skill_view` works** — Reading skills is available.
- **`bd | python3` is BLOCKED by Tirith** — The security scanner flags `bd list | python3 -c "..."` as "Pipe to interpreter: downloaded content executed without inspection." Use `grep`, `awk`, or `sed` instead of piping to python. For JSON filtering, use `bd list --json` with `grep` or `jq` if available.

**Workaround for log writing:** Use `write_file` to create JSON logs and markdown reports directly. Do not rely on `execute_code` for any step in the drain workflow.

**Workaround for bead filtering:** Use `grep` patterns instead of python:
```bash
# Instead of: bd list --json | python3 -c "..."
# Use:
bd list --flat --label <label> --state open
bd list --flat 2>/dev/null | grep -i "keyword"
```

## Persistent Pool Exhaustion Pattern (EARLY-EXIT)

When 3+ consecutive drain sessions report `exit_reason: "pool-exhausted"`, the backlog needs human intervention. **Check this BEFORE doing any per-bead triage:**

```bash
# STEP 1: Run this IMMEDIATELY after the pre-flight bd list — before any bd show calls
# Count FILES with pool-exhausted exit_reason, NOT matching lines (a single log
# file mentions "pool-exhausted" in exit_reason AND issues array, inflating grep -c)
EXHAUSTION_COUNT=$(ls ~/.hermes/drain-logs/$(date +%Y-%m-%d)/<project>-*.json 2>/dev/null | xargs grep -l '"exit_reason": "pool-exhausted"' 2>/dev/null | wc -l)
if [ "$EXHAUSTION_COUNT" -ge 2 ]; then
  # SKIP full triage — copy the skip list from the most recent log and increment count
  echo "Pool exhausted $EXHAUSTION_COUNT times today — skipping per-bead triage"
  # Jump directly to writing the drain report (Step 7 LOG)
fi
```

**Why early exit matters:** Running `bd show` on every bead when the pool has been exhausted 7+ times today wastes tokens and time. The per-bead classification is identical each run — same beads, same blockers, same skip reasons. The drain should:
1. Check exhaustion count **immediately after `bd list`** (not after full triage)
2. If ≥2 exhausted logs exist today for this project: **skip all `bd show` calls**
3. Reuse the skip list and reasons from the most recent log
4. Write the report with an incremented exhaustion count

**Trigger point in the drain flow:**
```
Pre-flight Check → bd list → IF exhaustion_count >= 2: CHECK OVERFLOW → then SKIP to LOG
                             ELSE: continue with full per-bead triage
```

**Overflow check after early exit:** When the primary project's pool is exhausted,
the drain should still check overflow/fallback projects before writing the final
report. Use the reusable script (single invocation, all projects at once):

```bash
# Use known path or resolve via skill_view
bash ~/.hermes/skills/dev-team/orchestrated-drain/scripts/overflow-quick-triage.sh \
  /media/bob/C/AI_Projects/FallbackProject1 /media/bob/C/AI_Projects/FallbackProject2
```

This reports open/blocked/free counts per project in one call. Do NOT run
manual `bd list | grep` patterns per project — the script does it faster and
more reliably. See `scripts/overflow-quick-triage.sh` for the implementation.

**Do NOT** run `bd show <bead-id>` for every bead when exhaustion is already confirmed. Each `bd show` is an API call to Dolt and adds latency + tokens for no new information. For overflow projects, a quick `bd show` on 2-3 promising P2 beads is acceptable to assess implementability.

**⚠ Overflow exhaustion early-exit:** When the primary project is exhausted AND overflow projects also show zero implementable beads after a quick grep check (comprehensive blocking patterns + `[task]`/`[bug]` count), skip per-bead `bd show` calls in overflow too. Same logic as Step 0: the classification won't change between runs. Just count open beads, run the blocking-patterns grep, and if blocked + features + stories > total, report exhaustion immediately. This saves ~6-10 `bd show` calls per overflow project when the pool is clearly non-implementable.

### Overflow Execution Flow (when overflow finds implementable work)

When the overflow check finds an implementable bead in a fallback project,
**execute it fully** — do NOT just report it and move on. The overflow bead
goes through the same complete lifecycle as primary-project work:

```
1. Claim        → bd update <bead-id> --claim (in the overflow project directory)
2. Implement    → write code, follow project conventions (AGENTS.md, tsconfig, vitest)
3. Test         → run full test suite (not just new tests — check for regressions)
4. Quality      → self-review diff + traceability check (proportionate gates for small diffs)
5. Commit       → git add -A && git commit --no-verify
6. Close        → bd close <bead-id> --reason "..."
7. Push         → git pull --rebase && git push (in the OVERFLOW project, not primary)
8. Log          → include overflow summary in drain report
```

**Key differences from primary-project execution:**
- **Working directory changes:** The drain operates in the overflow project's
  directory for code changes, tests, and git operations. Switch back to the
  primary project directory for the final drain log.
- **Git branch verification:** Confirm you're on `main` in the overflow project
  (same branch-checking pitfall applies).
- **Quality gates:** Same proportionate rules — self-review for small diffs,
  full Quinn/Murat for large or security-sensitive changes.
- **Test command:** Use the overflow project's test runner (e.g., `npx vitest`
  for LivingApp-Sidecar, not the primary project's `npx jest`).
- **Attestation:** Write to the overflow project's `.hermes/sessions/` directory.
- **Push:** Push to the overflow project's remote, not the primary.

### ⚠ Pitfall: Cross-repo code target — bead in Project A, code in Project B

When a bead is filed in Project A but its description says "Code path:
@scope/package" where the package lives in Project B, the implementation
goes into Project B — not Project A. The lifecycle is split across repos:

```
1. Claim        → bd update <bead-id> --claim (in Project A where bead is filed)
2. Implement    → write code + tests in Project B's package directory
3. Test         → run tests in Project B (npx vitest -p <package>)
4. Commit       → git add + commit in Project B (where code lives)
5. Close        → bd close <bead-id> in Project A (where bead is filed)
6. Push         → git push in BOTH Project A AND Project B
7. Attestation  → write to Project B's .hermes/sessions/ (code lives there)
```

**Real scenario (2026-07-14):** Crispi-app drain overflow found `beads_FlowInCash-7np`
(P1 Business-Day Engine) filed in FlowInCash. Bead description said "Code path:
@flowincash/cashflow date utility libraries" — that package lives in FlowInCash-Core.
Implementation went into `FlowInCash-Core/packages/cashflow/src/business-day-engine.ts`.
Bead claimed and closed in FlowInCash; code committed and pushed in FlowInCash-Core.

**Detection:** When triaging a bead, check if "Code path" or "DEPENDS ON" references
a package from another repo:
```bash
# Check if the referenced package exists locally
ls packages/<pkg>/ 2>/dev/null || echo "NOT LOCAL — check other repos"
# Check if the package is imported from another repo
grep -r "@scope/package-name" package.json 2>/dev/null
```

**If the code target is in another repo:**
- Verify the other repo has the package (`ls packages/<pkg>/` in the other repo)
- Verify the other repo is on `main` and has a clean working tree
- Implement in the OTHER repo, commit there, push there
- Claim/close the bead in the ORIGINAL repo (where it's filed)
- Write attestation in the OTHER repo (where code lives)
- Push BOTH repos

**Why this matters:** Without this pattern, the drain either:
- Implements in the wrong repo (Project A doesn't have the package)
- Commits code changes to Project A's repo (contamination)
- Fails to push the actual code changes (committed to wrong place)

**Why execute overflow beads (not just report them):**
1. The drain has token budget — spending it on "here's what's blocked" with no
   action wastes the cycle. One completed bead is more valuable than a report.
2. Overflow beads are often P1/P2 bugs or small tasks — high value, low effort.
3. The primary pool being exhausted doesn't mean the drain has nothing to do.

**Real scenario (2026-07-13):** Crispi-app drain found all 11 beads blocked.
Overflow to LivingApp-Sidecar found `dnq` (P1 security bug: RL routes lack
service-to-service auth). Clear plan in bead description. Completed in one
cycle: added HS256 JWT verification, auth middleware, 18 tests (all passing),
full suite green (704 tests), pushed to `origin/main`.

**Drain log format for overflow execution** (use `overflow_check` per drain-logger schema):
```json
{
  "overflow_check": {
    "projects_checked": ["LivingApp-Sidecar"],
    "LivingApp-Sidecar": {"open_beads": 11, "implementable": 1, "reason": "Found implementable P1 security bead"}
  }
}
```

**Report the pattern explicitly** in the drain log `issues` array using a standardized string format:
```json
"issues": [
  "6th consecutive pool-exhausted session for Crispi-app",
  "All 9 beads blocked: 2 human-gated, 2 post-beta (@azrlb), 1 blocked dep, 1 epic needing decomposition, 1 blocked on Story 07",
  "FlowInCash overflow: 29 open beads, ALL Owner: azrlb",
  "LivingApp-Sidecar overflow: 9 open beads — epic jqt (RL Training Platform) needs decomposition",
  "Recommended: close stale beads, decompose epics, file new pure-code beads"
]
```
The morning handoff reads these `issues` strings to track exhaustion trends and suggest interventions. Use `"Nth consecutive pool-exhausted session for <project>"` as the first issue line.

**⚠ MANDATORY: Use standardized skip categories in `beads_skipped`.** Every skip reason MUST start with a category prefix in CAPS from the drain-logger skill: `HUMAN ACTION`, `BLOCKED`, `GATED`, `LARGE FEATURE`, `CROSS-REPO`, `ASSIGNED-LOCKED`, `DEFERRED`, etc. Example: `"HUMAN ACTION — P0 legal gate: allergist attestation"` NOT `"Human action — allergist/owner attestation signature"`. See `dev-team/drain-logger` for the full category table. The morning handoff greps these prefixes to aggregate trends across drains.
3. **Categorize the blockers** — are beads gated, placeholders, epics needing decomposition, or human-action?
4. **Recommend specific actions to Bob:**
   - Close placeholder/garbage beads (e.g., title "wprl" with no description)
   - Decompose large epics into implementable child beads
   - Confirm post-beta metrics to ungate gated beads
   - Close or defer beads blocked on missing dependencies
5. **Do NOT force-claim non-implementable beads** just to produce activity — this wastes tokens and produces no value

### All Projects Exhausted — Combined Scenario

There is a distinct scenario from simple "pool-exhausted" (empty pool): the primary
project has beads, but **ALL are human-gated/blocked**, AND overflow projects also have
no implementable beads. This is NOT "pool-exhausted" in the traditional sense (the pool
isn't empty — it's just not machine-implementable).

**Detection pattern:**
```
Pre-flight Check → bd list (primary) → beads found → triage each → ALL blocked
→ Check overflow projects → also all blocked → exit_reason: "pool-exhausted"
```

**Key distinction:** `bd ready` returns beads (pool isn't empty), but every single one
requires human action, gated confirmation, or is blocked on external dependencies. The
drain must still check overflow before reporting exhaustion.

**Drain log format for this scenario:**
- `exit_reason`: `"pool-exhausted"` (same as empty pool — the result is the same)
- `beads_skipped`: Array of objects with `{id, reason}` for each blocked bead
- `overflow_check`: Include overflow project results (see drain-logger schema)

**Recommended actions for Bob** (add to drain report):
1. Close stale/placeholder beads that will never be implementable
2. Confirm gated metrics to unblock post-beta deprecation beads (dzr6, b6ct)
3. Decompose large epics (e.g., 6pqo family plan) into smaller implementable beads
4. File new pure-code beads if the backlog is genuinely exhausted of implementation work

### ⚠ Overflow Exhaustion with Ready-but-Non-Implementable Beads

A variant of "All Projects Exhausted" where overflow projects have **large pools of
ready beads** (e.g., 37 in FlowInCash) but **zero are machine-implementable**. The
drain sees `bd ready` return many results, but every bead falls into a non-implementable
category. This is the most confusing exhaustion scenario because the pool LOOKS full.

**Detection pattern:**
```
Pre-flight Check → bd list (primary) → beads found → ALL blocked/human-gated
→ Check overflow projects → bd ready returns N beads (N > 0)
→ Triage overflow beads → ALL non-implementable → exit_reason: "pool-exhausted"
```

**Non-implementable categories to check in overflow projects:**
| Category | Example | Detection |
|----------|---------|-----------|
| Human tasks | App Store submission, UX review, legal counsel | `Owner: Bob Banks` or description says "requires Bob" |
| Cross-repo dependencies | hermes-sidecar, FlowInCash-Core packages | Bead references types/exports from another repo |
| Feature-branch-only | Code exists on `vibe/*` branch, not `main` | `git ls-files --error-unmatch <file>` fails |
| Deferred | Marked deferred by Bob | `deferred` in title or labels |
| Missing description | `bd show` returns empty | Empty DESCRIPTION field |
| Epic parents | Parent beads whose children are blocked | Has CHILDREN that are blocked/open |
| Blocked dependencies | `DEPENDS ON` open blockers | `bd show` shows blocked status |
| Large features | `[feature]` type beads spanning multiple files/services | `[feature]` in brackets — needs decomposition before drain |
| Epic stories | `[story]` type beads under a parent epic | `[story]` in brackets with `parent:` — epic needs decomposition first |
| Planning beads | `beads-planning-*` prefix, PRD/design/documentation tasks | Prefix `beads-planning-` or description is planning/design only — no code |

**Why this matters:** A drain that sees 37 ready beads in an overflow project might
waste significant tokens triaging each one, only to find none are implementable. The
early-exit pattern (exhaustion count ≥ 2) helps for the PRIMARY project, but overflow
projects need their own quick triage. Use `bd list --state open --flat` + grep for
owner/deps/labels to快速 classify without calling `bd show` on every bead.

**Quick overflow triage — use the reusable script:**
The script is at `scripts/overflow-quick-triage.sh` relative to the skill
directory. Resolve the absolute path using `skill_view` or resolve from
`~/.hermes/skills/dev-team/orchestrated-drain/scripts/overflow-quick-triage.sh`:
```bash
# Option 1: known path (works on Bob's setup)
bash ~/.hermes/skills/dev-team/orchestrated-drain/scripts/overflow-quick-triage.sh \
  /media/bob/C/AI_Projects/FlowInCash /media/bob/C/AI_Projects/LivingApp-Sidecar

# Option 2: if skill_view was called, use the skill_dir from linked_files
bash /local-AI-Stack/home-hermes/skills/dev-team/orchestrated-drain/scripts/overflow-quick-triage.sh \
  /media/bob/C/AI_Projects/FlowInCash /media/bob/C/AI_Projects/LivingApp-Sidecar
```
This replaces the 3-command manual pattern (grep → count features → count tasks)
with a single invocation that reports open/blocked/free counts per project.

**⚠ USE THE SCRIPT — do NOT replicate it manually.** The drain should NOT run
3 separate `bd list | grep -ciE` commands per overflow project when the script
does the same thing in one call. Manual triage wastes 2-3 tool calls per project.
If you cannot find the script path, fall back to the manual pattern below — but
always attempt the script first.

**Manual fallback (inline):**
```bash
# Fast classify ALL blocking conditions (not just "Owner:" and "blocked by")
cd /path/to/overflow-project && bd list --state open --flat 2>/dev/null | grep -ciE \
  "Owner:|blocked by|blocked on|post-beta|DO NOT|@azrlb|@hermes-dev-team|human-action|needs-visual|release-cycle|deferred|\[feature\]|\[story\]"
# How many are tasks (potential code tasks)?
cd /path/to/overflow-project && bd list --state open --flat 2>/dev/null | grep -c "\[task\]"
# How many are bugs (potential code tasks)?
cd /path/to/overflow-project && bd list --state open --flat 2>/dev/null | grep -c "\[bug\]"
```
If blocked + large-features + epic-stories > total, the overflow project is also exhausted.

**⚠ WARNING — Do NOT use simple `grep -v "Owner:\|blocked by"` to find "available" beads.** This misses non-obvious blocking patterns. See Pitfall below.

### ⚠ Pitfall: `bd list --state open` may show beads as open when `bd show` reports them CLOSED

Dolt database synchronization lag can cause `bd list --state open --flat` to include beads
that `bd show` reports as CLOSED (or vice versa). This happens when:
- A previous drain session closed the bead via `bd close` but the Dolt commit hasn't propagated
- The JSONL file and Dolt DB are out of sync (Dolt is source of truth)

**Impact:** Triage wastes time calling `bd show` on beads that are already closed.

**Mitigation:** When `bd show` reports a bead as CLOSED but `bd list` showed it as open:
- Trust `bd show` (Dolt is source of truth) — skip the bead
- Log the discrepancy as a note in the drain report
- Do NOT attempt to close the bead again (it's already closed)

**Detection:** `bd show <bead-id>` returns status CLOSED while `bd list --state open` included it.

### ⚠ Pitfall: `bd list --flat` output format breaks bracket-based priority grepping

`bd list --flat` output embeds the status icon INSIDE the priority brackets:
```
○ Crispi-app-56jv [● P1] [task] - Engage food-safety/product-liability counsel
● Crispi-app-3h6q [● P3] [task] @hermes-dev-team - cwu3/Shop: deprecate legacy pages
```
Here `○` = unassigned/open, `●` = assigned/blocked, `◐` = in-progress. The priority (`P1`, `P3`) sits AFTER the status icon inside `[● P1]`, NOT as standalone `[P1]`.

**Broken grep:** `bd list --flat | grep -iE "\[P[12]\]"` — looks for literal `[P1]` or `[P2]` but the actual text is `[● P1]` or `[○ P1]`. Returns nothing. ALSO, the status icons (`○`, `●`, `◐`) are multi-byte Unicode characters that can corrupt byte-level grep matching even for simpler patterns like `grep "P3"`.

**Working alternatives:**
```bash
# Grep for priority anywhere in the line (simple, reliable)
bd list --flat | grep "P2\]"
# Or grep for the priority suffix before the bracket close
bd list --flat | grep -E " P[12] \]"
# If grep still fails due to Unicode bytes, pipe through cat -v first
bd list --state open --flat 2>/dev/null | cat -v | grep -i "P3"
```

**⚠ Important:** `bd list --flat --label P2` filters by USER-DEFINED labels
(e.g., `appsumo-fast-track`, `epic-cashflow-engine`), NOT by priority level.
Priority (P0-P4) is embedded in the bracket format `[● P3]` and is NOT a
label. Using `--label P2` will return empty even when P2-priority beads exist.
Always use grep-based filtering for priority levels.

**Why this matters:** Drains targeting specific priorities (e.g., "process P2/P3 beads") waste 2-3 grep attempts before falling back to manual inspection. Use label-based filtering (`--label P2`) when available; fall back to suffix-pattern grep (`P2\]`) otherwise.

### ⚠ Pitfall: `bd ready` false positives — beads reported as unblocked when they're gated

`bd ready` checks formal dependency chains (DEPENDS ON) but does NOT inspect
bead descriptions for human-imposed gates like "release-cycle-gated", "post-beta",
"Owner: azrlb", or "DO NOT execute until Bob confirms". The tool returns these
beads as "ready with no active blockers" even though they're clearly not
implementable by an automated drain.

**Real scenario (2026-07-11):** `bd ready` reported 7 beads as ready in
Crispi-app. Three P3 beads were listed as ready, but all were gated:
- 6pqo: large feature/epic needing decomposition (family plan multi-user)
- dzr6: assigned to @azrlb + "DO NOT execute until Bob signals metrics green"
- b6ct: assigned to @azrlb + "DO NOT execute until Bob confirms phase 5 metrics"

**Mitigation:** When `bd ready` returns beads, ALWAYS cross-check each bead's
description and acceptance criteria for gating conditions:
```bash
bd show <bead-id> 2>/dev/null | grep -iE "DO NOT|gated|post-beta|assigned to|human-action|blocked on"
```
If gating language is found, skip the bead even if `bd ready` says it's ready.
Do NOT trust `bd ready` as the sole implementability signal — it only checks
formal dependency chains, not human-imposed process gates.

**Impact on pool-exhausted detection:** Without this cross-check, a drain might
see `bd ready` return results and waste time triaging beads that are actually
blocked, or worse, claim and attempt to implement a gated bead.

### ⚠ Pitfall: `bd list --flat` does NOT include Owner field — grep-based owner filtering is unreliable

`bd list --flat` output shows the status icon, priority, type, and title — but does
NOT include the `Owner:` field that `bd show` displays. This means filtering by
owner assignment via grep on flat list output misses beads that ARE assigned to
human developers.

**Real scenario (2026-07-14):** FlowInCash had `beads_FlowInCash-rtb` in flat list:
```
○ beads_FlowInCash-rtb [● P3] [task] - annual-bills-010-c: Wire annual-bills-detector...
```
Running `grep -vE "Owner:|@Bob|@azrlb"` returned this bead as "unblocked." But
`bd show beads_FlowInCash-rtb` revealed `Owner: azrlb` — it's human-gated.

**Why it happens:** The `bd list --flat` format embeds status/priority/type in brackets
but omits the owner field entirely. The owner is only visible via `bd show <id>`.

**Mitigation:** When filtering for "available" beads from `bd list --flat` output,
do NOT rely on `grep -v "Owner:"` to exclude human-assigned beads. Instead:
1. Use the comprehensive blocking pattern grep (catches `@azrlb` in titles)
2. For beads that pass grep, run `bd show <bead-id>` to verify owner
3. Use the `overflow-quick-triage.sh` script which handles this correctly

**Impact:** Without this check, drains may claim beads that are assigned to human
developers, causing merge conflicts or wasted implementation cycles.

### ⚠ Pitfall: Grep-based triage classification misses non-obvious blocking conditions

Using `grep -v "Owner:\|blocked by"` to find "available" beads is UNRELIABLE.
The grep only catches explicit `Owner:` and `blocked by` strings, missing many
other blocking conditions that appear in bead descriptions.

**Real scenario (2026-07-12):** Crispi-app had 11 open beads. Running:
```bash
bd list --state open --flat 2>/dev/null | grep -vE "Owner:|blocked by|@azrlb|DO NOT"
```
returned 7 beads as "available." Manual review showed ALL 7 were actually blocked:
- `e7a7`: "blocked on Story 07" — grep missed "blocked on" (not "blocked by")
- `3h6q`: "(post-beta)" in description — grep missed post-beta gating
- `dzr6`, `b6ct`: assigned to @azrlb + post-beta — grep missed @azrlb in title
- `e9gf`, `ng45`, `6pqo`: large features needing decomposition — not caught by any pattern

**Complete blocking patterns to check:**
```bash
# Use this comprehensive pattern instead of simple grep -v
bd list --state open --flat 2>/dev/null | grep -ciE \
  "Owner:|blocked by|blocked on|post-beta|DO NOT|@azrlb|@hermes-dev-team|human-action|needs-visual|release-cycle|deferred"
```

**Why this happens:** Bead descriptions use varied language for blocking:
- `blocked by: <id>` (formal dependency)
- `blocked on Story 07` (informal dependency)
- `(post-beta)` in parentheses (process gate)
- `@azrlb` or `@hermes-dev-team` in title (assignment lock)
- Large features without decomposition (too big for drain)

**Impact:** Drains waste tokens triaging beads that are clearly non-implementable,
or worse, claim and attempt to implement blocked beads.

**Mitigation:** Always use the comprehensive grep pattern above. When in doubt,
run `bd show <bead-id>` on a sample of "available" beads to verify classification.

### ⚠ Pitfall: Triage misclassification — "depends on X" vs "X exists locally"

When a bead says "depends on @flowincash/cashflow from Core" or similar, DON'T
assume the dependency is missing without checking the local codebase. A previous
session may have created a LOCAL implementation (service + component) that makes
the bead partially or fully implementable without the Core package. The previous
drain log may have classified it as "dependency-blocked" when it was actually
"needs integration + tests."

**Verification step during triage (add to the cross-repo diagnostic):**
```bash
# Search for the component/service locally BEFORE marking as dependency-blocked
grep -rn "TieredLight\|TieredObligation\|<search-term>" src/ client/src/ --include="*.ts" --include="*.tsx" -l
# If files exist, check if tests exist
find . -name "*<SearchTerm>*" -name "*.test.*"
# Check if the component is actually imported/used anywhere
grep -rn "import.*<ComponentName>" client/src/ --include="*.tsx" --include="*.ts"
```

**Classification matrix:**
| Bead says | Local code exists? | Local tests exist? | Integrated in page? | Real status |
|-----------|-------------------|-------------------|-------------------|-------------|
| "depends on X" | Yes, full | Yes, passing | Yes | Possibly closable — verify AC |
| "depends on X" | Yes, full | No | No | "Complete existing code" mode — needs tests + integration |
| "depends on X" | No | No | No | Genuinely dependency-blocked |
| "depends on X" | Partial (service only, no UI) | Yes | No | Needs UI integration — larger scope, may exceed drain |

This distinction matters because "needs integration + tests" IS implementable
(just larger scope), while "dependency-blocked" is NOT implementable at all.

### ⚠ Pitfall: Epic closure when all children are done

When triage finds an epic whose children are ALL closed (e.g., `3/3 complete — eligible for close`), this is a **bookkeeping closure**, not an implementation task. The orchestrator should:
1. Verify all children are actually closed via `bd show <child-id>`
2. Verify the implementation commits exist in git (`git log --oneline` for child bead IDs)
3. Write test attestation: `echo "PASS $(git rev-parse HEAD)" > .hermes/sessions/<epic-id>.test-result`
4. Close the epic: `bd close <epic-id> --reason "All N children closed with passing tests. <summary>"`
5. Commit bead metadata: `git add .beads/issues.jsonl && git commit --no-verify -m "chore: close <epic-id>"`
6. Push (with stash/pop if unstaged changes exist — see shared-execution pitfall)

**Do NOT delegate to a specialist for epic closure** — there is no code to implement. The orchestrator handles this directly as a triage/bookkeeping step.

### ⚠ Pitfall: "Complete existing code" on a feature branch — code exists but isn't on the current branch

The "complete existing code" detection (checking `git ls-files --others` and `git diff --name-only`) only finds untracked or uncommitted files. It MISSES the case where implementation code is committed but on a different branch (e.g., `vibe/qbo-capability-probe`) and NOT merged to `main` or the drain's working branch.

**Real scenario (2026-07-11):** `TieredObligationLights.tsx` (287 lines) existed in `client/src/components/financial/` and was committed — but only on branch `vibe/qbo-capability-probe`, not on `main`. The bead `beads_FlowInCash-jvc` (Story 1.8) was classified as potentially "complete existing code" because `find` located the file. But the component was unreachable from the drain's working branch.

**Detection:** When `find` or `grep` locates implementation files for a bead, verify they are on the CURRENT branch:
```bash
# Check if the file is tracked on the current branch
git ls-files --error-unmatch <file-path> 2>/dev/null
# If exit code != 0, the file is NOT on this branch
# Also check: is the file on main?
git log main --oneline -- <file-path> 2>/dev/null | head -3
# Empty output = file has never been on main
```

**If code exists on a feature branch but not the current branch:**
- The bead is NOT "complete existing code" — the code isn't accessible
- Flag as `feature-branch-only` with the branch name
- Do NOT try to cherry-pick or merge feature branch code during a drain — that's a separate task
- If the feature branch is stale, note it in the drain report for Bob

**Why this matters:** Without this check, the drain wastes cycles trying to test/import code that isn't in the working tree, or worse, incorrectly closes a bead as "verify and close" when the code isn't actually available.

### ⚠ Pitfall: Drain running on wrong git branch

Cron jobs inherit the working directory state from the last session. If a
developer was working on a feature branch (e.g., `vibe/fr14-conversational-nlp`)
when the cron job fires, the drain operates on that branch — not `main`.

**Impact:** Code changes, commits, and bead closures land on a feature branch
instead of the default branch. The drain may also encounter pre-existing
uncommitted modifications (e.g., `vitest.config.ts`) from the prior session
that are unrelated to bead work.

**Detection:** At the START of every drain, before any bead work:
```bash
cd /path/to/project
CURRENT_BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(git remote show origin 2>/dev/null | grep "HEAD branch" | awk '{print $NF}')
echo "Current: $CURRENT_BRANCH | Default: $DEFAULT_BRANCH"
```

**Mitigation:**
- If on a feature branch: `git stash` any unrelated changes, then
  `git checkout main && git pull --rebase` before starting bead work
- If checkout fails (dirty tree): note the branch mismatch in the drain
  report as an issue — do NOT force-switch and lose work
- Pre-existing modifications to tracked files (like `vitest.config.ts`) from
  prior sessions should be noted in the drain report but NOT committed as
  part of bead work

**Why this matters:** Without branch verification, drain commits scatter
across feature branches instead of landing on `main`, and bead closures
reference commits that aren't on the default branch.

### ⚠ Pitfall: Overflow bead is implementable but its repo has a LIVE session (daytime-drain hazard)

A **daytime** drain (unlike overnight) frequently overflows into a repo where
a human is actively working RIGHT NOW. The overflow bead may be genuinely
implementable pure code — but committing/pushing into a repo with uncommitted
live-session work risks the exact "merge-conflict catastrophe" the workflow
guards against. This is a **timing conflict, not a permanent lock** — the bead
is a valid target for the next clean-tree (overnight) drain.

**Detection — check working-tree freshness BEFORE claiming any overflow bead:**
```bash
cd /path/to/overflow-project
git status --short                       # any dirty tracked files?
# How recently were the dirty files touched? (active session vs stale leftover)
git log -1 --format="%h %cr %s"          # last commit age
stat -c '%y %n' <dirty-file>             # mtime of each modified file — compare to `date`
```
- Dirty files modified **within the last ~1-2 hours** ⇒ treat as an ACTIVE live
  session. Do NOT commit/push here on a daytime drain. Defer the bead.
- Dirty files that are **stale leftovers** (hours/days old, or clearly prior-drain
  artifacts like `.hermes/`, `_output/`) ⇒ safe to stash/work/pop per the
  standard overflow flow.

**Response when a live session is detected:**
1. Do NOT `git stash` a live human's uncommitted work to force your own commit
   through — that disrupts their session.
2. Record the bead as implementable-but-deferred with a precise reason, e.g.
   `"DEFERRED — <id> is valid pure-code work (deps confirmed on main) but FlowInCash
   working tree is dirty from an active live session (files modified ~50 min ago);
   daytime drain must not commit into live work. Retry on overnight drain."`
3. Set `overflow_check.<project>.implementable` to the true count (>0) but explain
   the deferral in `reason` — this is MORE accurate than marking it `0`/locked, and
   tells the next drain it's a ready target once the tree is clean.

**Distinguish from a permanent lock:** `Owner: azrlb` alone is a TENANT tag on
FlowInCash beads, not an active human-developer claim — nearly every FlowInCash
bead carries it. The real lock signal is `@azrlb`/`@<dev>` in the TITLE (flat-list
assignee), `Assignee: <human>` in `bd show`, or gating language. A tenant-tagged
bead with clean deps is implementable; it's the LIVE dirty tree — not the tag —
that defers it. Verify a candidate's foundation is really on `main` before
deferring vs claiming:
```bash
# Confirm the dependency's code is actually on main (not just "bd show: CLOSED")
git log main --oneline 2>/dev/null | grep -i "<dep-bead-id>"
grep -rln "<KeyType>" src/ packages/ 2>/dev/null   # e.g. SourcedRecord.ts on main
```

**Real scenario (2026-07-15, daytime-2):** Crispi P2/P3 pool exhausted (5th
consecutive). Overflow to FlowInCash found `jzs` (P1 Standalone Deduper
`@flowincash/dedup`) — genuinely implementable: its dependency `ckg` was closed
AND its foundation (`src/types/SourcedRecord.ts` + 19 tests, commit `37a52326`)
was confirmed ON MAIN. But FlowInCash `main` had a dirty tree (`BusinessLanding.tsx`,
mobile files modified ~50 min prior) = active live session. Correctly DEFERRED
`jzs` to the next overnight clean-tree drain rather than committing into live
work. Note: bead said code path is `@flowincash/dedup module` but `packages/`
only had `mcp-tools` — the `ckg` foundation was actually implemented under `src/`
(trust the codebase over bead text — see FlowInCash stack pitfall in bead-execution).

**Re-evaluating a deferred bead on a LATER drain (the other half of the story):**
A bead deferred for a live session is a first-class target the next time the tree
is clean. When you pick up a previously-deferred overflow bead, run a SHARPER
active-session probe than raw mtime, then use a SURGICAL commit path that never
touches the human's WIP.

1. **Sharper active-vs-stale probe** — mtime of the known dirty files can be
   ambiguous (~2-3 h is borderline). Instead, ask "has ANYTHING been edited
   recently?":
   ```bash
   cd /path/to/overflow-project
   find . -path ./node_modules -prune -o -path ./.git -prune -o -type f -mmin -45 -print 2>/dev/null | grep -v node_modules
   ```
   If the ONLY hits are `.beads/` files (Dolt journal/manifest touched by your own
   `bd list`/`bd show`/`bd update` calls) and NO source/editor files appear, the
   live session has ended/paused — the dirty tree is now a stale leftover. Safe to
   proceed. If source files appear in the window, a human is still active — defer.

2. **Surgical no-stash commit path** — when the bead is a NEW module with ZERO
   file overlap with the human's dirty files, you can land it without ever
   stashing their work:
   ```bash
   git status -sb | head -1        # confirm "main...origin/main" with NO [ahead/behind]
   git add <only-your-new-files> .beads/issues.jsonl   # targeted — never `git add -A`
   git commit --no-verify -m "feat(scope): <bead-id> — <desc>"
   git push                        # push WITHOUT `git pull --rebase`
   ```
   The key insight: `git pull --rebase` is what fails on a dirty tree and forces the
   stash. But if local `main` is already level with `origin/main` (no ahead/behind
   in `git status -sb`), you don't need to pull at all — a plain `git push` of your
   new commit leaves the human's unstaged WIP 100% untouched. Verify the staged set
   contains ONLY your files before committing (`git diff --cached --name-only`).
   Write the attestation (`.hermes/sessions/<bead-id>.test-result`) AFTER the commit
   using the real commit sha.

**Real scenario (2026-07-15, daytime-3):** The `jzs` deduper deferred by daytime-2
was re-picked-up 3 h later. `find -mmin -45` showed only `.beads/` Dolt files (my
own `bd` calls) — no editor activity since 12:11 — so the session was confirmed
stale. `jzs` was a brand-new `src/dedup/` module (no overlap with Bob's dirty
`BusinessLanding.tsx`/mobile files). Implemented deduper + 43 vitest tests at 100%
coverage, `git status -sb` showed `main...origin/main` clean, so committed the 3 new
files + `.beads/issues.jsonl` and pushed WITHOUT pulling — Bob's WIP never touched.

**⚠ Sub-case: the deferred bead's code is ALREADY STAGED — verify, don't re-implement.**
A drain that deferred a bead may have already IMPLEMENTED and `git add`-ed the code
before deferring. On the next drain, `git status --short` shows the implementation
files as staged (`A src/<module>/...`) alongside the human's UNstaged WIP (` M ...`).
Do NOT re-implement — this is a verify-and-commit-staged-work case, effectively
"verify and close" mode against a dirty tree:
1. Confirm the staged set is exactly your files: `git diff --cached --name-only`
   (should show your new module files + `.beads/issues.jsonl`, nothing of the human's).
2. VERIFY the staged code before committing: run its tests (`npx vitest run <test>
   --coverage.enabled --coverage.include='src/<module>/**'`) and `npx tsc --noEmit
   2>&1 | grep -i "<module>"` — do NOT trust that prior-session staging means it passes.
3. Self-review the staged diff (read the impl file) for P0/P1. If it's pre-tested with
   100% coverage and clean self-review, self-review + traceability is sufficient — log
   Quinn/Murat as false with reason "verify-and-close of pre-tested staged code".
4. `git commit --no-verify` the staged files (they're already staged — no re-`git add`).
5. **`bd close` RE-STAGES `.beads/issues.jsonl`** (and touches `.beads/interactions.jsonl`)
   → a SECOND commit is needed for the close metadata. Stage both `.beads/*.jsonl`,
   commit `chore: close <bead-id>`, then push. Two commits total (code + close metadata).
6. Push path: `git status -sb` shows `[ahead N]` with NO `behind` → plain `git push`,
   no pull, human's WIP untouched. Verify after: `git status -sb` == `main...origin/main`
   clean AND the human's unstaged files still show ` M`.

**Real scenario (2026-07-15, overnight):** Crispi P2/P3 exhausted (6th). Overflow to
FlowInCash: `jzs` was ALREADY staged by daytime-3 (`A src/dedup/deduper.ts`,
`A src/dedup/index.ts`, `A src/__tests__/.../deduper.test.ts`, `M .beads/issues.jsonl`)
but never committed/closed. `find -mmin -45` = only `.beads/` Dolt files → session stale.
Verified: 43 tests pass, 100% coverage, no dedup type errors. Committed staged files
(`2b5b4a21`), wrote attestation with the real sha, `bd close` (which re-staged
`issues.jsonl`), committed close metadata (`c6404ee7`), pushed WITHOUT pull
(`[ahead 2]`, no behind). Bob's WIP (`BusinessLanding.tsx`, mobile, teaser assets)
confirmed intact after push.

**100%-coverage technique (when a bead demands it):** vitest v8 coverage flagged 4
uncovered branches that were genuinely-dead defensive guards or unique-id ties.
To reach true 100% without gaming it: (a) DELETE dead defensive branches whose
guard condition is already handled upstream (e.g. a `union === 0 ? 0 :` guard when
an earlier `return` already covered the both-empty case); (b) replace ternary
tiebreaks that have an unreachable arm with a single-expression equivalent
(`a.id.localeCompare(b.id)` instead of `a.id < b.id ? -1 : a.id > b.id ? 1 : 0`);
(c) ADD tests for the genuinely-reachable fallback arms (string-typed date fields,
`isNaN` invalid-date paths). Scope coverage to the new module with
`npx vitest run <test> --coverage.enabled --coverage.include='src/<module>/**'`.

### ⚠ Pitfall: Pure-triage overflow leaves a spurious `.beads/issues.jsonl` dirty change — revert it when no work was done

`bd list` / `bd show` / `bd ready` all touch the embedded Dolt DB and can MODIFY
`.beads/issues.jsonl` (and the `.beads/embeddeddolt/.../noms/` journal) as a
side-effect of merely READING — no bead was claimed or closed. When an overflow
(or primary) drain does PURE TRIAGE and finds the pool exhausted (writes nothing),
this read-triggered change leaves the project's working tree dirty for no reason,
which then confuses the NEXT drain's freshness probe and can mask whether a human's
WIP is really untouched.

**Rule:** If the drain does NO work in a project (triage-only → exhausted), revert
the read-triggered Dolt change before leaving so the tree is provably clean:
```bash
cd /path/to/overflow-project
git checkout .beads/issues.jsonl 2>/dev/null   # discard read-only Dolt journal touch
git status --short | grep -vE '^\?\?'          # confirm ONLY the human's real WIP remains
git status --short | grep -E '<human-wip-file>' # prove Bob's stale WIP is intact & untouched
```
Only revert `.beads/issues.jsonl` when you closed/claimed NOTHING. If you DID close
a bead, that file's change is real close metadata — commit it, don't revert it.

**Real scenario (2026-07-16, overnight):** Crispi P2/P3 exhausted (no P2s; all 5
P3s human/QA, large-feature, or @azrlb post-beta). Overflow to FlowInCash: 21 open /
9 blocked / 12 free, but all 12 free were video/creative/DNS/app-store/@Bob-Banks —
zero pure code (`ajp` teaser-finishing needs FFmpeg render + Bob visual sign-off).
`find -mmin -45` showed only `.beads/` Dolt files → no active session; the dirty
`sentry.ts` / `BankConnectionScreen.tsx` were stale leftovers. Because NO work was
done, reverted the read-triggered `.beads/issues.jsonl` change with `git checkout`
and confirmed Bob's two stale WIP files remained ` M` and untouched. Clean exit,
`exit_reason: pool-exhausted`.

### ⚠ Pitfall: Phantom exhaustion via unmerged feature branch (bead closures on branch, Dolt still OPEN)

A feature branch can accumulate bead "close" commits (`chore: close <bead-id>`)
that were never reflected in Dolt because the branch was never merged to main.
The drain sees beads as OPEN in Dolt and classifies them as blocked/human-gated,
when in reality the work is DONE but the closure is stuck on an unreachable branch.

**Mitigation & Response:**
* Do NOT attempt duplicate implementations of these beads to try to force progress.
* Audit git branches `git branch -a` for untracked or stale feature branches (e.g. `vibe/*`).
* Explicitly report a **merge backlog** to Bob with the exact branch name and size of completed code so he can coordinate merging and syncing.

Real scenario (2026-07-12): FlowInCash had 50 open beads. The drain
discovered `vibe/qbo-capability-probe` branch with 13,870 lines (94 files)
including close commits for the entire cash-flow engine epic (22z + 9 children).
`bd show beads_FlowInCash-22z` reported OPEN on main, but the branch had:
```
e52e4d40 chore: close beads_FlowInCash-22z — EPIC: all 9 children complete
27883fcd chore: close beads_FlowInCash-22z.9 — Engine-P13 complete
da8597cf chore: close beads_FlowInCash-22z.3 — Engine-P9 complete
7c11d09a feat(integration): beads_FlowInCash-22z.7 — Engine-P11
...
```
The drain correctly classified these as "feature-branch-only" and skipped them,
but the real issue is a **merge backlog**, not missing implementation work.

**Detection (add to triage when beads show as OPEN but seem suspiciously stale):**
```bash
# Check if any feature branch has close commits for this bead
git branch -a --list 'vibe/*' 2>/dev/null | while read branch; do
  if git log "$branch" --oneline 2>/dev/null | grep -q "close.*<bead-id>"; then
    echo "CLOSE COMMIT FOUND on $branch"
  fi
done
# Or broader: check all vibe/* branches for close commits
for branch in $(git branch -a --list 'vibe/*' 2>/dev/null); do
  count=$(git log "$branch" --oneline 2>/dev/null | grep -c "chore: close" 2>/dev/null)
  [ "$count" -gt 0 ] && echo "$branch: $count close commits"
done
```

**Classification:** This is NOT "code on feature branch" (existing pitfall).
This is "closure on feature branch" — the code AND the test attestation exist
but Dolt was never updated. The fix is a branch merge + Dolt sync, not
re-implementation.

**Recommended action for Bob:**
- Review and merge the feature branch
- After merge, run `bd close` for each bead that has a close commit on the branch
- Or manually sync Dolt to reflect the branch's closures

**Why this matters:** Without this check, the drain reports "pool exhausted"
when there's actually 13,870 lines of completed work waiting for merge. The
exhaustion is a bookkeeping problem, not a work-availability problem.

**Sub-variant: Implementation without closure on unmerged branch.**
The pattern above covers beads with *close commits* on the branch. A
different variant occurs when implementation code + test attestation exist
on a feature branch, but the drain session that did the work stalled
before the CLOSE step — no `chore: close <bead-id>` commit exists on the
branch either. The bead is still OPEN in Dolt, the implementation is done,
but neither the closure nor the merge happened.

**Real scenario (2026-07-13):** LivingApp-Sidecar `dnq` (P1 security bug:
RL routes lack service-to-service auth). Branch `vibe/rl-auth-service-to-service`
had 3,804 lines across 34 files including `src/rl/routes.ts` (auth middleware),
`tests/rl/rl-auth.test.ts` (321 lines), and `.hermes/sessions/LivingApp-Sidecar-dnq.test-result`
attestation — but NO `chore: close` commit. The bead was never closed in Dolt.
The implementation was complete; the session just didn't finish the lifecycle.

**Detection (broader than close-commit scan):**
```bash
# Check if ANY feature branch has commits mentioning this bead ID (not just close)
git branch -a --list 'vibe/*' 2>/dev/null | while read branch; do
  if git log "$branch" --oneline 2>/dev/null | grep -qi "<bead-id>"; then
    echo "BEAD COMMITS FOUND on $branch"
    git log "$branch" --oneline 2>/dev/null | grep -i "<bead-id>"
  fi
done
# Also check for implementation files without close commits
for branch in $(git branch -a --list 'vibe/*' 2>/dev/null); do
  impl=$(git log "$branch" --oneline 2>/dev/null | grep -c "feat\|fix\|implement" 2>/dev/null)
  close=$(git log "$branch" --oneline 2>/dev/null | grep -c "chore: close" 2>/dev/null)
  [ "$impl" -gt 0 ] && [ "$close" -eq 0 ] && echo "$branch: $impl impl commits, 0 close commits"
done
```

**Classification:** This is a third variant alongside "code on feature branch"
and "closure on feature branch." The implementation is done and tested, but
the bead lifecycle was never completed. The fix is: merge the branch, then
run the CLOSE workflow (attestation + bd close + commit metadata + push).

**Recommended action for Bob:**
- Review and merge the feature branch (implementation is complete)
- After merge, the drain can pick up the bead in "verify and close" mode
- Or Bob can manually run `bd close <bead-id>` after confirming tests pass

### ⚠ Pitfall: Phantom-satisfied dependency — dep bead CLOSED but its close commit is metadata-only (no impl anywhere)

A distinct third failure mode alongside "closure on feature branch" and
"implementation without closure on branch." Here a *dependency* bead shows
CLOSED in Dolt and `bd show <downstream>` reports its `DEPENDS ON → ✓ <dep>`
as satisfied — but the dep's close commit touched **ONLY `.beads/issues.jsonl`**,
with NO implementation commit on main OR any feature branch. The code was never
built; only the bookkeeping was flipped to closed. This **silently blocks the
downstream bead**: the drain thinks the foundation is present (green checkmark)
and may waste a cycle trying to build on nonexistent code — or, if caught, must
skip the downstream bead as foundation-missing.

**Do NOT trust `bd show`'s `DEPENDS ON → ✓` alone.** A green checkmark means
"marked closed in Dolt," not "code exists on main." Before implementing any bead
whose value rests on a closed dependency, VERIFY the dependency's code is
physically present on the current branch.

**Detection — verify the dep's close commit actually shipped code:**
```bash
# 1. What did the dependency's close commit contain? If ONLY .beads/*.jsonl → phantom.
git show <dep-close-sha> --stat 2>/dev/null | head -15
#    Look for: "1 file changed ... .beads/issues.jsonl" with NO src/ files = phantom.

# 2. Cross-check: is the dep's actual code anywhere in src/ on main?
git log main --oneline 2>/dev/null | grep -iE "<dep-bead-id>|<feature-keyword>" | head
grep -rln "<KeyTypeOrFunction>" src/ packages/ 2>/dev/null | grep -v node_modules | head
#    Empty grep + only-metadata close commit = foundation MISSING despite "CLOSED".

# 3. Compare with a REAL dependency for contrast: a genuine close has BOTH an
#    impl commit (feat(...): <id> — ... N tests) AND a chore: close <id> commit.
git log main --oneline 2>/dev/null | grep -i "<real-dep-id>"
```

**Classification & response:**
- If the dep's close commit is metadata-only AND its code is absent everywhere →
  the downstream bead is **foundation-missing**, NOT implementable. Skip it.
- Flag in the drain report as a distinct issue: `"PHANTOM DEPENDENCY: <dep-id>
  shows CLOSED but close commit <sha> only touched .beads/issues.jsonl — NO impl
  on main. Blocks <downstream-id>."` with a recommendation to verify whether the
  dep code exists on an unmerged branch, or re-open + re-implement the dep.
- Do NOT attempt to build the downstream feature on the missing foundation — that
  produces broken/half work that can't pass tests or close.

**Real scenario (2026-07-16, overnight):** FlowInCash overflow. `wl5` (P1 Feed
Health Checkers) `bd show` reported `DEPENDS ON → ✓ beads_FlowInCash-7np`
(Business-Day Engine). But `git show 75b3f2ff --stat` (7np's close commit) showed
"1 file changed, 25 insertions, 25 deletions .beads/issues.jsonl" — metadata only.
`grep -rln "addBusinessDays|isHoliday|BusinessDay" src/` returned nothing on main.
The business-day engine was never built; 7np was just flipped to closed. Correctly
classified `wl5` as foundation-missing and skipped it. CONTRAST: `6pu`'s dependency
`ckg` was a REAL close — commit `37a52326 feat(ingestion): beads_FlowInCash-ckg —
sourced_records schema, TS types & 19 unit tests` plus `279587ff chore: close ckg`,
and `src/types/SourcedRecord.ts` was physically on main. So `6pu`'s foundation was
genuinely present (though `6pu` itself was a full-stack [feature] needing decomposition).

### ⚠ Pitfall: `bd update --claim` fails when already claimed by same team

When a bead is already assigned to `hermes-dev-team` (from a previous session
that claimed but didn't complete), `bd update <id> --claim` returns:
```
Error claiming <id>: issue already claimed by hermes-dev-team
```

**This is NOT a blocker.** The bead is already "ours" — proceed with
implementation. The claim failure is cosmetic (the bead is already assigned
to the right team). Do NOT skip the bead or treat this as a dependency issue.

**If claimed by someone ELSE** (e.g., `@azrlb`), that IS a blocker — do not
override another developer's claim.

### ⚠ Pitfall: Cross-project contamination blocking git pull

When `git pull --rebase` fails due to unstaged changes, inspect what's modified.
Cross-project contamination occurs when a previous drain session accidentally
modified files belonging to a different project (e.g., Crispi marketing copy
replaced with FlowInCash content). This is detected by:

```bash
git diff --stat  # shows which files are modified
git diff <file>  # inspect the actual change
```

**Response:** Stash the contaminated changes, complete the push, then restore
the stash and flag the contamination in the drain report as an issue for Bob.
Do NOT commit cross-project contamination. Do NOT discard it without flagging.

## Example: Processing a Bead

Bead: "Fix TypeScript error in payment.ts line 42"
Classification: Code
Specialist: code (DeepSeek V3.2)

```python
# Orchestrator (architect profile) initiates a loop:
max_attempts = 5
for attempt in range(max_attempts):
    # Delegate to code specialist with rich context and past feedback
    delegate_task(
        profile="code",
        goal="Fix the TypeScript error in payment.ts on line 42. The error is 'Type 'string' is not assignable to type 'number'.",
        context="File: /media/bob/C/AI_Projects/FlowInCash/src/routes/payment.ts. The variable 'amount' is typed as string but should be number. Add parseFloat() conversion. "
                "THINK BEFORE ACTING: What is the ROOT CAUSE? What is the MATH? What is the CONTEXT? Have I VERIFIED? "
                "CODE QUALITY OVER SPEED: Ensure changes are robust and maintainable. "
                "Feedback from previous attempt (if any): [Synthesized feedback from Quinn/Murat reviews or failed tests]. "
                "DEFINITION OF GOOD: After your changes, run `npx tsc --noEmit` and `npx vitest run packages/FlowInCash/src/routes/__tests__/payment.test.ts`. Both must pass with zero errors.",
        toolsets=["terminal", "file"]
    )
    # --- Orchestrator verification logic (this part exists within the actual cron job logic, not directly in SKILL.md) ---
    # Orchestrator verifies independent of specialist's claim:
    # 1. Run npx tsc --noEmit; check for new errors.
    # 2. Run npx vitest run <test_path>; check for failures.
    # 3. If tests pass and no new errors, trigger shared-execution quality gates (Quinn/Murat).
    # 4. If quality gates pass, break loop. Else, if max_attempts reached, initiate escalation.
    # ------------------------------------------------------------------------------------------------------------------
```
