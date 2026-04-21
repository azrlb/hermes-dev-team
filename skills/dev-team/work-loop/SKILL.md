# Work Loop (DEPRECATED — use vibe-loop)

> **⚠ RETIRED:** This skill is now Phase 10 inside `dev-team/vibe-loop`. Do NOT invoke work-loop directly — it skips Pattern Capture (10b), Quinn Adversarial Review (10c), E2E validation (11), Deploy (12), and Completion (13). Use vibe-loop for ALL dev work. If stories + tests already exist, tell vibe-loop to skip to Phase 10: `hermes chat -s dev-team/vibe-loop --yolo -q "Stories and tests exist. Skip to Phase 10 (implementation) and continue through completion."`

Orchestrates the full story lifecycle: pick work from Beads → health check → invoke Pi subagents → evaluate → land the plane or escalate.

**CRITICAL: This is a LOOP. You MUST keep running until `bd ready` returns zero issues. After completing or escalating each story, ALWAYS run `bd ready --json` again and pick the next one. NEVER stop after a single story. The session ends ONLY when there are no more ready stories to execute.**

## Trigger

- **Cron:** Periodic `bd ready` check (configurable interval, e.g. every 15 min)
- **Telegram:** Bob sends a Beads ID (e.g. `LivingApp-S2.1`) → execute that specific issue
- **Telegram:** Bob sends `run ready` → execute all ready issues
- **On-demand:** After completing a story, check for next

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `HERMES_MAX_PARALLEL` | `1` | Max concurrent Pi subagent sessions |
| `STORY_BUDGET_USD` | `unlimited` | Per-story budget cap. No limit — stories take what they take. |
| `WORK_LOOP_BUDGET_USD` | `unlimited` | Per-work-loop cumulative budget cap. No limit — run until all stories are done. |
| `APPROVALS_MODE` | `off` | Graduated autonomy phase: `manual`, `smart`, or `off`. Default is `off` — true yolo. When `--yolo` flag is used, ALWAYS treat as `off` regardless of any other setting. |

## Critical Rules

- **NEVER modify test files.** Tests define the contract. Only Pi's `tdd-coder` subagent writes implementation code, and it is also instructed to never touch tests. If tests fail due to environment issues (missing DB, broken native modules, import errors from missing implementations), escalate via the failure-classifier — do NOT edit the test file to work around the problem.
- **NEVER modify implementation code directly.** All code changes go through Pi subagents. Hermes orchestrates, Pi codes. If Hermes needs to fix something, it dispatches to Pi with the fix context — it does not edit source files itself.
- **NEVER install or modify dependencies** (package.json, node_modules) without explicit user approval.

## Steps

### 1. Pre-Flight Health Check

**Purpose:** Ensure the codebase can commit cleanly BEFORE starting story work. Pre-existing lint/TS errors will block every commit.

**Run once per work-loop session** (not before every story):

**1a. Stack Detection (MANDATORY — runs before everything else):**

Invoke `dev-team/stack-detect` with `{project_root}`. This:
- Auto-detects test runner, build tool, linter, DB tool from package.json and config files
- Writes/updates the `<!-- BEGIN STACK DETECT -->` block in AGENTS.md
- Returns `{test_cmd}`, `{test_single_cmd}`, `{build_cmd}`, `{lint_cmd}`, `{tsc_cmd}`

**Store these values for use in Steps 7 and 9.** Do NOT hardcode test runner commands.

If stack-detect returns `NO_STACK` (greenfield, no package.json yet): skip stack detection and fall back to `CI=true npm test` for test commands. Stack-detect will populate AGENTS.md on the next run after the project is scaffolded.

**1b. Lint and TypeScript checks:**

```bash
# Run the same checks the pre-commit hook runs
npx eslint src/**/*.ts src/**/*.tsx --quiet 2>&1
npx tsc -p tsconfig.server.json --noEmit 2>&1
```

**If all checks pass:** Log "Health check PASS" and proceed to Step 2.

**If errors found:** Apply the "is this related to the work we are about to do?" filter BEFORE reaching for health-fix.

