---
name: drain-logger
description: >
  Structured logging for overnight drain sessions. Each drain writes a
  JSON log file when it finishes. Morning handoff reads these logs.
triggers:
  - "write drain log"
  - "log drain results"
  - "drain summary"
version: 1.2.6 # Added mandatory standardized skip categories enforcement with concrete overflow exhaustion example
author: hermes-agent
tags: [drain, logging, structured, morning-handoff]
---

# Drain Logger

Write a structured JSON log after every drain session.
The morning handoff reads these logs to build a daily summary.

**Log reader script:** See `references/drain-log-reader.md` for the
`drain-log-reader.py` script location and usage.

## THINK BEFORE ACTING (MANDATORY)

Before ANY fix, action, or change — pause and answer these questions:

1. **What is the ROOT CAUSE?** (not just the symptom)
2. **What is the MATH?** (display sizes, scale factors, dimensions, costs)
3. **What is the CONTEXT?** (where does this output appear? what is the display environment?)
4. **Have I VERIFIED?** (check the output BEFORE showing it to the user)

If you cannot answer all four, STOP and investigate before acting. Speed is not the goal — getting it RIGHT the first time is. Every quick fix that fails wastes the user time and trust.


## When to Write

Write the log as the VERY LAST action before your final response.
Do NOT skip this step — the morning handoff depends on it.

**This applies even when zero beads were processed.** A `pool-exhausted` drain
that found nothing to do still needs a log entry — the morning handoff reads
these to know the drain ran and the pool was empty. Without the log, the
handoff assumes the drain crashed or never executed.

**⚠ CRITICAL: Pool-exhausted drains MUST write a log.** This is the most
common failure mode for drains that find nothing to do. The agent sees
"nothing to implement" and skips straight to the markdown report without
writing the structured JSON log. The morning handoff reads JSON logs, not
markdown reports. If you write a markdown report but no JSON log, the
handoff won't see your drain ran.

**⚠ CRITICAL: Overwrite existing logs, do NOT append.** Cron jobs often
re-trigger drains for the same project/scope on the same day. If the log
file already exists, OVERWRITE it with the latest state. Logs are per-date,
not append-only. The morning handoff reads the latest log for each slot,
not a history of all runs. Overwriting ensures the handoff sees the most
recent state, not stale data from an earlier run.

**Checklist before final response:**
1. Did I write the markdown drain report? (for human consumption)
2. Did I write the JSON drain log? (for morning handoff automation)
3. Did I set `exit_reason` correctly? (`pool-exhausted` for empty scope, not `completed`)

## Log Format

Write to: `~/.hermes/drain-logs/YYYY-MM-DD/<project>-<slot>.json`

Example: `~/.hermes/drain-logs/2026-06-25/flowincash-core-8pm.json`

```json
{
  "drain_id": "2970e93d",
  "project": "FlowInCash-Core",
  "time_slot": "8pm",
  "date": "2026-06-25",
  "start_time": "2026-06-25T20:01:06-07:00",
  "end_time": "2026-06-25T21:15:32-07:00",
  "duration_minutes": 74,
  "goal": "Close all P0 and P1 beads",
  "exit_reason": "completed",
  "re_run": false,
  "re_run_reason": null,
  "beads_attempted": [
    {"id": "Core-ua4", "status": "closed", "tests_passed": true},
    {"id": "Core-3di", "status": "closed", "tests_passed": true},
    {"id": "Core-1bb", "status": "failed", "error": "test regression in counterparty service"}
  ],
  "beads_closed": ["Core-ua4", "Core-3di"],
  "beads_failed": ["Core-1bb"],
  "beads_skipped": ["Core-ao4", "Core-pmw"],
  "tests_run": 47,
  "tests_passed": 45,
  "tests_failed": 2,
  "git_commits": ["abc1234", "def5678"],
  "quality_gates": {
    "self_review": false,
    "quinn_review": false,
    "quinn_result": null,
    "murat_review": false,
    "murat_score": null,
    "traceability_check": false
  },
  "issues": [
    "Core-1bb: test regression needs investigation"
  ]
}
```

## How to Write

**ALWAYS use `write_file` tool — never shell heredocs.**

In cron context, `execute_code` is blocked. Use `write_file` directly. The
`write_file` tool writes to `~/.hermes/` paths without triggering the Tirith
security scanner, unlike shell redirects.

**Do NOT use shell heredocs** (`cat > ~/.hermes/... << 'EOF'`). Two reasons:
1. **Tirith flags them** as dotfile overwrites (may auto-reject).
2. **Single-quoted heredocs (`<< 'EOF'`) don't expand variables** — your JSON
   will contain literal `$(date +%H%M%S)` instead of the actual timestamp,
   producing broken drain logs that the morning handoff can't parse.

