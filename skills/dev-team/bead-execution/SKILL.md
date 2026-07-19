---
name: bead-execution
description: >
  Systematic workflow for executing beads (stories/tasks) end-to-end:
  claim → implement (iterative loop) → test → quality review → commit → close.
  Handles batch execution with robust iteration, quality enforcement, and
  escalation for quality-first drain operations.
triggers:
  - "build bead"
  - "implement story"
  - "execute task"
  - "keep going through all"
  - "execute bead by bead"
  - bead is claimed and ready to build
dependencies:
  - beads-decomposition (for breaking epics into beads)
  - orchestrated-drain (for overall orchestration and multi-tiered escalation)
  - shared-execution (for core lifecycle steps, esp. quality gates)
version: 1.15.0 # Updated the assignment bypass and un-assignment routines for automated drains; un-blocked @azrlb locked beads.
author: hermes-agent
tags: [beads, execution, workflow, testing, git, quality, loop, iteration, escalation]
---

# Bead Execution Workflow (Enhanced for Autonomous Quality)

This skill picks up existing beads and executes them, forming the core "Building", "Testing", and "Review" phases of the Vibe Loop within the drain context. It now includes a robust, iterative "loop-and-fix" mechanism enforced by quality gates, and explicitly calls upon specialized profiles from the orchestrator's hierarchy.

**CODE QUALITY OVER SPEED:** This workflow firmly prioritizes code quality over completion speed. Never skip quality gates to close more beads. One well-reviewed bead is worth more than five unreviewed beads. If token budget is tight, close fewer beads but run full quality review. **This is fully enforced.**

## Pre-Flight Check (MANDATORY — before any bead work)

Before starting any execution cycle, validate that work exists:

```bash
# Quick check: beads with ALL dependencies satisfied (ready to claim NOW)
bd ready -l <target-label>
# Broader check: ALL open beads (may include blocked/dependency-waiting ones)
bd list --label <target-label> --state open
# If empty, also check deferred beads (❄️ are excluded from --state open):
bd list --all --flat | grep -i "<target-label>"
```

**`bd ready` vs `bd list` — know the difference:**
- `bd ready` returns only beads whose dependencies are ALL satisfied — safe to claim immediately.
- `bd list --state open` returns ALL open beads, including those blocked on other beads or human deps.
- A drain that runs `bd ready` and finds nothing does NOT mean the pool is empty — it means no beads are unblocked yet. Always follow up with `bd list` to see the full picture.
- `bd list --flat` status icons: `○` = open/unassigned, `●` = open/assigned, `◐` = in-progress.

**Multi-Project Discovery (for label-targeted cron jobs):**
When the cron job targets a specific label (e.g., `appsumo-fast-track`) rather
than a specific project, beads may live across multiple project directories.
Search ALL projects before concluding the pool is empty:

```bash
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

See `orchestrated-drain/references/project-locations.md` for the full directory map.

**If no beads are found:** Report "No beads matching filter found" and STOP. Do not attempt to create beads, initialize databases, or guess at what should be built. The orchestrator or user must populate the beads board first. This prevents wasted cron cycles on empty databases.

**If beads exist but ALL are closed (✓):** Report the specific closed beads with their close reasons and STOP. Unlike "no beads found", this is a valid outcome — the work was done. Include actionable next steps if any human action is pending (e.g., "AppSumo listing copy ready at `~/.hermes/appsumo-listing.md` — needs Bob to submit").

**Common causes of empty results:**
- Beads database not initialized (`bd init` needed in project directory)
- Beads created in a different workspace (check `bd where`)
- Label filter doesn't match any created beads
- All matching beads already closed
- Beads live in a different project directory (use multi-project discovery)

## The Cycle (per bead) — Autonomous Iterative Loop

This skill drives the iterative execution for a single bead, ensuring quality before completion.

### 1. Triage (as managed by `orchestrated-drain`)
The bead's initial implementability and context are handled by the `orchestrated-drain` skill's comprehensive triage (Step 1). This skill starts with an already triaged, implementable bead.

**⚠ Detect "complete existing code" mode during triage:**
Before entering the standard claim→implement cycle, check if implementation
code already exists but lacks tests. A previous session may have left untracked
files that need test coverage and closure:

```bash
# Check for untracked implementation files in the bead's scope
git ls-files --others --exclude-standard | grep -E "\.(ts|tsx)$" | grep -v __tests__
# Also check for tracked but uncommitted files
git diff --name-only | grep -E "\.(ts|tsx)$" | grep -v __tests__
```

If untracked/tracked implementation files exist (services, components) but no
corresponding test files exist, the bead is in **"complete existing code" mode**:
- **SKIP** the IMPLEMENT phase (Step 3) — code is already written
- **GO DIRECTLY** to TEST (Step 4) — write tests for the existing implementation
- Then proceed through quality gates, commit, and close as normal

This mode applies when:
- `bd show <bead-id>` shows status `IN_PROGRESS`
- `git ls-files --others` reveals `.ts`/`.tsx` files in `src/services/` or `client/src/`
- No matching `*.test.ts` files exist yet

**⚠ Guard against wrong-branch contamination at session startup:**
If a previous interactive session left a modified working tree or checked out a feature branch (e.g. `vibe/...`), automated or background cron runs must avoid committing to those paths:
```bash
# Check current branch and dirty modifications
git branch --show-current
git status --short
# When running unattended, if dirty or on an unrelated feature branch:
git stash
git checkout main && git pull --rebase
# Keep developer workspace safe while keeping cron sessions isolated!
```

**⚠ Detect "verify and close" mode during triage:**
A prior session may have fully implemented AND tested a bead but failed to close
it in the Dolt database (the JSONL may show "closed" while `bd show` still shows
"IN_PROGRESS" — Dolt is the source of truth). Check:

```bash
# Find the test file(s) for this bead's implementation
find . -path '*/node_modules' -prune -o -name '*<ServiceName>*' -print 2>/dev/null | grep -v node_modules
# Run the tests
npx vitest run <test-file-path>
```

If both implementation AND test files exist and ALL tests pass, the bead is in
**"verify and close" mode**:
- **SKIP** IMPLEMENT (Step 3) and TEST (Step 4) — code and tests are done
- **GO DIRECTLY** to QUALITY (Step 4b) — self-review the existing code
- Then COMMIT (Step 5) bead metadata if needed, CLOSE (Step 6), and LOG (Step 7)

This mode applies when:
- `bd show <bead-id>` shows status `IN_PROGRESS`
- Implementation file(s) exist in `src/services/`
- Corresponding test file(s) exist in `src/__tests__/`
- `npx vitest run <test-file>` passes with 0 failures

### 2. CLAIM
```bash
bd update <bead-id> --claim
# Ensure the bead is claimed by Hermes (Bob's delegated agent)
```

### 3. IMPLEMENT (Iterative Loop with `code` Profile)
**Goal:** Produce code that makes associated tests pass and is free of P0/P1 quality issues.
**Process:** The orchestrator (or this skill if fully handling the loop) will drive an iterative loop (e.g., up to 5 attempts, configurable).

**⚠ SKIP this phase if in "complete existing code" mode** — go directly to Step 4 (TEST).

```python
MAX_CODE_IMPLEMENT_ATTEMPTS = 5
for attempt in range(MAX_CODE_IMPLEMENT_ATTEMPTS):
    # Delegate to the 'code' specialist (DeepSeek V3.2)
    delegate_task(
        profile="code",
        goal="Implement the necessary code changes for bead {{bead_id}}. "
             "Your objective is to make all associated tests pass and introduce no new TypeScript errors. "
             "Refer to the context for detailed requirements, project patterns, and current test status.",
        context="""
You are DEV, an expert TDD developer. Your task is to IMPLEMENT the solution described in the bead {{bead_id}}.

BEAD ID: {{bead_id}}
BEAD TITLE: {{bead_title}}
BEAD DESCRIPTION / AC:
{{bead_description_and_ac}}

PROJECT CONTEXT (AGENTS.md):
{{project_agents_md_content}}

PROJECT CODEBASE PATTERNS & PITFALLS (from references/ for this project):
{{project_patterns_md_content}}

TEST FILE(S) TO MAKE PASS: {{test_file_path}}
TEST COMMAND: `npx vitest run packages/<pkg>/src/__tests__/{{test_file_name}}`
BUILD COMMAND: `npx tsc --noEmit`

DEFINITION OF GOOD:
1. All tests in `{{test_file_path}}` must pass with 0 failures.
2. `npx tsc --noEmit` must report 0 new errors (current errors: {{initial_tsc_error_count}}).
3. Code must adhere to project patterns in AGENTS.md and relevant references.

FEEDBACK FROM PREVIOUS ATTEMPTS (if any):
{{synthesized_feedback_from_orchestrator_or_quality_gates}}

THINK BEFORE ACTING (MANDATORY):
1. What is the ROOT CAUSE? (of the problem or the failed attempts)
2. What is the MATH?
3. What is the CONTEXT?
4. Have I VERIFIED? (new code, tests, build)

CODE QUALITY OVER SPEED (MANDATORY):
Never compromise code quality. Focus on robust, maintainable, secure solutions.
"""
        toolsets=["terminal", "file", "git"]
    )
    # --- Orchestrator/bead-execution's role after delegation ---
    # The orchestrator (orchestrated-drain) or bead-execution itself (if handling sub-delegation)
    # will verify the results of the 'code' agent's work.
    # This involves:
    # 1. Independent execution of tests and build check.
    # 2. Triggering quality gates (Quinn & Murat via 'analysis' profile).
    # 3. Synthesizing feedback if checks fail.
    # 4. If all quality gates pass, break the loop. Else, continue for next attempt.
    # 5. If MAX_CODE_IMPLEMENT_ATTEMPTS reached, trigger escalation chain (orchestrated-drain will handle).
