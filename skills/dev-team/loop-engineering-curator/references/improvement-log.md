# Loop Engineering Improvement Log

Tracking approved improvements and their measured impact.

---

## Initial Audit — 2026-06-25

### Baseline Measurements (before improvements)

**Goal Clarity (Audit 1):**
- FlowInCash-Core drains: 2/4 (have bead list, no exit conditions)
- Crispi drains: 2/4 (have bead list, no exit conditions)
- Average: 2/4

**Quality Gates (Audit 2):**
- Bead-execution skill enforces: tests → verify → attest → close
- Quinn review: NOT enforced in overnight drain prompts
- Gap: Drains could close beads without adversarial review
- Score: 2/4

**Logging (Audit 3):**
- No structured drain logs exist
- Morning handoff uses git log reconstruction
- Pipeline watchdog detects stalls only
- Score: 1/4

**Safety Limits (Audit 4):**
- No runtime limits in drain prompts
- No max-bead limits
- No retry limits (bead-execution has 3-failure pattern but drains don't reference it consistently)
- Score: 0/4

**Process Effectiveness (Audit 5):**
- Overnight drains productive (8 beads closed last night for FlowInCash-Core)
- Crispi slower (2 beads closed, 20 "blocked" = deferred)
- Score: 3/4

**OVERALL BASELINE: 8/20**

---

### P6: Wire TEA/Murat into Overnight Drains (LEVEL 2 — BATCH)
- **Problem:** 5-layer quality pipeline designed but only Layer 1 (dev+tests) runs
- **Gap:** Quinn review, Murat RV, Murat NFR, E2E validation NOT enforced
- **Fix:** Updated bead-execution skill + drain prompts with Level 2 batch review
- **Effort:** MEDIUM-HIGH
- **Expected impact:** P0 quality gap closed — biggest single improvement
- **Status:** ✅ IMPLEMENTED 2026-06-25
- **What changed:**
  - Added "Level 2 Quality Review" section to bead-execution skill
  - Removed per-bead Quinn/Murat instructions from drain prompts
  - Added batch review at END of drain (catches composition bugs)
  - Flow: self-review → Quinn subagent → Murat subagent → traceability
  - All 14 drain prompts updated
- **Key design decision:** Batch review at end of drain, not per-bead
  - Per-bead: misses A+B composition bugs, expensive
  - Per-drain: catches composition bugs, right timing
  - Cross-drain: too late, bugs compound overnight

**VALIDATED INTEGRATION PLAN (from quinn-vs-tea-integration.md):**
```
Phase 10:  Dev (Pi writes code + tests)
Phase 10b: Pattern capture
Phase 10c: Quinn adversarial review (3 layers) — SUBAGENT via delegate_task
Phase 10d: Murat test quality review (RV) — SUBAGENT via delegate_task
Phase 10e: Murat NFR audit (NR) — SUBAGENT via delegate_task (conditional)
Phase 11:  E2E validation
Release:   Murat traceability + gate (TR) — SUBAGENT via delegate_task
```

**Independence principle:** All reviewers (Quinn + Murat) run as SEPARATE
SUBAGENTS via delegate_task. Developer ≠ reviewer — enforced at architecture level.

**Impact assessment:** This is the highest-impact single improvement.
Current score: 8/20. After P1-P4 + P6: projected 18-19/20.

---

## Session Log

### 2026-06-25 — Full Loop Engineering Implementation
- P1: Goals + exit conditions → 14 drain prompts updated
- P2: Structured logging → drain-logger skill + drain-log-reader.py
- P3: Quinn review enforced → 14 drain prompts updated
- P4: Safety limits → 14 drain prompts updated
- P6: TEA/Murat wired in → bead-execution updated with Level 2
- Key learning: "aspirational vs enforced" — agents log "done" without executing
- Fix: Made Level 2 ENFORCED with explicit execution steps + enforcement check
- Vibe-loop vs bead-execution distinction documented

### 2026-06-26 — First Night Results
- Crispi: 5 beads closed in one slot, quality gates logged as "pending"
- FlowInCash-Core: 0 beads closed (queue drained)
- Finding: Agents logged quality gates as true without executing them
- Fix: Updated bead-execution with enforcement check + honest logging rule

### 2026-06-27 — Second Night Results
- All drains: 0 beads closed (queues empty)
- Quality gates: ALL FALSE (honest — nothing to review)
- Level 2 enforcement working (honest logging) but can't be tested (empty queues)

## 2026-07-10 — Backlog Exhaustion & Action Prioritization
- **Problem:** Drains are running successfully but closing 0 beads because backlogs are entirely blocked, require human action, or are epics needing decomposition. Drains consume tokens processing blocked items.
- **Fix:** Standardized the concept of "Backlog Exhaustion" under Audit 5 (Process Effectiveness) and categorized typical blocked types (Legal/Safety, Epics, Placeholders, Human-Action).
- **Impact:** Decreases token wastage by identifying blocked queues immediately and prompting the operator to either decompose Epics, clean up placeholders, or perform the necessary offline actions.
- **Status:** ✅ IMPLEMENTED 2026-07-10

## Pending Improvements (awaiting Bob's approval)

### P1: Add Goals + Exit Conditions to All Drain Prompts
- **Effort:** LOW
- **Expected impact:** +1 to Audit 1 (2→3/4)
- **Status:** ✅ IMPLEMENTED 2026-06-25
- **What changed:** 14 drain prompts updated with:
  - Explicit GOAL (close P0/P1 beads, stop at 5 max)
  - EXIT CONDITIONS (dependency blocked, context full, 2hr limit, Bob decision needed)
  - QUALITY GATES (tests before commit, attestation, all tests pass)
  - SAFETY LIMITS (max 5 beads, max 3 consecutive failures)
  - FINAL REPORT requirement (what closed, what failed, why stopped)
- **Measurable:** Tonight's drains will be the first with P1 — compare tomorrow's audit

### P2: Add Structured Drain Logging
- **Effort:** MEDIUM
- **Expected impact:** +2 to Audit 3 (1→3/4)
- **Status:** ✅ IMPLEMENTED 2026-06-25
- **What changed:**
  - Created `drain-logger` skill with JSON log format
  - Created `drain-log-reader.py` script for morning handoff
  - Added logging instructions to all 14 drain prompts
  - Created ~/.hermes/drain-logs/ directory structure
- **Measurable:** Tomorrow's morning handoff can read structured logs

### P3: Enforce Quinn Review Before Bead Close
- **Effort:** LOW
- **Expected impact:** +1 to Audit 2 (2→3/4)
- **Status:** ✅ IMPLEMENTED 2026-06-25
- **What changed:**
  - Added mandatory Quinn review gate to all 14 drain prompts
  - 3 review layers enforced: Blind Hunter, Edge Case Hunter, Acceptance Auditor
  - P0/P1 findings must be fixed before bead close
  - quality_gates.quinn_review tracked in structured logs

### P4: Add Safety Limits to Drain Prompts
- **Effort:** LOW-MEDIUM
- **Expected impact:** +2 to Audit 4 (0→2/4)
- **Status:** ✅ IMPLEMENTED 2026-06-25
- **What changed:**
  - Max 5 beads per run
  - Max 2 hours runtime
  - Max 2 retries per bead
  - Max 3 consecutive failures before stopping
  - Token budget awareness (wrap up if responses getting long)
  - All 14 drain prompts updated

### P5: Extract Shared Routines into Skills
- **Effort:** MEDIUM-HIGH
- **Expected impact:** +1 to multiple audits, long-term maintainability
- **Status:** DEFERRED — do after P1-P4 + P6 are measured

**PROJECTED SCORE AFTER P1-P4 + P6: 17-18/20 (+9-10 points)**