**Correct pattern (terminal tool):**
```bash
cat > ~/.hermes/drain-logs/$(date +%Y-%m-%d)/<project>-<slot>.json << 'LOGEOF'
{
  "drain_id": "2970e93d",
  "project": "FlowInCash-Core",
  "time_slot": "8pm",
  "date": "2026-06-25",
  "exit_reason": "completed",
  "beads_attempted": [],
  "beads_closed": [],
  "beads_failed": [],
  "beads_skipped": [],
  "tests_run": 0,
  "tests_passed": 0,
  "tests_failed": 0,
  "git_commits": [],
  "quality_gates": {
    "self_review": false,
    "quinn_review": false,
    "quinn_result": null,
    "murat_review": false,
    "murat_score": null,
    "traceability_check": false
  },
  "issues": []
}
LOGEOF
```
⚠ This only works for static content. If your JSON contains dynamic values
(drain_id, date, bead counts), you MUST build the JSON first, then write it.

**Best pattern — use `write_file` tool directly:**
```python
# Call write_file(path, json_string) with the fully-resolved JSON content.
# The drain_id should be a short hash or timestamp, e.g. "drain-$(date +%H%M%S)"
# or a fixed string — NOT a shell expansion inside the JSON.
```

Example `write_file` call:
```
write_file(
    path="~/.hermes/drain-logs/2026-06-25/crispi-app-overflow-drain.json",
    content='{\n  "drain_id": "overflow-drain-203542",\n  "project": "Crispi-app",\n  ...\n}'
)
```

**Avoid `execute_code` in cron context** — it is blocked by security approval.
Use `write_file` directly for log creation.

## How Morning Handoff Reads Logs

```bash
# Read all logs from yesterday
date=$(date -d "yesterday" +%Y-%m-%d)
cat ~/.hermes/drain-logs/$date/*.json 2>/dev/null | python3 -c "
import sys, json
for line in sys.stdin:
    try:
        log = json.loads(line)
        print(f\"{log['project']} ({log['time_slot']}): {len(log.get('beads_closed',[]))} closed, {len(log.get('beads_failed',[]))} failed\")
    except: pass
"
```

## Key Fields Explained

- `exit_reason`: WHY the drain stopped
  - `completed` — goal achieved, at least one bead was implemented and closed this session
  - `pool-exhausted` — all open beads in the target scope are non-implementable (tracking markers, design tasks, epic markers, blocked items, explicitly deferred). No code to write. This is the MOST COMMON exit for overflow/specialized drains. **Use this when the drain found zero implementable beads, even if the drain prompt said "done when all ready beads are closed"** — the distinction is whether any work was actually done.
  - `limit-hit` — hit max beads (5) or max time (2hrs)
  - `dependency-blocked` — stuck on blocked bead
  - `context-full` — responses getting too long
  - `error` — unexpected failure
  - `bob-decision` — needs Bob's input
- `re_run` (boolean, optional): Set to `true` when a drain log already exists for this scope/date and bead state is unchanged. The re-run detection pattern (from bead-execution skill) checks `ls ~/.hermes/drain-logs/YYYY-MM-DD/<project>-<slot>.json` before triaging. If the log exists and bead counts match, skip to report. Include `re_run_reason` string explaining why this is a rerun (e.g., "Drain log already exists for this scope. Bead state unchanged.").
- `re_run_reason` (string, optional): Explains why `re_run` is true. Only set when `re_run: true`.
- `overflow_check` (object, optional): Include when the drain checked overflow/fallback projects. Structure per project:
  ```json
  "overflow_check": {
    "projects_checked": ["FlowInCash", "FlowInCash-Core"],
    "FlowInCash": {"open_beads": 37, "ready_beads": 37, "implementable": 0, "reason": "All human-gated or cross-repo"},
    "FlowInCash-Core": {"open_beads": 0, "reason": "Empty pool"}
  }
  ```
  **Include when:** Primary project is exhausted and drain checked other projects for work.
  **Omit when:** Drain only processed the primary project (no overflow check needed).

  **Pool-exhausted overflow example (no work found anywhere):**
  ```json
  "overflow_check": {
    "projects_checked": ["FlowInCash", "LivingApp-Sidecar"],
    "FlowInCash": {"open_beads": 51, "implementable": 0, "reason": "All blocked by cash-flow engine epic, App Store gating, or video tasks"},
    "LivingApp-Sidecar": {"open_beads": 10, "implementable": 0, "reason": "RL Training Platform epic (all child tasks) + Railway deploy (Bob-owned)"}
  }
  ```

  **⚠ Field name is `overflow_check`, NOT `overflow_summary`.** The orchestrated-drain skill historically used `overflow_summary` in examples, but drain-logger owns the schema. Always use `overflow_check`.

  **Pitfall: `completed` vs `pool-exhausted`** — A drain that targets "Epics 7-12" and finds all those beads already closed should use `pool-exhausted`, NOT `completed`. The `completed` exit implies the drain achieved its goal by doing work; `pool-exhausted` means there was no work to do. Morning handoff needs to know the difference — `completed` means "nothing left to do"; `pool-exhausted` means "the pool was empty this run, try a different scope next time."

