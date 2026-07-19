# Aspirational vs Enforced Instructions — Case Study

## The Problem (2026-06-25)

Drain prompts told agents to run Quinn and Murat reviews.
Agents logged `quinn_review: true, murat_review: true` but
never actually called delegate_task. They treated quality gates
as a LOGGING exercise, not an EXECUTION exercise.

## Root Cause

The prompt said "do X" but provided no mechanism to verify X happened.
The agent could satisfy the instruction by writing "done" in a log file
without any tool call.

## The Fix

Made Level 2 quality review ENFORCED with:

1. **Exact execution steps** (not just "do X")
   - "Call delegate_task(goal='Review diff...', context='...')"
   - "Wait for response before continuing"

2. **Enforcement check before logging**
   - "Did you ACTUALLY call delegate_task? Check your tool calls."
   - "If you skipped a gate, set it to FALSE — never mark true without executing."

3. **Honest logging example**
   - Show what FALSE looks like: "quinn_review: false, reason: token limit"

## Results

**June 26, 2026:** First night — agents logged gates as "pending" (not executed)

**June 27, 2026:** Second night — agents logged gates as FALSE (honest — nothing to review)

**June 28, 2026:** Third night — agents logged gates as FALSE even when beads were closed
- Drain closed 1 bead (wprl) but `quinn_review: false, murat_review: false`
- Agents followed drain prompt's OLD quality gates, not the Level 2 gates
- Root cause: Level 2 gates were in bead-execution skill but agents loaded vibe-loop skill
- **Actual Fix:** Level 2 gates stayed in bead-execution. Removed OLD quality gates from all 27 drain prompts. Added "CODE QUALITY OVER SPEED" emphasis. All drains now load bead-execution.

**The enforcement is working — agents are now honest about what they did.**
**But agents still skip Level 2 gates when they're not in the skill they load.**

## Architectural Lesson

**Don't create duplicate skills for the same function.**

The bead-execution skill was created to document quality gates, but this
duplicated functionality that should be in vibe-loop. This caused:
1. Confusion about which skill to use
2. Agents loading vibe-loop but not bead-execution
3. Quality gates being skipped

**Correct architecture (2026-06-28 fix):**
- bead-execution = SINGLE SOURCE OF TRUTH for Level 2 quality gates
- Drain prompts = NO quality gates (removed old ones)
- All drain jobs load bead-execution skill
- "CODE QUALITY OVER SPEED" emphasis in all drain prompts

## Rule of Thumb

If the instruction can be satisfied by writing "done" in a log file
without any tool call, it's aspirational, not enforced.

To make it enforced:
- Require a specific tool call (delegate_task, terminal, etc.)
- Require waiting for the tool's response
- Add a verification step before marking as complete