1. Run `bd ready --json` first.
2. If at least one ready issue names files or packages that appear in the error output, health-fix is relevant → invoke it with the constraints below.
3. If NO ready issue relates to the errors, these are **pre-existing project warnings, not our problem this session**. Log `Pre-existing warnings unrelated to queued work — committing with --no-verify` and skip directly to Step 2. Do NOT invoke health-fix.

**Health-fix invocation** (only when errors are related to queued work):

Invoke `dev-team/health-fix` with a hard **single-pass budget**: one invocation, no retries from work-loop's side, 5-minute wall-clock maximum. If health-fix has not returned `PASS` within that window, treat the outcome as `PARTIAL`.

- `error_source`: "eslint+tsc"
- `error_list`: the error output
- `scope`: "blocking-only"
- `project_root`: current directory

Routing:
- `PASS` → proceed to Step 2, commits verified normally
- `PARTIAL` or 5-min timeout → proceed to Step 2 with `--no-verify` on all commits this session; remaining errors filed as P0 blockers for next session
- `FAIL` → log "Health check unresolvable. All errors filed as blockers." and exit

**RATIONALE:** Pre-existing warnings in any real project are not this session's problem. Health-check exists to catch environmental breakage that would prevent ANY commit landing — not to achieve a clean lint report on a project with accumulated cruft. A small-model Brain that gets trapped in health-fix burns the whole work-loop budget without finishing a single story. The filter above is the bright line between "the repo is broken" and "the repo has warnings."

---

### 2. Check Queue

If triggered by Telegram with specific ID(s): use those IDs.
Otherwise: run `bd ready --json` and pick up to `HERMES_MAX_PARALLEL` issues.

If no issues are ready, log "No ready issues" and exit.

**IMPORTANT — Claim Identity:** Hermes runs under Bob's git identity. When `bd update --claim` assigns an issue, the assignee will show as "Bob Banks" or "bob". This is CORRECT — Hermes IS operating as Bob. Do NOT skip issues because they are assigned to "Bob", "Bob Banks", or "bob". Those are YOUR claims. You ARE Bob's autonomous agent. Only skip issues explicitly assigned to a different named person (e.g., a specific team member's name that isn't Bob).

### 3. Claim

For each issue picked:
```
bd update {id} --claim
```

### 4. Pre-Flight Story Validation

For each claimed issue, validate from Beads issue metadata before handing to Pi:

| Check | Source | On Fail |
|-------|--------|---------|
| `story_file` exists on disk | issue metadata or description | `bd update {id} --status=open --append-notes "Pre-flight fail: story_file missing"`, skip |
| `test_file` exists on disk | issue metadata or description | `bd update {id} --status=open --append-notes "Pre-flight fail: test_file missing"`, skip |
| Story frontmatter parseable | story file | `bd update {id} --status=open --append-notes "Pre-flight fail: bad frontmatter"`, skip |
| All `context_files` exist | story frontmatter | `bd update {id} --status=open --append-notes "Pre-flight fail: context_file missing"`, skip |

If validation fails, release the claim and skip to next issue.

### 5. Build Context

Read the Beads issue (`bd show {id} --json`) to assemble Pi's task context:
- `story_file` content (the spec)
- `test_file` path (what tests to pass)
- `checkpoints` from metadata (prior progress, if retrying)
- `failed_approaches` from metadata (what NOT to do)
- `budget_usd` from metadata or `STORY_BUDGET_USD` env var
- Set `STORY_ID={id}` env var for Pi extensions

Determine model tier using the 5-tier routing system:
- Read story complexity from issue metadata `model_tier` field if present
- Otherwise use `model-tier-classifier` skill or default to Tier 3 (qwen3:8b local)

### 6. Check Parallel Safety

If running multiple stories in parallel, check for file overlap between context_files:
- Extract `context_files` from each story's frontmatter
- If any files overlap between parallel candidates → run overlapping stories sequentially
- Non-overlapping stories can run in parallel

### 7. Invoke Pi via CLI

