# Gold-Panning Triage — 2026-06-05

## Sources scanned

- **Pi** (`@earendil-works/pi-coding-agent`): 2 versions in last 7 days (v0.78.0, v0.78.1)
- **Hermes** (`NousResearch/hermes-agent`): 1 release in last 7 days (v0.15.2 / v2026.5.29.2 — bugfix patch on v0.15.0 "Velocity Release")

---

## SHIP (0)

Nothing meets the SHIP bar this week. All Pi releases are developer quality-of-life or provider-coverage improvements — none unlock a customer-visible feature in Crispi, FlowInCash, or the pipeline apps. The Hermes release is a bugfix patch on v0.15.0, which was already triaged as RESEARCH last week. Default posture applies: "spine of the business, done right, not in a rush."

---

## RESEARCH (1)

### 1. Hermes v0.15.2 — Kanban Worker SIGTERM Fix (continuation of v0.15.0 research)

**What changed since last triage:** Last week's gold-panning flagged Hermes v0.15.0's kanban multi-agent platform as RESEARCH — a 1,302-commit major release that could potentially replace the dev-team's custom orchestration code (vibe-loop, kanban-orchestrator, kanban-worker skills). The research question was: does `hermes kanban swarm` + auto-decomposition replace the custom code, or conflict with it?

**New signal:** v0.15.2 patches a bug where kanban workers receiving SIGTERM during overnight drains would not exit cleanly. This was a known reliability concern for the 22:00 / 02:00 / 04:00 cron crons that power Crispi's and FlowInCash's overnight bead processing. The fix means workers now terminate gracefully, reducing the risk of zombie processes and partial bead closures.

**Why this matters for Bob:** The SIGTERM fix removes one blocker from the v0.15.0 upgrade path. Last week's RESEARCH item noted that the v0.15.0 bump "touches ADR 005-adjacent territory (kanban composition root, worker SIGTERM handling, Docker entrypoint)." The worker SIGTERM handling is now patched. The composition root and Docker entrypoint questions remain.

**Research question (updated):** With the SIGTERM fix in place, does the v0.15.2 patch make it safe enough to test on a non-production branch? What's the minimal regression suite needed to validate that the overnight drain pipeline still works after upgrading Hermes from v0.13.0 to v0.15.2?

**Suggested next-session scope:**
- App: LivingApp-Sidecar (dev-team infrastructure)
- Investigate: diff the Sidecar's Hermes integration points against v0.15.2's changes. Specifically: does the Docker entrypoint change affect the Sidecar's `hermes update` flow? Does the kanban worker SIGTERM fix resolve the actual failure mode observed in overnight drains, or is there a different root cause?
- What would unblocks a SHIP decision: confirmation that the Sidecar's test suite passes against v0.15.2, plus a 3-night soak test on a staging branch showing no regressions in overnight drain behavior.
- Carry-forward: the broader kanban swarm vs custom orchestration question from last week is still open. This week's patch narrows the risk surface but doesn't resolve the architectural question.

---

## PARK (2)

1. **Pi v0.78.0 (named sessions, clickable file paths)** — Parked: `--name` lets you label Pi sessions at startup (e.g., "Crispi-drain-0400"), and file paths in tool output are now clickable hyperlinks. Both are developer convenience features. They improve the dev workflow but don't translate to customer-visible features in any app. No action needed.

2. **Pi v0.78.1 (provider coverage, extension context, security fixes)** — Parked: Adds Ant Ling, NVIDIA NIM, and MiniMax-M3 as built-in providers — none of which Bob uses. The `ctx.mode` and `ctx.getSystemPromptOptions()` extension APIs are forward-looking (extensions can adapt to TUI/RPC/JSON/print mode) but no Pi extensions are in the pipeline. Security fixes (XSS in HTML exports, unsafe git paths, temp extension permissions) are good hygiene but don't unlock features. The large JSONL session memory fix is a bugfix that affects session handling at scale — relevant only if sessions grow very large.

---

## Notes

**Upstream cadence:**
- Pi shipped 2 versions in 7 days (v0.78.0, v0.78.1). Both are incremental — no architectural shifts. Pi is in a stable, well-managed phase. The rapid v0.78.0 → v0.78.1 cycle (6 days) suggests active maintenance but not a feature burst.
- Hermes shipped 1 patch release (v0.15.2) on top of the v0.15.0 Velocity Release from last week. This is a healthy patch cadence — the team caught the SIGTERM regression fast. v0.15.0 → v0.15.2 in 1 day is good sign.

**Carry-forward from last week (2026-05-29):**
- RESEARCH: Hermes v0.15.0 Kanban Multi-Agent Platform — still open. v0.15.2 narrows the risk surface but doesn't resolve the architectural question.
- RESEARCH: Pi v0.76.0 Explicit Session IDs — still open. Pi v0.78.0 added `--name` (display names) but the `--session-id` feature from v0.76.0 is still the more impactful one for automation. No new signal this week.

**Pipeline app status (from latest session handoff, 2026-05-17 evening):**
- Crispi-app: live, focus on MealsPage Yummly redesign (eq19)
- FlowInCash-Core: live, 22:00 cron draining beads with bd-gate enforcement
- LivingApp-Platform: future app, 0 open issues
- LivingApp-Sidecar: shared backend, `/hermes` WebSocket route broken (migration deferred)

**ADR 002 reminder:** All upstream pins are alert-only. This triage surfaces opportunities; it does not authorize pin bumps. Bob decides when and whether to act.

---

*Generated by Hermes gold-panning cron, 2026-06-05.*
