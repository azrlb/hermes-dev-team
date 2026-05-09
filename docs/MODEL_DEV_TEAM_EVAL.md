# Model Dev-Team Evaluation Template

**Purpose:** Standardized benchmark for evaluating LLM models as autonomous dev-team members. Tests real-world coding ability, not academic benchmarks. Run via Hermes Pi against a prepared test repo.

**Created:** 2026-04-12
**Origin:** Quinn R3 review of GLM 5.1 (qwen3.5:cloud) fixing auth security bugs in FlowInCash-Core.

---

## Why This Exists

Anthropic won't allow third-party tools (Hermes/Pi) to use Claude via auth subscriptions, and `claude -p` doesn't work with Pi. So we need to find the best alternative models that can run 24/7 as autonomous dev-team members. Academic benchmarks (HumanEval, MMLU) don't predict real-world dev performance. This template does.

---

## Test Architecture

```
1. PREPARE    → Plant known bugs in a test branch (the "challenge set")
2. LAUNCH     → Run Hermes with the candidate model against the bugs
3. GRADE      → Quinn code review (always on a strong model) grades the output
4. SCORE      → Fill in the scorecard
```

**Critical:** The grading model must ALWAYS be stronger than the candidate. Use Claude Opus or equivalent for Quinn review.

---

## The Challenge Set (5 Tiers)

Each tier tests a distinct capability. A model that passes Tier N but fails Tier N+1 tells you exactly what it can and can't do autonomously.

### Tier 1: Workflow Execution (can it operate?)

**What:** Navigate a real repo, find files, read beads issues, claim work, commit, push.
**How to test:** Give it a trivial fix (typo in a comment, rename a variable) and see if the full workflow completes.
**Grading:**
- [ ] Read AGENTS.md / CLAUDE.md
- [ ] Found the right file
- [ ] Claimed the beads issue (`bd update --claim`)
- [ ] Made the correct edit
- [ ] Committed with proper prefix
- [ ] Closed the beads issue
- [ ] Pushed to remote

**Pass criteria:** All checkboxes. This is table stakes.

### Tier 2: Guard Clause / Input Validation (basic code reasoning)

**What:** Add defensive checks — null guards, throw on invalid input, reject empty strings.
**Example bugs to plant:**
- Function returns unfiltered data when a required parameter is missing
- Date field defaults to `new Date()` instead of rejecting missing values
- Optional parameter accepted without validation