Pi runs as a **child process** (not MCP). Each story gets its own Pi invocation — fully isolated. If Pi crashes, Hermes is unaffected and can retry.

**Default (local Ollama via `ollama/qwen3:8b`):**
```bash
cd {project_root} && pi --print \
  --provider ollama --model qwen3:8b \
  --session .hermes/sessions/{story_id}.jsonl \
  --append-system-prompt ~/.pi/agents/tdd-coder.md \
  "$(cat <<'PROMPT'
Read AGENTS.md for project conventions.

## Story
{story_content}

## Tests to Pass
Run: {test_single_cmd} {test_file}
Make ALL tests pass.
IMPORTANT: Use ONLY the test command above. It was auto-detected from this project's package.json by stack-detect.

## Prior Context
Checkpoints: {checkpoints}
Failed approaches (do NOT repeat): {failed_approaches}

## Rules
- NEVER modify test files — tests are the contract
- Follow existing code patterns (read AGENTS.md and nearby source files)
- When done, write PASS or FAIL to {story_id}.result
PROMPT
)" 2>&1
```

**Pi CLI syntax notes (Pi 0.67+):**
- Messages are POSITIONAL, not `-q`
- Use `--print` for non-interactive mode
- Use `--append-system-prompt <file>` to load the tdd-coder agent definition
- No `--yolo` flag exists in Pi; auto-approval happens via settings or extensions
- Pi uses `--provider` and `--model` for model selection

**Escalation model stack (local, zero-cloud):**

Primary escalation uses DeepSeek-R1 32B via local Ollama on GPU 1 — reasoning model for cross-file logic problems:
```
hermes chat -m deepseek-r1:32b --base-url http://localhost:8082/v1 -q "..."
```

Use ONLY for: stalled stories, blocker revisits, Deep Research apply. Normal retries stay on Pi (local Ollama qwen3:8b on GPU 2).

**After coding agent returns PASS:** The agent already validated the story's own tests. No separate Quinn run per story.

Proceed directly to Step 8 (Evaluate Result).

**Multiple stories (parallel):**
Run multiple Pi CLI invocations in parallel (separate processes). Each has its own working directory or uses git worktrees for file isolation.

**Why CLI over MCP:**
- Process isolation — Pi crash never kills Hermes
- No worker thread complexity — just a shell command
- Trivial retry — run the command again
- Each story gets a fresh context — no stale session state
- No session persistence needed — each story is self-contained

### 8. Evaluate Result

Apply progress-aware monitoring using the same detection signals as `dev-team/health-fix`:
- Test pass count: increasing → progress, flat → stalled
- Tool call hashes: repeating 3-call sequences → loop
- Files edited count: 3+ on same file → thrash
- Self-assessment every 3 attempts

**Pi PASS (story tests pass):**

**MANDATORY CROSS-CHECK:** Do NOT trust Pi's PASS at face value. Pi may have used a different test runner or environment. Before proceeding to Step 9, Hermes MUST independently verify by running the story's test file with the stack-detected command:

```bash
cd {project_root} && {test_single_cmd} {test_file} 2>&1
```

- If cross-check PASSES → Proceed to Land the Plane (Step 9)
- If cross-check FAILS → Pi's PASS was unreliable. Treat as Pi FAIL. Re-invoke Pi with explicit instructions: "Your previous PASS was incorrect. The project test runner (`{test_single_cmd}`) shows failures. Fix these tests. Do NOT use any other test runner."

**Pi FAIL with PROGRESS (test count increasing):**
- Re-invoke with checkpoint context. No attempt limit while progress is being made.

**Pi STALLED (same test count for 2 retries):**

> **INVARIANT — read this before invoking the escalation model:** The escalation model (deepseek-r1:32b local) is a *problem solver*, not a *story finisher*. It does NOT call `bd close`, it does NOT run Quinn, it does NOT advance the loop. Every escalation invocation in this skill MUST be followed by the **Verify & Resume** block below. "Escalation model was invoked" is NEVER a terminal state.