- `quality_gates.self_review`: Did you scan the diff for obvious issues?
- `quality_gates.quinn_review`: Did Quinn run adversarial review? (boolean)
- `quality_gates.quinn_result`: Quinn's verdict — PASS or FAIL (null if not run)
- `quality_gates.murat_review`: Did Murat score test quality? (boolean)
- `quality_gates.murat_score`: Murat's 0-100 score (null if not run)
- `quality_gates.traceability_check`: Did you verify all closed beads have tests?

## Quality Gates Reference

The quality_gates field in the log should reflect ACTUAL execution
of the Level 2 gates defined in `dev-team/bead-execution`:

- `self_review: boolean` — Did you scan the diff for obvious issues?
- `quinn_review: boolean` — Did you call delegate_task for adversarial review?
- `murat_review: boolean` — Did you call delegate_task for test quality scoring?
- `traceability_check: boolean` — Did you verify all closed beads have tests?

**CRITICAL:** Only set a gate to true if you ACTUALLY EXECUTED it.
If the drain prompt doesn't mention these gates, set them to false
with an honest reason (e.g., "drain prompt did not include Level 2 gates").

See `dev-team/bead-execution` for the full Level 2 quality review
procedure and enforcement rules.

## Pitfalls

- **Epic-scope empty check (fast-path):** Before investigating individual beads, check if ALL beads for the target epic/scope are already closed. Run `bd list --json` and filter by epic label or story prefix. If zero open beads exist in scope → use `pool-exhausted` exit, skip to log + report. Do NOT spend time triaging individual non-implementable beads when the whole scope is done. This saves significant context and time.
- **Stale sprint-status.yaml / story-spec files:** Files like `_bmad-output/implementation-artifacts/sprint-status.yaml` or `docs/stories/*.md` may show stories as "ready-for-dev" when the actual beads are CLOSED. These files are NOT updated by `bd close` — they drift. Always trust `bd list --status open` over file-based status. If you find yourself checking individual bead IDs from a status file one-by-one, you're likely chasing stale data. The fast-path check (`bd list --status open --json | python3 -c "..."` filtered by scope) catches this immediately and saves ~20 tool calls.
- Write the log BEFORE your final response, not after
- If the drain crashes before writing, the log is lost — that's OK,
  the morning handoff falls back to git log
- Don't include sensitive data (API keys, passwords) in logs
- Keep the JSON clean — no trailing commas, proper quoting
- **Pool exhaustion is common.** When ALL open beads are non-implementable (tracking markers for other repos, design/research tasks, epic markers, blocked items, explicitly deferred), use `exit_reason: "pool-exhausted"` and list each bead in `beads_skipped` with a reason string explaining why. Don't burn context trying to find implementable work that doesn't exist. Morning handoff needs to know the pool was empty, not that the drain ran out of time.
- **Early-exit and `triage_summary`.** When the drain uses the early-exit pattern (≥2 prior exhaustion logs → skip per-bead triage), there is no per-bead classification to put in `triage_summary`. In this case, `triage_summary` is NOT required — the skip reasons from the most recent log are reused. Only include `triage_summary` when the drain actually ran full per-bead triage and classified each bead.
- **Batch bead status check (avoid one-by-one).** To check whether target-scope beads exist, use a single batch query instead of calling `bd show` per ID:
  ```bash
  bd list --limit 0 2>&1 | grep -c "○"  # count open beads
  bd list --status open 2>&1 | grep -i "epic.7\|epic.8\|story.7\|story.8"  # filter by scope
  ```
  If the grep returns empty, ALL target beads are closed → `pool-exhausted`. Do NOT iterate through story files checking individual bead IDs — that burns 20+ tool calls for a yes/no answer.
