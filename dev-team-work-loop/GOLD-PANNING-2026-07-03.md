# Gold-Panning Triage — 2026-07-03

## Sources scanned

- **Pi** (`@earendil-works/pi-coding-agent`): 1 version in last 7 days (v0.80.3)
- **Hermes** (`NousResearch/hermes-agent`): 1 release in last 7 days (v2026.7.1 "The Judgment Release" — Jul 1)

---

## SHIP (2)

### 1. Hermes v0.18.0 — Goal Completion Contracts for Pipeline Verification

**What changed:** `/goal` gained completion contracts — you state what "done" looks like, and the standing-goal loop judges completion against evidence (test results, lint exit codes) instead of the model asserting success. A `pre_verify` hook lets you wire in custom checks.

**Why this matters for Bob:** The dev-team's overnight drain pipelines (Sidecar 02:00, Crispi 04:00, FIC-Core 22:00) currently close beads when the agent *thinks* it's done. Completion contracts replace "I think I fixed it" with "the tests pass, here's proof." This directly strengthens the bd-gate enforcement TEA already landed (commit `5dca98c`) — the agent can now declare its own verification criteria instead of relying solely on the hook. Reduces the chance of beads closing on broken code.

**Story stub:**
- **Problem:** Overnight drain agents sometimes close beads when their tests pass locally but the commit breaks something else — the agent declares success without proof.
- **Proposed approach:** Update drain cron prompts to use `/goal` completion contracts — each bead worker declares verification criteria ("vitest passes, eslint clean, no regressions in touched files") and the goal loop judges against evidence before allowing close.
- **App target:** LivingApp-Sidecar (shared infra) — affects all three overnight drain pipelines
- **Estimated effort:** small (prompt engineering to add completion contract declarations to existing drain prompts; no code changes needed)
- **ADR 002 gate impact:** none — this is a Hermes runtime feature, not a dependency pin bump. The drain prompts already run against the current Hermes version.

### 2. Hermes v0.18.0 — Kanban Task Lifecycle Hooks + Block Reason Types

**What changed:** Kanban plugin now fires hooks on task claimed/completed/blocked transitions. Block reasons are typed (not free-text). Handoff freshness stamping tracks when a task was last touched.

**Why this matters for Bob:** The dev-team's bead-based workflow currently uses `bd update --append-notes` for status tracking (the Session-Start Orientation Protocol from May 17). Task lifecycle hooks could replace manual note-writing with automatic state transitions — when an agent claims a bead, the hook fires; when it completes, the hook fires. Typed block reasons would make the overnight drain's blocker detection more reliable (no more parsing free-text notes to figure out why a bead is stuck).

**Story stub:**
- **Problem:** Bead status tracking relies on agents manually writing notes. If an agent crashes mid-work, the bead stays in limbo — no "blocked" or "in-progress" signal unless the next agent reads the notes.
- **Proposed approach:** Wire the kanban lifecycle hooks into the drain pipeline so bead state transitions are automatic and typed. Use block reasons to categorize failures (test failure, dependency issue, upstream regression) instead of free-text notes.
- **App target:** LivingApp-Sidecar (shared infra) — affects all three overnight drain pipelines
- **Estimated effort:** medium (requires understanding how kanban hooks integrate with the existing bd-gate system; may need a bridge layer between kanban events and beads state)
- **ADR 002 gate impact:** none — Hermes runtime feature, no dependency change.

---

## RESEARCH (2)

### 1. Hermes v0.18.0 — Mixture-of-Agents as First-Class Model

**What changed:** MoA ensembles (named groups of models that deliberate together) are now selectable as a model in every picker — CLI, TUI, desktop, gateway. Each reference model's reasoning is shown, and the aggregator's answer streams live.

**Why this matters for Bob:** MoA could improve the quality of overnight drain agent decisions — instead of relying on a single model's judgment to decide whether a bead is truly done, a MoA ensemble could cross-check. But this raises cost and latency questions. The dev-team's pipeline runs on constrained budgets.

**Research question:** Can MoA be configured per-session (e.g., only for the verification step, not the entire drain)? What's the cost multiplier vs. single-model? Would the quality improvement justify the 2-3× token cost for overnight drain work?

**Suggested next-session scope:**
- App: Hermes agent (infrastructure)
- Investigate: Check if MoA ensembles can be scoped to specific pipeline steps (e.g., verification only). Review the MoA cost model — does it count all reference model tokens? Test with a small bead to measure quality delta and cost.
- What would unblock a SHIP decision: If MoA can be applied selectively to verification steps at reasonable cost, it could become the "second opinion" before bead close. If it's all-or-nothing with 3× cost, it stays parked.

