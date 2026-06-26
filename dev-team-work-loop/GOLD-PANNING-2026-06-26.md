# Gold-Panning Triage — 2026-06-26

## Sources scanned

- **Pi** (`@earendil-works/pi-coding-agent`): 5 versions in last 7 days (v0.79.8, v0.79.9, v0.79.10, v0.80.1, v0.80.2)
- **Hermes** (`NousResearch/hermes-agent`): 1 release in last 7 days (v2026.6.19 "The Reach Release" — Jun 19)

---

## SHIP (1)

### 1. Hermes v2026.6.19 — Background Subagents for Overnight Drain Parallelism

**What changed:** `delegate_task(background=true)` now dispatches subagents that run in the background and return a handle immediately. The full result re-enters the conversation when it finishes. This is a first-class capability, not a workaround.

**Why this matters for Bob:** The dev-team's overnight drain pipeline (Sidecar 02:00, Crispi 04:00, FIC-Core 22:00) currently processes beads sequentially — one bead, one conversation. Background subagents unlock parallel bead processing: the drain agent could dispatch 2–3 bead workers simultaneously, each running in its own subagent, while it continues monitoring. This could cut overnight drain wall-clock time significantly and get Bob's apps updated faster each morning.

**Story stub:**
- **Problem:** Overnight drain pipelines process beads one at a time. A 3-bead batch takes 3× the wall-clock time. Bob wakes up to partial progress on multi-bead nights.
- **Proposed approach:** Update the Sidecar/Crispi/FIC-Core cron drain prompts to dispatch beads via `delegate_task(background=true)` when ≥2 ready beads exist. The drain agent monitors completion and writes structured bead notes on each subagent's result.
- **App target:** LivingApp-Sidecar (shared infra) — affects all three overnight drain pipelines
- **Estimated effort:** medium (prompt engineering + testing across 3 cron jobs + verification that background subagents work reliably in cron context)
- **ADR 002 gate impact:** needs verification — background subagents are a Hermes runtime feature; confirm they work in the cron/s6 container context before committing. No Pin bump needed (Hermes is already pinned to a post-v0.17.0 version in the container).

---

## RESEARCH (3)

### 1. Hermes v0.17.0 — Automation Blueprints for Non-Technical Scheduling

**What changed:** Automation Blueprints let you pick an automation by name and Hermes asks questions to configure it — no cron syntax needed. One definition renders across all surfaces (dashboard form, slash command, conversation, docs).

**Why this matters for Bob:** Bob is non-technical and currently relies on cron job prompts with precise scheduling syntax. Automation Blueprints could let him set up new recurring workflows by just describing what he wants ("check Crispi health every morning at 8am") instead of crafting cron expressions.

**Research question:** Can Automation Blueprints replace the hand-crafted cron prompts for the overnight drain pipelines, or are they too high-level for the multi-step bead-processing logic the drains require?

**Suggested next-session scope:**
- App: Hermes agent (infrastructure)
- Investigate: Read the Automation Blueprints docs. Test whether a blueprint can encode the drain pipeline's multi-step logic (pull ready beads → dispatch work → write notes → close) or whether it's limited to simple schedule-then-execute patterns.
- What would unblock a SHIP decision: If blueprints support parameterized multi-step flows, they could simplify cron job management. If they're just "run this prompt on a schedule," they add no value over the existing cron setup.

### 2. Hermes v0.17.0 — Curator Cost Optimization (Zero-Token Routine Curation)

**What changed:** The skill curator no longer runs its LLM-powered consolidation pass by default. Deterministic inactivity pruning still runs for free; the aux-model-spending "build umbrella skills" fork is now opt-in (`curator.consolidate: true`).

**Why this matters for Bob:** The dev-team's hermes-dev-team profile runs skill curation as part of its overnight operations. If the consolidation pass was consuming aux-model tokens on routine runs, this change immediately reduces operational cost with zero behavioral regression.

**Research question:** Is the hermes-dev-team profile's curator currently running the consolidation pass? If so, what's the token cost per run, and does disabling it affect skill quality for Bob's dev-team skills?

**Suggested next-session scope:**
- App: Hermes agent (infrastructure)
- Investigate: Check the hermes-dev-team profile's `config.yaml` for `curator.consolidate` setting. Review recent curator run logs for token consumption. Assess whether any dev-team skills were consolidated by the LLM pass that would be lost without it.
- What would unblock a SHIP decision: Confirmation that consolidation is either (a) already off (no action needed) or (b) running and consuming significant tokens with minimal value (disable it).

### 3. Pi v0.79.8–v0.79.10 — Provider Infrastructure & Extension Compaction Context