- **Fixed priority list: batch-check IDs before triaging.** When the drain prompt explicitly lists bead IDs (e.g., "PRIORITY BEADS: 0mbx, qzz5, s6cp, 3h6q, dzr6, b6ct"), batch-check ALL of them with `bd show` in parallel before doing any implementation work. This takes ~3 tool calls (2 IDs per call) vs 6 sequential calls. If most are already closed or gated, you discover this in seconds, not minutes. This is distinct from the epic-scope check — that filters by label; this checks specific IDs from the prompt. If ALL listed IDs are closed/gated, exit with `pool-exhausted` immediately. If some are implementable, proceed with those. When you find a stale priority list (most items already done), report it explicitly in the drain log `issues` field so the cron prompt author knows to update the list.
- **Concrete `pool-exhausted` example:** Drain targets "Epics 7-12". After `bd list --status open`, zero beads have epic-7 through epic-12 labels. All 45 stories in those epics are closed. Exit with `"exit_reason": "pool-exhausted"`, `beads_skipped: []` (nothing to skip — scope was empty), and note in `issues`: `"All Epics 7-12 beads already closed from prior sessions"`. Do NOT use `"exit_reason": "completed"` — that implies the drain did work.
- **Concrete `pool-exhausted` with general queue fallback:** Drain prompt lists 6 specific bead IDs. First 3 are already closed (prior drain). Last 3 are all gated (need Bob's metrics confirmation or blocked on frozen dependency). However, `bd ready` shows 12 other implementable beads at P0-P2. **Correct behavior:** Fall back to `bd ready`, pick highest-priority implementable bead, work it. If you choose NOT to work the general queue (e.g., scope mismatch — drain prompt says "deprecation only" and general queue has feature work), exit with `"exit_reason": "pool-exhausted"` and explain in `issues`: "All 6 assigned beads closed/gated. General queue has 12 implementable beads but outside drain scope (feature work vs deprecation). Prompt author should update priority list." Do NOT use `"exit_reason": "completed"` — the drain did zero work.
- **`beads_skipped` supports two formats:** flat strings (`["Core-abc"]`) for simple skips, or objects (`[{"id": "Core-abc", "reason": "tracking marker for other repo"}]`) when the skip reason matters for morning triage. Prefer objects — the reason saves the next drain from re-triaging the same bead.
- **Shell heredocs produce broken JSON logs.** Using `cat > ~/.hermes/.../file.json << 'EOF'` with single-quoted `'EOF'` prevents shell variable expansion. The JSON file contains literal `$(date +%H%M%S)` instead of the actual timestamp. The morning handoff tries to parse the JSON and fails silently. **ALWAYS use `write_file` tool** for log creation — it handles `~/.hermes/` paths cleanly and doesn't have variable expansion issues. If you must use shell, use `<< EOF` (unquoted) but this risks Tirith security flags. The `write_file` tool is the only reliable approach in cron context.

## Triage Summary (Recommended for All Drains That Skip Beads)

When a drain skips multiple beads (whether `pool-exhausted` or `completed`
with many skipped), add a `triage_summary` object to the log. This gives
morning handoff (and future drains) a structured breakdown of *why* beads
were skipped, saving re-triage time. Without it, the handoff sees "23 beads
skipped" but doesn't know if they're human-dependent, cross-repo blocked,
or genuinely empty — each scenario has different next-step implications.

**When to include:**
- `pool-exhausted` drains — always (the pool was empty, explain why)
- `completed` drains that skipped beads — always (explain what's left)
- Drains with only 1-2 skips — optional (the skip reasons in `beads_skipped` are sufficient)

```json
"triage_summary": {
  "total_open_beads": 28,
  "in_progress_beads": 3,
  "p0_skipped": 5,
  "p1_human_action": 5,
  "p1_epic_marker": 2,
  "p2_cross_repo_blocked": 4,
  "p2_bob_owned_video_teaser": 8,
  "p2_dns_infra": 2,
  "p2_deferred_bob_owned": 1,
  "p2_gtm_brief_blocked": 1,
  "p2_code_implementable": 0,
  "in_progress_planning_artifact": 1,
  "in_progress_human_action": 1,
  "in_progress_parent_epic_blocked": 1
}
```

**Keys to include** (adapt to your project's bead categories):
- `total_open_beads` / `in_progress_beads` — raw counts
- `pN_<category>` — count of beads per priority + blocking reason
- `*_code_implementable` — count of beads a drain could actually build (should be 0 for pool-exhausted)
- `in_progress_*` — why in-progress beads aren't closable

**Why this matters:** Without triage_summary, the morning handoff sees
"pool-exhausted" but doesn't know if the pool is empty because (a) all beads
are done, (b) all beads need Bob's action, or (c) beads exist but are
cross-repo blocked. Each scenario has different next-step implications.

## ⚠ MANDATORY: Standard Skip Reason Categories

**Every `beads_skipped` entry MUST start with a CATEGORY prefix in CAPS.**
Without it, the morning handoff cannot aggregate skip reasons across drains.
Drains regularly forget this — the prefix is the SINGLE MOST IMPORTANT
field in the skip reason. Details follow the prefix.

When writing `beads_skipped` as objects (`[{id, reason}]`), use these
standardized categories so morning handoff can aggregate across drains:

| Category | Pattern | Example |
|----------|---------|---------|
| `HUMAN ACTION` | Requires Bob's direct action (sign, submit, recruit) | "HUMAN ACTION — Engage food-safety counsel" |
| `BLOCKED` | Formal `DEPENDS ON` blocker in bd | "BLOCKED — Blocked by Crispi-app-m3xf" |
| `GATED` | Human-imposed gate ("DO NOT execute until...") | "GATED — DO NOT execute until Bob signals metrics green" |
| `LARGE FEATURE` | Too large for one drain session, needs decomposition | "LARGE FEATURE — FR14 conversational NLP" |
| `CROSS-REPO` | Code/dependency lives in another repo | "CROSS-REPO — Depends on Core TieredLightEvaluator" |
| `FEATURE-BRANCH-ONLY` | Code exists on feature branch, not main | "FEATURE-BRANCH-ONLY — Code on vibe/qbo-capability-probe" |
| `MERGE-PENDING` | Work exists on feature branch but not merged to main (with or without close commits) | "MERGE-PENDING — 13K lines on vibe/qbo-capability-probe, branch not merged" |
| `DEFERRED` | Explicitly deferred by Bob | "DEFERRED — Marked deferred in title/labels" |
| `MISSING DESCRIPTION` | `bd show` returns empty, cannot triage | "MISSING DESCRIPTION — Cannot determine implementability" |
| `EPIC PARENT` | Parent bead whose children are blocked/open | "EPIC PARENT — Children not yet complete" |
| `ASSIGNED-LOCKED` | Assigned to human developer (@azrlb) | "ASSIGNED-LOCKED — Assigned to @azrlb, not for automated drain" |

**Format:** Prefix the reason with the category in CAPS, then a dash and details.
This makes grep-based analysis reliable: `grep -c "HUMAN ACTION" drain-logs.json`.

**⚠ MANDATORY for ALL drain logs — including overflow exhaustion.** The most
common failure is writing custom reasons like "P0 legal gate — allergist
attestation" instead of the standardized "HUMAN ACTION — P0 legal gate:
allergist attestation". Always prefix with the category. The morning handoff
greps for these categories to aggregate trends across drains.

**Concrete example — overflow exhaustion log with standardized categories:**
```json
"beads_skipped": [
  {"id": "Crispi-app-vvwx", "reason": "HUMAN ACTION — P0 legal gate: allergist attestation, blocks Crispi-app-3z2"},
  {"id": "Crispi-app-ngg", "reason": "BLOCKED — Blocked by Crispi-app-vgka"},
  {"id": "Crispi-app-56jv", "reason": "HUMAN ACTION — P1: engage food-safety counsel, human-gated legal review"},
  {"id": "Crispi-app-vu5g", "reason": "HUMAN ACTION — P1: pre-V1 validation cohort recruitment, human-gated"},
  {"id": "Crispi-app-6pqo", "reason": "LARGE FEATURE — P3: family plan multi-user (epic needing decomposition)"},
  {"id": "Crispi-app-3h6q", "reason": "ASSIGNED-LOCKED — P3: post-beta deprecation, assigned @hermes-dev-team, blocked by m3xf"},
  {"id": "Crispi-app-dzr6", "reason": "GATED — P3: post-beta deprecation, assigned @azrlb, DO NOT execute until Bob confirms"},
  {"id": "Crispi-app-b6ct", "reason": "GATED — P3: post-beta deprecation, assigned @azrlb, DO NOT execute until Bob confirms"},
  {"id": "Crispi-app-e7a7", "reason": "BLOCKED — P4: blocked on Story 07"}
]
```
**Without standardized categories**, the morning handoff can't aggregate:
`grep -c "HUMAN ACTION" drain-logs.json` returns 0, hiding that 3 of 9 beads
need Bob's direct action (the most actionable finding for the daily summary).

## Related Skills

- `dev-team/bead-execution` — Level 2 quality review procedure
- `dev-team/shared-execution` — Execution lifecycle
- `devops/drain-loop-prevention` — Prevent system freezes from concurrent drains (resource monitor, kill switch)