### 2. Pi v0.80.3 — Claude Sonnet 5 Support + RPC Session Tree Access

**What changed:** Pi now supports Claude Sonnet 5 through Anthropic-compatible and Bedrock provider catalogs with adaptive thinking. RPC clients can also inspect session entries and tree snapshots via `get_entries` and `get_tree`.

**Why this matters for Bob:** Claude Sonnet 5 is a new model tier — potentially faster/cheaper than current models for routine drain work. The RPC session tree access could improve observability into Sidecar's in-process Pi sessions (the Sidecar runs Pi as an imported Node module per ADR 005). But the Sidecar may not currently use Pi's RPC interface.

**Research question:** Does LivingApp-Sidecar's Pi integration use the RPC interface (making `get_entries`/`get_tree` relevant for observability)? Is Claude Sonnet 5 available through the Hermes provider catalog (making the Pi-level support redundant for Bob's apps)?

**Suggested next-session scope:**
- App: LivingApp-Sidecar (shared dependency)
- Investigate: Check Sidecar's Pi integration — does it use RPC mode or direct SDK calls? Check if Hermes already supports Claude Sonnet 5 through its own provider system (making Pi's support redundant). Assess whether Sonnet 5's speed/cost profile would benefit the drain pipeline's routine tasks.
- What would unblock a SHIP decision: If Sidecar uses Pi RPC (unlikely — it's likely SDK-level), the session tree access enables real-time drain monitoring. If Hermes already supports Sonnet 5, Pi's support is moot. If neither, this is a future dependency consideration.

---

## PARK (3)

1. **Hermes v0.18.0 — Background Fan-Out (Consolidated Return)** — Parked: This was already triaged as SHIP in the June 26 gold-panning (Hermes v2026.6.19). The v0.18.0 version refines it with consolidated returns and status bar tracking. The original SHIP story stub still applies; no new action needed beyond verifying the June 26 story is still valid.

2. **Hermes v0.18.0 — Scale-to-Zero + Drain Coordination** — Parked: Gateway-level production hardening (dormancy detection, safe-shutdown coordination). Relevant if Bob's Hermes instance runs on Railway and needs scale-to-zero, but the current Sidecar v2 architecture runs Hermes as a standalone Python service — scale-to-zero is an infrastructure decision, not an app feature. Resurface if Bob moves to a hosted Hermes model.

3. **Pi v0.80.3 — Configurable Output Spacing / External Editor / Azure Foundry** — Parked: UI and provider ergonomics for Pi's CLI interface. Bob's apps consume Pi as an SDK module, not a CLI tool. These features don't affect Sidecar's runtime behavior.

---

## Notes

**Upstream cadence:**
- Pi shipped 1 version in 7 days (v0.80.3). Quiet week after the v0.80.0 API reorganization (Jun 23) and patch releases (v0.80.1, v0.80.2). v0.80.3 is a features-and-fixes release. Pi remains in active development but the pace is more measured than the v0.79.x burst.
- Hermes shipped 1 release (v2026.7.1 "The Judgment Release") — a massive release with ~1,720 commits, 998 merged PRs, 949 issues closed. The P0/P1 clean sweep (100% resolved) is the headline. This is the most feature-rich Hermes release since v0.16.0.

**Carry-forward from 2026-06-26:**
- RESEARCH: Hermes v0.17.0 Automation Blueprints for Non-Technical Scheduling — still open. No new signal in v0.18.0 (blueprints not mentioned in release notes). Carry forward.
- RESEARCH: Hermes v0.17.0 Curator Cost Optimization — still open. v0.18.0 mentions "cheaper background review" which may partially address this. Carry forward with note to investigate overlap.
- RESEARCH: Pi v0.79.8–v0.79.10 Provider Infrastructure — still open. v0.80.3 doesn't add new provider infrastructure changes. Carry forward.
- PARK: Hermes Desktop App, Web Admin Panel — still parked, no change. Desktop improvements in v0.18.0 (projects, memory graph, `/journey`) are impressive but don't affect Bob's server-side apps.

**Pipeline app status (from latest session handoff, 2026-05-17 evening):**
- Crispi-app: live, focus on MealsPage Yummly redesign (eq19)
- FlowInCash-Core: live, 22:00 cron draining beads with bd-gate enforcement
- LivingApp-Platform: future app, 0 open issues
- LivingApp-Sidecar: shared backend, `/hermes` WebSocket route broken (migration deferred)

**ADR 002 reminder:** All upstream pins are alert-only. This triage surfaces opportunities; it does not authorize pin bumps. Bob decides when and whether to act.

---

*Generated by Hermes gold-panning cron, 2026-07-03.*