1. Try different approach (same Pi local model)
2. Try a second different approach (still Pi local)
3. **Research:** Web search the exact error or failing test. Feed findings to Pi.
4. Re-invoke Pi with research context
5. Escalate to `deepseek-r1:32b` via local Ollama (port 8082) — then run **Verify & Resume** (below).
6. If Verify & Resume returns NO_PROGRESS: failure-classifier → escalation-handler (research findings included)

#### Verify & Resume (mandatory after every escalation model invocation)

```bash
# 1. Re-run the story's own test file independently — do NOT trust the escalation model's self-report.
cd {project_root} && {test_single_cmd} {test_file} 2>&1 | tee /tmp/hermes-{story_id}-postopus.log
TEST_EXIT=$?
```

Branch on the result:

- **PASS** (`TEST_EXIT == 0`) → proceed to **Step 9 (Land the Plane)**: commit, `bd close {id}`, push, then LOOP back to Step 2.
- **PARTIAL PROGRESS** (fewer failing tests than the pre-Opus baseline) → resume Pi with the reduced error set, preserving prior context via the stable session file:
  ```bash
  cd {project_root} && pi --print --continue \
    --provider ollama --model qwen3:8b \
    --session .hermes/sessions/{story_id}.jsonl \
    --append-system-prompt ~/.pi/agents/tdd-coder.md \
    -q "Escalation model attempted a fix and made partial progress. Remaining failures: <paste tail of postopus.log>. Continue from here. Do NOT modify test files."
  ```
  Then return to the top of Step 8 (Evaluate Result) with Pi's new output.
- **NO PROGRESS / SAME ERRORS** → fall through to step 6 above (failure-classifier → escalation-handler). In Step 9a, fall through to Step 9b. In Step 9b Phase 6, loop back to Phase 1 (Root Cause Archaeology) with the new failure data.

**Under no circumstances may this step exit without either landing the story OR explicitly handing off to the next escalation tier.**

**Pi LOOP detected (tool call hash repeat):**
- Stop immediately. Revert changes. Log the approach as failed.
- Re-invoke: "Previous approach looped. Try completely different strategy. Do NOT: {looped approach}"

**Pi THRASH detected (same file edited 3+):**
- Checkpoint progress on other files. Focus Pi on the thrashing file only.

**After any successful fix that required research or 3+ rounds:**
- Save the solution as a learned skill via `skill_manage` (same pattern as health-fix Step 7)

### 9. Land the Plane

**Trigger:** Pi returns PASS on the story's own tests.

**Pre-commit regression check** (targeted, not full suite):

Do NOT run the entire test suite — it may take 30+ minutes and timeout. Instead, run a targeted regression check against only CLOSED stories' test files:

1. Get all closed stories' test files from Beads:
   ```bash
   bd list --status=closed --json
   ```
   Extract `test_file` from each closed story's metadata/description.

2. Run each test file (or batch them into a single jest command):
   ```bash
   cd {project_root} && {test_single_cmd} "file1|file2|file3" 2>&1
   ```
   Use `--testPathPattern` with a pipe-delimited regex of all closed stories' test files. This runs only the tests that SHOULD pass (their stories are done), skipping unimplemented stories entirely.

3. Parse the output:
   - ALL tests pass → no regressions, proceed to landing
   - Any test FAILS → REAL regression (these are closed stories). Stop. Hand back to Pi to fix.

**Why targeted instead of full suite:**
- Full suite includes tests for open/unimplemented stories that are EXPECTED to fail
- Full suite can take 30+ minutes on large codebases, hitting the terminal timeout
- Targeted regression runs only what matters — closed stories that should still work
- Each batch command fits within a single timeout window

If the closed story test file list is very long (20+), split into batches of 10 to avoid extremely long commands.

**Graduated autonomy gate:**

**CRITICAL: When running with `--yolo` flag, ALWAYS use `off` mode — no pausing, no waiting, no Telegram approval. Just land and move on. The `--yolo` flag means TRUE yolo — never pause between stories.**