**Grading:**
- [ ] Identified the correct code location
- [ ] Fix is logically correct (throws/rejects, doesn't silently pass)
- [ ] Fix doesn't break callers (or documents the breaking change)
- [ ] No unrelated changes

**Pass criteria:** Correct fix, no collateral damage.

### Tier 3: Domain-Specific Logic (does it understand the problem?)

**What:** Implement logic that requires domain knowledge — crypto, financial calculations, protocol handling, SQL query building.
**Example bugs to plant:**
- Certificate chain validation that checks format but not cryptographic signatures
- Financial rounding that uses floating point instead of decimal
- SQL query builder that doesn't parameterize user input
- JWT validation that decodes without verifying signature

**Grading:**
- [ ] Fix demonstrates real domain understanding (not pattern matching)
- [ ] Implementation is cryptographically/mathematically correct
- [ ] No security theater (looks secure but isn't)
- [ ] Appropriate use of standard libraries (not hand-rolled crypto)

**Pass criteria:** A security-aware human reviewer can't find a bypass.

### Tier 4: Test Discipline (does it prove its work?)

**What:** Write tests for the fixes it made. Not "does it write tests when asked" — does it write them unprompted as part of completing the fix?
**Grading:**
- [ ] Tests exist for each fix
- [ ] Tests cover the happy path
- [ ] Tests cover the edge case that was the bug
- [ ] Tests use the project's test framework (not a different one)
- [ ] All tests pass

**Pass criteria:** Each fix has at least one test covering the bug scenario.

### Tier 5: Scope Discipline (does it follow instructions?)

**What:** Fix ONLY what was asked. Don't refactor surrounding code, don't add features, don't "improve" things.
**Grading:**
- [ ] Changes are limited to the files/functions mentioned in the issue
- [ ] No unrequested new functions or modules
- [ ] No removed warning comments or safety documentation
- [ ] Commit message accurately describes what changed
- [ ] No scope creep (extra features, premature abstractions)

**Pass criteria:** `git diff --stat` shows only the expected files changed.

---

## Scorecard Template

```
Model Evaluation Scorecard
==========================
Date:           ____
Model:          ____
Provider:       ____
Context window: ____
Hermes config:  ____

Challenge Set:  [repo/branch]
Grading Model:  [model used for Quinn review]

Results:
                        Pass/Fail   Notes
Tier 1 - Workflow:      [ ]         ____
Tier 2 - Guard clauses: [ ]         ____
Tier 3 - Domain logic:  [ ]         ____
Tier 4 - Test writing:  [ ]         ____
Tier 5 - Scope control: [ ]         ____

Overall Grade: ___/5

Strengths:
-

Weaknesses:
-

Recommendation:
[ ] Full autonomous (all tiers pass)
[ ] Supervised autonomous (Tier 1-2 pass, use for simple tasks only)
[ ] Interactive only (needs human steering)
[ ] Not suitable for dev team
```

---

## Reference: GLM 5.1 Baseline (2026-04-12)

First model evaluated using this template (before it was formalized):

```
Model:          qwen3.5:cloud (GLM 5.1)
Provider:       Ollama cloud
Context window: 256K
Challenge:      3 Quinn R2 security bugs in FlowInCash-Core auth package

Tier 1 - Workflow:      [PASS]  Full cycle completed correctly
Tier 2 - Guard clauses: [PASS]  Null checks and throw-on-missing landed
Tier 3 - Domain logic:  [FAIL]  Fake cert chain validation (security theater)
Tier 4 - Test writing:  [FAIL]  Zero tests written for any fix
Tier 5 - Scope control: [FAIL]  Added cert gen/rotation code nobody asked for

Overall Grade: 2/5

Recommendation: Supervised autonomous — good for simple guard clauses,
input validation, and workflow tasks. Cannot handle crypto/security logic
or self-directed test writing. Needs stronger model for domain-specific work.
```

---

## Running an Evaluation

### 1. Prepare the challenge branch

```bash
# Create a branch with known bugs planted
git checkout -b eval/model-test-<model-name>
# Plant bugs across the 5 tiers (or use a pre-built challenge set)
# Commit the buggy state
git push -u origin eval/model-test-<model-name>
```

### 2. Create beads issues for each bug

```bash
bd create --title="[EVAL-T1] Fix typo in config comment" --type=bug --priority=2
bd create --title="[EVAL-T2] Add null check for userId in handler" --type=bug --priority=2
bd create --title="[EVAL-T3] Implement HMAC signature verification" --type=bug --priority=1
# Tag with EVAL prefix so they're easy to find and clean up
```

### 3. Launch Hermes with the candidate model

```bash
LOG=~/.hermes/logs/eval-$(date +%s).log

setsid -f bash -c 'cd /path/to/test-repo && \
  hermes chat --yolo -m <candidate-model> \
  -q "Fix all open EVAL bugs. Read AGENTS.md first. Claim each issue with bd before starting. Write tests for each fix. Commit with fix(): prefix. Close issues with bd close when done." \
  > '"$LOG"' 2>&1'
```

### 4. Grade with Quinn review

After Hermes completes, run `bmad-code-review` (Quinn) using a strong model (Claude Opus) to review the diff. Use this conversation's Quinn R3 approach:

```bash
# Get the diff of what the model changed
git diff <baseline-commit>..HEAD > /tmp/eval-diff.patch
# Run Quinn review via Claude Code / bmad-code-review skill
```

### 5. Fill in the scorecard

Map Quinn findings to tiers. Each tier is binary pass/fail based on the criteria above.

---

## Models to Evaluate

Priority candidates (available via Ollama cloud or direct API):

| Model | Provider | Context | Status |
|-------|----------|---------|--------|
| qwen3.5:cloud | Ollama | 256K | Baseline (2/5) |
| deepseek-v3 | DeepSeek API | 128K | Pending |
| codestral | Mistral API | 256K | Pending |
| gemini-2.5-pro | Google API | 1M | Pending |
| grok-3 | xAI API | 128K | Pending |
| llama-4-maverick | Meta/Ollama | 1M | Pending |

---

## Evolving the Challenge Set

The challenge set should grow as you find new failure modes:

- **2026-04-12:** Added crypto domain test (mTLS chain validation) — caught GLM 5.1
- Add financial domain tests (decimal rounding, tax calculations)
- Add concurrency tests (race conditions, atomic operations)
- Add integration tests (multi-file refactors, API contract changes)
- Add "trap" tests (planted code that looks wrong but is intentional — tests whether model over-corrects)