**What changed across 3 releases:**
- **v0.79.8:** Selective provider base entry points (lighter Pi bundles), Mistral prompt caching (cost savings), post-compaction token estimates (better context visibility).
- **v0.79.9:** Chat-template thinking compatibility for vLLM/HF models (DeepSeek behind local inference), GLM-5.2 provider improvements.
- **v0.79.10:** Extension compaction events now include `reason` and `willRetry` metadata, letting extensions distinguish manual vs. auto compaction. Safer update flow.

**Why this matters for Bob:** The post-compaction token estimates (v0.79.8) could improve the dev-team's overnight drain pipeline visibility — the drain agent would know exactly how much context it recovered after compaction. The extension compaction context (v0.79.10) could enable smarter compaction strategies if Pi extensions are used for custom summarization. The selective entry points could reduce Sidecar's bundle size if it only imports needed providers.

**Research question:** Does LivingApp-Sidecar currently import full `pi-ai`/`pi-agent-core` packages (making selective entry points relevant)? Does the Sidecar use compaction events (making the v0.79.10 metadata useful)?

**Suggested next-session scope:**
- App: LivingApp-Sidecar (shared dependency)
- Investigate: Review Sidecar's imports — does it use `@earendil-works/pi-ai` root or selective imports? Check if Sidecar registers any Pi extension event handlers for compaction. Assess whether post-compaction token estimates would improve the drain pipeline's context management decisions.
- What would unblock a SHIP decision: If Sidecar uses full pi-ai imports AND bundle size is a measured pain point, selective entry points could reduce cold-start time. Otherwise these are incremental improvements with no customer-visible impact.

---

## PARK (4)

1. **Pi v0.79.8 — Mistral Prompt Caching + OpenRouter Fusion** — Parked: Cost optimization for Mistral provider and a new OpenRouter model alias. Bob's apps don't currently use Mistral or OpenRouter Fusion. If provider landscape shifts, this resurfaces.

2. **Pi v0.79.9 — Chat-Template Thinking Compatibility** — Parked: Enables vLLM/Hugging Face chat-template models (e.g., DeepSeek behind local inference) to use provider-native thinking controls. Relevant only if Bob's apps move to self-hosted model inference — not currently planned.

3. **Pi v0.80.1 — Bedrock/Fireworks/Together Provider Fixes** — Parked: Scoped AWS_PROFILE for Bedrock, session-affinity fixes for Fireworks, MiniMax M2.7 metadata fix. None of these providers are used by Bob's apps (all run on Hermes-managed providers).

4. **Pi v0.80.2 — ApiKeyCredential Type Rename + Anthropic Compat** — Parked: Internal credential format standardization and custom model compatibility fixes. These are SDK-level changes that improve Pi's internal consistency but don't affect Bob's apps' behavior or capabilities.

---

## Notes

**Upstream cadence:**
- Pi shipped 5 versions in 7 days (v0.79.8 → v0.80.2). The jump from v0.79.x to v0.80.x (Jun 23) signals a minor version milestone — the main change is the pi-ai API surface reorganization (old global API moved to `/compat`). The v0.80.1 and v0.80.2 are immediate patch releases fixing regressions from the v0.80.0 API move. Pi remains in active provider-infrastructure development mode.
- Hermes shipped 1 release (v2026.6.19 "The Reach Release") — a major release with 1,475 commits, 800+ PRs, 245 contributors. This is the biggest Hermes release since v0.16.0. The background subagents feature alone is the most significant capability addition for Bob's overnight pipeline since the original drain architecture.

**Carry-forward from 2026-06-19:**
- RESEARCH: Hermes v0.16.0 Kanban Platform Maturity (goal_mode, terminate, file attachments) — still open, no new Hermes signal since v0.17.0 didn't add kanban-specific changes. The native kanban platform question remains relevant but unaddressed. Carry forward.
- PARK: Hermes Desktop App, Web Admin Panel, Leaner Skills + NVIDIA Tap — still parked, no change. The v0.17.0 desktop improvements (watch-windows, themes, shortcuts) are impressive but don't affect Bob's server-side apps.

**Pipeline app status (from latest session handoff, 2026-05-17 evening):**
- Crispi-app: live, focus on MealsPage Yummly redesign (eq19)
- FlowInCash-Core: live, 22:00 cron draining beads with bd-gate enforcement
- LivingApp-Platform: future app, 0 open issues
- LivingApp-Sidecar: shared backend, `/hermes` WebSocket route broken (migration deferred)

**ADR 002 reminder:** All upstream pins are alert-only. This triage surfaces opportunities; it does not authorize pin bumps. Bob decides when and whether to act.

---

*Generated by Hermes gold-panning cron, 2026-06-26.*