| Phase | Behavior |
|-------|----------|
| `manual` | Telegram to Bob: "{id} ready to land. Tests pass. [Approve] [Reject] [View Diff]". Wait for approval. |
| `smart` | Auto-land if story matches a graduated skill pattern. Novel stories → ask for approval. |
| `off` | **DEFAULT.** Auto-land. Telegram notification only. No pausing. |

**Landing sequence (after approval or auto-approve):**
1. **COMMIT** — auto-committer stages non-test files, `git commit`
2. **UPDATE BEADS** — `bd close {id}` with result metadata + commit SHA
3. **PUSH** — `git pull --rebase && bd sync && git push`
4. **DISCOVER** — File new Beads issues for any tech-debt or bugs found during implementation
5. **REPORT** — Telegram: "{id} PASS | {duration} | {tests_passed}/{tests_total}"
6. **EPIC CHECK** — Check if all stories in the current epic are now closed (see Step 10)
7. **NEXT** — Run `bd ready --json` again. If stories are ready, go back to Step 3 (Claim). If no stories are ready, proceed to **Step 9a (Blocker Revisit)** before exiting.

### 9a. Blocker Revisit

**Trigger:** `bd ready` returns zero issues, but there are stories that were blocked or skipped earlier in this session.

**Purpose:** Fixes applied during one story may have resolved blockers for another. For example, a polyfill fix committed during Story 4.3 might unblock Story 3.4's fetch issue. Revisiting avoids leaving solvable work on the table.

**Process:**