```
**Actual implementation of `IMPLEMENT`** involves the `code` profile writing code based on the detailed `context` provided.

### 4. TEST & QUALITY (Continuous Verification)
**Goal:** Ensure the implemented code meets all objective and subjective quality criteria.
**Process:** This is governed by the `shared-execution` skill and is invoked *after* each iteration of `IMPLEMENT` within the loop, until all gates pass.

   **4a. Objective Verification (Automated Tests & Build):**
   ```bash
   # Run ALL tests in the relevant package
   cd /path/to/project && npx vitest run packages/<pkg>/src/__tests__/{{test_file_name}}
   # Check exit code, output for failures. Also run:
   npx tsc --noEmit # Check for TypeScript errors
   ```
   **4b. Subjective Verification (Quality Gates - via `shared-execution`):**
   *   **Self-review:** Instruct the agent to perform a `git diff` review.
   *   **Quinn Review:** `delegate_task(profile="analysis", ...)` to criticaly review code diff. **(Already patched in `shared-execution` to use `analysis` profile)**
   *   **Murat Test Quality:** `delegate_task(profile="analysis", ...)` to audit test quality. **(Already patched in `shared-execution` to use `analysis` profile)**
   *   **Traceability:** Verify test coverage, story specs, and code export.

   **Loop Feedback:** If any of these checks (tests, build, Quinn, Murat) fail, synthesized feedback is provided to the `IMPLEMENT` step for re-iteration.

### 5. COMMIT (Managed by `orchestrated-drain`)
Once all quality gates have passed for a bead, `orchestrated-drain` will handle the commit process as defined in `shared-execution`.

### 6. CLOSE (Managed by `orchestrated-drain`)
Post-commit, `orchestrated-drain` will handle the bead closure process as defined in `shared-execution`.

### 7. LOG (Managed by `orchestrated-drain`)
Finally, `orchestrated-drain` will ensure structured logging.

---
## Autonomous Batch Mode

When user says "go ahead" or "keep going through all":
- Do NOT stop between beads to summarize
- Build the full batch end-to-end (each bead goes through its full iterative loop)
- Summarize ONCE at the very end including comprehensive report on each bead (status, attempts, issues, escalation path if any).
- Each bead gets its own commit adhering to format.
- Update todo list after each bead.

## Pitfalls

1. **`vibe-loop` skill does not exist** — Some cron jobs and orchestrator configs reference `vibe-loop` as a dependency alongside `bead-execution`. This skill is not in the library. If a cron job fails with "skill not found: vibe-loop", the job config needs updating to remove that reference. Do not attempt to create `vibe-loop` unless Bob explicitly requests it.

2. **Deferred beads (❄️) invisible to `--state open`** — When `bd list --state open --label <label>` returns empty, it does NOT mean no beads exist with that label. Deferred beads (❄️) are excluded from `--state open`. Always fall back to `bd list --all --flat | grep -i "<label>"` to see the full picture including deferred beads. Common status icons: `○` = open/unassigned, `●` = open/assigned, `◐` = in-progress, `❄️` = deferred, `✓` = closed.

3. **Empty beads database wastes cycles** — Without the pre-flight check, cron jobs run the full triage/claim loop only to find nothing to do. Always validate `bd list` returns results before proceeding.

4. **Truncated cron job instructions** — Some cron jobs are set up with partial instructions (cut off mid-sentence). If the prompt context is incomplete, report the truncation and stop rather than guessing at the intent.

5. **Tirith blocks pipes to interpreters** — The security scanner flags `bd list --json | python3 -c "..."` AND `grep "pattern" file | python3 -c "..."` as "Pipe to interpreter." Use `grep`, `awk`, `jq`, or `sed` for filtering instead. For JSON output, pipe to `jq` if available, or use `bd list --flat` with `grep`.

6. **Multi-project bead discovery** — When targeting a label (e.g., `appsumo-fast-track`), beads may live in any project under `/media/bob/C/AI_Projects/*/`. A single-project `bd list` may return empty even when beads exist elsewhere. Use the multi-project discovery pattern from the Pre-Flight Check section.

7. **"Complete existing code" mode missed** — When triage finds IN_PROGRESS beads with untracked implementation files but no tests, the standard claim→implement cycle wastes time trying to re-implement already-written code. Use `git ls-files --others --exclude-standard | grep -E "\.(ts|tsx)$" | grep -v __tests__` during triage to detect this. If code exists, skip IMPLEMENT and go straight to TEST.

   **⚠ Sub-pitfall: code on a feature branch, not the current branch.** The detection above only finds untracked/uncommitted files. If implementation code is committed but on a different branch (e.g., `vibe/qbo-capability-probe`), it won't appear in `git ls-files --others` or `git diff --name-only`. Verify the file is actually on the current branch before entering "complete existing code" mode:
   ```bash
   git ls-files --error-unmatch <file-path> 2>/dev/null
   # Exit code 0 = file is on current branch; non-0 = it's not accessible here
   ```
   If code is on a feature branch only, flag as `feature-branch-only` — do NOT try to test or close the bead.

8. **Unstaged changes block `git pull --rebase`** — After committing bead metadata, `git pull --rebase` fails if there are any unstaged changes (cross-project contamination, untracked `.hermes/` files from prior sessions, `_output/` reports). Always check `git status --short` before pulling. If unstaged changes exist, stash → pull → push → pop. See `shared-execution` CLOSE section for the full pattern.

9. **Cross-project contamination** — Previous drain sessions may modify files belonging to a different project (e.g., Crispi marketing copy replaced with FlowInCash content). Detected by `git diff --stat` showing unexpected file changes. Stash contaminated changes before push, flag in drain report as an issue for Bob. Do NOT commit cross-project content.

10. **Pool has beads but all are unimplementable (or assignment-locked)** — The pre-flight check finds open beads, but every one is blocked on human dependency (Bob-owned, designer, legal), cross-repo work (different codebase), or missing external packages. 

   **⚠ Crucial Sub-Case: Assignment Locks.** Some open beads are assigned to a human developer (like `@azrlb`) because they were started during a live session. The automated night drains will *refuse* to touch any bead assigned to a human developer to avoid merge conflict catastrophes. 
   * **The Lesson:** If you want nocturnal drains to resolve these beads, they must be unassigned (`bd assign <bead-id> ""` or reassigned to `drain`) so the daemon is clear to claim them.
   
   Unlike "no beads found" (empty pool), this requires a different response: report the specific blockers per bead in the drain log so Bob can prioritize which to unblock. Do NOT attempt to implement beads that require changes in other repos (e.g., FlowInCash-Core, hermes-sidecar) — those need their own drain cycles. Check each bead's description for words like "migrate to Core", "hermes-sidecar", "Bob-owned", "requires designer", "blocked on" to classify implementability.

11. **Dolt DB is source of truth, not `.beads/issues.jsonl`** — The JSONL file can show "closed" while `bd show` still reports "IN_PROGRESS" (or vice versa) if the Dolt database wasn't properly updated. Always trust `bd show` / `bd list` output over grep on the JSONL. When closing beads, use `bd close` (which updates Dolt) rather than manually editing the JSONL.

12. **Unicode characters in `bd list --flat` break grep** — The output contains multi-byte Unicode status icons (`○` = U+25CB, `●` = U+25CF, `◐` = U+25D0) that corrupt standard grep patterns. Even simple `grep "P3"` can fail because the Unicode bytes before the bracket content interfere with byte-level matching. Use `cat -v` to reveal the actual bytes, or use bd's built-in `--label` filter which is reliable. If you must grep, pipe through `cat -v` first:
    ```bash
    bd list --state open --flat 2>/dev/null | cat -v | grep -i "P3"
    # Or better: use bd's label filter
    bd list --state open --flat --label P3 2>/dev/null
    ```

13. **Bead descriptions may have incorrect technical details** — Bead titles and descriptions can reference the wrong database engine, framework, or tooling. Example: beads in FlowInCash said "SQLite database schemas" but the project uses PostgreSQL with raw `pg.Pool`. During triage, verify the ACTUAL project stack before implementing:
    ```bash
    # Check actual DB engine
    grep -r "require.*pg\|import.*Pool\|sqlite\|knex" src/ --include="*.ts" | head -5
    # Check actual test runner
    cat package.json | grep -E "vitest|jest"
    ```
    Trust the codebase, not the bead text. If the bead says "SQLite" but the project uses PostgreSQL, implement for PostgreSQL.

### 14. **"Complete existing code" must verify the component is imported/integrated** — Code can exist on the current branch, have a service test, and still be dead code (never imported into any page or component). A bead like `beads_FlowInCash-jvc` had `TieredObligationLights.tsx` (287 lines, committed) + `TieredObligationService.ts` (551 lines, with tests), but the component was never imported anywhere — zero integration. The bead requires both the component AND its integration into the dashboard. Detection:
    ```bash
    # After finding implementation files, check if they're actually imported
    grep -rn "import.*<ComponentName>" client/src/ src/ --include="*.tsx" --include="*.ts" | grep -v "<ComponentName>.tsx"
    # Empty result = dead code, not "complete existing code"
    # If dead code: flag as "needs-integration" (larger scope than just tests)
    ```

15. **React Native/Web Integration Startup Pitfalls** — React Native standalone production builds often crash instantly with silent native errors. Always double-check standard entry points (e.g. `index.js` registering matching values like `'main'` instead of `package.json` names), Sentry or SDK constant evaluation guards for offline scenarios, and PostgreSQL database table schema states (especially `audit_trail` and tenant context variables) before shipping changes. See linked file `references/teller-flowincash-troubleshooting.md` for full blueprints on resolving these bottlenecks.

## Key Principles (Reinforced)

1.  **Iterate for Perfection:** The system will loop and fix until quality gates are met.
2.  **Autonomous Escalation:** Complex blockers are resolved internally, leveraging specialized models, rather than interrupting Bob.
3.  **Quality First:** "CODE QUALITY OVER SPEED" is paramount and enforced.
4.  **Enforced Gates:** Quality checks are not aspirational; they are executed and verified. Failure to meet them results in re-iteration or escalation.
5.  **Context-Rich Feedback:** Iterative feedback to specialists is detailed and actionable.
6.  **Trust but Verify:** Specialist reports are always independently (and often automatically) validated.

## Step Details (from `shared-execution` for core steps)

For granular details on `CLAIM`, `IMPLEMENT` (developer flow), `TEST` (test writing/running), `QUALITY` (self-review, Quinn, Murat, traceability), `COMMIT`, `CLOSE`, and `LOG` — refer to the `shared-execution` skill. This `bead-execution` skill focuses on the orchestration and iterative process around those core steps.