1. List all stories that were blocked/skipped during this session (tracked in Hermes's session state).
2. If none → exit normally ("All stories complete").
3. For each blocked story, re-run its test file with `{test_single_cmd}`:
   ```bash
   cd {project_root} && {test_single_cmd} {test_file} 2>&1
   ```
4. If tests NOW PASS (blocker was resolved by side-effect of another story's work):
   - Cross-check passes → proceed to Land the Plane (Step 9) for this story
5. If tests still FAIL with the SAME errors as before:
   - **Escalate to deepseek-r1:32b (local).** The first attempt used the default tier — if it couldn't solve it, throw the reasoning model at it with full context:
     ```
     hermes chat -m deepseek-r1:32b --base-url http://localhost:8082/v1 -q "..."
     ```
   - Include in the prompt: the original error, all failed approaches from the Beads issue notes, and any research findings from the first attempt. The escalation model gets the full picture.
   - **Run the Verify & Resume block from Step 8** (re-run `{test_single_cmd} {test_file}`, branch on PASS / PARTIAL / NO_PROGRESS).
     - PASS → land.
     - PARTIAL → resume Pi via `pi -c --session .hermes/sessions/{story_id}.jsonl` with the reduced error set, then re-evaluate.
     - NO_PROGRESS → proceed to **Step 9b (Deep Research & Rearchitect)**.
6. If tests FAIL with FEWER errors (partial progress from side-effects):
   - Re-invoke via `deepseek-r1:32b` (local, port 8082) with the reduced error set. Fewer errors + reasoning model = best chance of finishing.
   - **Run the Verify & Resume block from Step 8.**
     - PASS → land.
     - PARTIAL → resume Pi via `pi -c --session .hermes/sessions/{story_id}.jsonl`, then re-evaluate.
     - NO_PROGRESS → proceed to **Step 9b (Deep Research & Rearchitect)**.

**Why escalate on revisit:** The first pass already exhausted the normal escalation chain (different approach → research → default model). If the story is being revisited, it was too hard for lesser models. DeepSeek-R1 32B (local, port 8082) is the reasoning problem solver — thinks step-by-step for cross-file logic. If the escalation model fails, Deep Research takes over.

**Keep revisiting while making progress.** If Deep Research produces a new approach, try it. If that fails but reveals new information, research again. Only file a P0 blocker Beads issue when Deep Research has genuinely exhausted all alternatives AND two consecutive attempts produced zero new insight. Bob is NOT a developer — filing a blocker that requires human code debugging is a dead end. Solve it.

### 9b. Deep Research & Rearchitect

**Trigger:** Opus failed on a blocker during revisit (Step 9a), OR the regular escalation chain exhausted all strategies during normal story execution.

**Purpose:** When all models fail on the same approach, the problem is the APPROACH, not model capability. Stop coding. Start investigating. Come back with a fundamentally different strategy.

**CRITICAL: Do NOT skip this step and file a human blocker.** Bob is not a developer — filing "awaiting Bob's decision" is a dead end. This step IS the final resolution path.

**Process (Hermes executes directly, NOT delegated to Pi):**

**Phase 1 — Root Cause Archaeology**
1. Read the full error chain and trace it to the actual root cause (not just the symptom)
2. `git log` — find when this code/test last worked and what changed since
3. Check library versions in `package.json` against the error — is this a known breaking change?

**Phase 2 — Deep Web Research**
Search with multiple targeted queries using Hermes's `web` toolset:
```
"{exact_error_message}" github issue
"{library_name} {version}" breaking changes
"{library_name} {error_keyword}" migration guide
"{library_name}" changelog {version}
site:stackoverflow.com "{error_message}"
site:github.com/{library_repo}/issues "{error_keyword}"
```
Read the top results. Extract:
- Is this a known issue? What's the official fix?
- Did a version upgrade cause this? What's the migration path?
- Are other people solving this differently?

**Phase 3 — Question Every Assumption**
List every assumption the failed approaches made, and challenge each:
- "We assumed jsdom needs fetch polyfilled" → What if we change test env to `node`?
- "We assumed this test needs jsdom" → Does it actually use DOM APIs?
- "We assumed the mock must use globalThis" → Can we use jest.mock() instead?
- "We assumed the library API works this way" → Did the API change in this version?

For each challenged assumption, check if the alternative is viable.

**Phase 4 — Alternative Architecture**
Based on research findings and challenged assumptions, propose 2-3 completely different approaches that **sidestep** the problem entirely (don't try to fix the original approach — go around it):
- Different test environment configuration
- Different mocking strategy
- Different library/API usage
- Restructuring the code to avoid the problematic dependency

Pick the simplest approach that has evidence of working (from web research or codebase patterns).

**Phase 5 — Isolated Prototype**
Before touching the project, verify the new approach works:
```bash
mkdir -p /tmp/hermes-prototype-{story_id}
cd /tmp/hermes-prototype-{story_id}
# Create minimal reproduction with the new approach
# Run it — does it work?
```
If the prototype passes → apply to the project via `deepseek-r1:32b` (local, port 8082) with the proven approach.
If the prototype fails → try the next alternative from Phase 4.

**Phase 6 — Apply & Verify**
Invoke the escalation model with the researched, prototyped, proven approach:
```
hermes chat -m deepseek-r1:32b --base-url http://localhost:8082/v1 -q "..."
```
Include: the working prototype code, the root cause analysis, the specific approach to use, and explicit instructions on what NOT to do (all previous failed approaches).

**Run the Verify & Resume block from Step 8** — the escalation model does not finish the story on its own.

- PASS → return control to the work-loop and proceed to **Step 9 (Land the Plane)**, then LOOP back to Step 2. Vibe-loop's gate ("all stories closed → Phase 10b → 10c → 11") fires automatically once the story lands.
- PARTIAL → resume Pi via `pi --print --continue --provider ollama --model qwen3:8b --session .hermes/sessions/{story_id}.jsonl --append-system-prompt ~/.pi/agents/tdd-coder.md` with the reduced error set, then re-evaluate at Step 8.
- NO_PROGRESS → loop back to Phase 1 (Root Cause Archaeology) with the new failure data. Keep looping while producing new insights. Only file a P0 blocker Beads issue when TWO consecutive Deep Research cycles produce zero new insight — tag as `needs-deep-research-round-2` with ALL accumulated research, prototype results, and failed approaches so the next session continues from findings, not from scratch.

**Key principle:** This step produces KNOWLEDGE even if it doesn't produce a fix. Each cycle narrows the problem space. The next cycle (or next session) starts with everything accumulated, not from zero. Bob is NOT a developer — every cycle must resolve autonomously or build toward autonomous resolution.

### 10. End-of-Epic Review

**Trigger:** After closing a story, check if ALL stories with the same `epic-{N}` label are now closed:
```bash
bd list -l epic-{N} --json
```
If any are still open → skip, continue to next story.

**If all stories in the epic are closed**, run a thorough review:

1. **Epic test suite (targeted):**
   Collect all test files for stories in this epic:
   ```bash
   bd list -l epic-{N} --json
   ```
   Extract `test_file` from each story, then run them as a batch:
   ```bash
   cd {project_root} && {test_single_cmd} "epic_test1|epic_test2|..." 2>&1
   ```
   ALL tests for this epic's stories must pass (they're all closed now). Any failure is a real bug — file a Beads issue.

2. **Build verification:**
   ```bash
   cd {project_root} && npm run build 2>&1
   ```
   Must complete without errors.

3. **Quinn adversarial code review (MANDATORY):**

   Pi writes both tests and code — they share the same blind spots. Quinn catches what tests can't: omissions, dead code, composition errors, security issues, spec deviations.

   Collect all files changed across the epic's stories:
   ```bash
   git diff {commit-before-epic}..HEAD --name-only
   git diff {commit-before-epic}..HEAD
   ```

   Invoke `bmad-code-review` skill (or run the review layers directly) with three parallel reviewers:
   - **Blind Hunter** — diff only, no context. Finds bugs and security issues.
   - **Edge Case Hunter** — diff + project read access. Finds unhandled edge cases.
   - **Acceptance Auditor** — diff + story spec files. Checks every AC is met.

   Triage findings:
   - Critical/High → P0 beads issue tagged `epic-{N}-review`
   - Medium → P1 beads issue tagged `epic-{N}-review`
   - Low/Defer → P2 beads issue tagged `epic-{N}-review`

   **Fix loop:** If P0/P1 findings were filed, claim each, invoke Pi to fix, verify, and land. Loop until all P0/P1 `epic-{N}-review` issues are closed. P2 findings remain open for future sessions.

4. **Epic report:**
   ```
   Epic {N} Complete — {epic title}
   Stories: {count} closed
   Tests: {total passing}
   Build: {pass/fail}
   Quinn review: {findings_total} findings ({fixed} fixed, {deferred} deferred, {dismissed} dismissed)
   ```
   Report via Telegram.

This runs ONCE per epic, not per story. Deep adversarial review adds value after all the pieces are in place and can be evaluated as a whole.

### 11. Budget Guard

Budget caps are disabled. The work-loop runs until all ready stories are complete. Do NOT stop early due to cost — keep looping until `bd ready` returns zero.

## Error Handling

- If Pi subagent crashes without returning: read `.result` marker file as fallback
- If `bd` CLI fails: log error, skip issue, continue with next
- If git push fails: retry once with `git pull --rebase`, then alert via Telegram
- If tests fail due to environment issues (DB connection, native module errors): classify as INFRA via failure-classifier → escalation-handler. Do NOT attempt to fix by editing tests.
- Never leave an issue in `in_progress` without a checkpoint — always write status before exiting

## Dependencies

- Pi CLI: `pi` command (invoked as child process, not MCP)
- Pi agent definitions: `~/.pi/agents/tdd-coder.md`, `~/.pi/agents/failure-classifier.md`
- Quinn review: MANDATORY, runs once per epic (Step 10). Uses `bmad-code-review` skill with three parallel layers (Blind Hunter, Edge Case Hunter, Acceptance Auditor). Files findings as beads issues, fixes P0/P1 before proceeding.
- Pi extensions: `beads-checkpoint.ts`, `failure-classifier.ts`, `budget-enforcer.ts`, `auto-committer.ts`
- Hermes skills: `escalation-handler` (for failure routing), `health-fix` (pre-flight error resolution), `stack-detect` (pre-flight stack detection)
- Hermes toolsets: `web` (for error research during stall escalation)
- Hermes tools: `skill_manage` (for saving learned solutions)
- External: `bd` CLI, `git`, project test runner (auto-detected by `stack-detect` — NEVER hardcode)
