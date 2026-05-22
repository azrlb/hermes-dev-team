# Gold-Panning Triage — 2026-05-22

## Sources scanned

- **Pi** (`@earendil-works/pi-coding-agent`): **7 versions** published in the last 7 days (v0.74.1, v0.75.0, v0.75.1, v0.75.2, v0.75.3, v0.75.4, v0.74.2)
- **Hermes** (`NousResearch/hermes-agent`): **1 release** published in the last 7 days (v2026.5.16 / v0.14.0 — "The Foundation Release", 808 commits, 633 merged PRs)

---

## SHIP (0)

No releases this week present a clear, low-effort opportunity to unlock a customer-visible feature in Crispi, FlowInCash, or the pipeline apps. Default posture applies: "spine of the business, done right, not in a rush."

---

## RESEARCH (2)

### 1. Hermes v0.14.0 — Cross-session 1-hour Claude prompt caching

**Summary:** Hermes now caches the prompt prefix (system prompt, skills, memory) for one hour across sessions when using Claude. Background memory review also hits the cache. This means overnight crons that spin up fresh sessions pay less per turn because the cache is still warm from the previous run.

**Why it matters for Bob's apps:** The Sidecar, Crispi, and FlowInCash overnight crons all run as separate Hermes sessions. If they share a Claude provider and the cache window covers the gap between runs, the per-session cost drops. Over weeks, this compounds.

**Research question:** How much do the current overnight crons cost in Claude API tokens, and does the 1-hour cache window actually overlap between runs? The Sidecar fires at 02:00, Crispi at 04:00 — that's a 2-hour gap, which exceeds the 1-hour window. FlowInCash at 22:00 to Sidecar at 02:00 is also 4 hours. So the cache may NOT help unless crons are re-timed to run within 1 hour of each other.

**Suggested next-session scope:**
- App target: all three live apps (shared infrastructure decision)
- Investigate: actual cron run timestamps vs. cache window; whether re-timing crons to cluster within 1 hour is feasible without breaking bead-queue dependencies
- Unblocks SHIP decision: if cache overlap is confirmed and re-timing is low-effort, this becomes a cost-reduction story

---

### 2. Pi v0.75.0 — Node.js 22.19.0 minimum (breaking change)

**Summary:** Pi raised its minimum supported Node version from 20 to 22.19.0. This is a hard floor — Pi v0.75.x+ won't install or run on Node 20. The Sidecar's production container uses `node:22-slim` (per Session 6 handoff), so the Sidecar itself is fine. But the dev toolchain on Bob's workstation matters: if `pi` is invoked from a shell that's still on Node 20, future Pi upgrades will silently fail or error.

**Why it matters for Bob's apps:** If the dev workflow uses Pi as the coding agent (and it does — Pi is the subagent for overnight bead drains), then Pi staying on v0.74.x means missing all v0.75.x improvements (compaction fixes, context boundary fixes, model list updates). These improvements could affect code quality in overnight drain sessions.

**Research question:** What Node version is Bob's workstation running for Pi? If it's already ≥22.19.0, this is a non-issue and Pi can be bumped to v0.75.4 immediately. If it's Node 20, then Pi is stuck on v0.74.2 until the workstation Node is upgraded — and the v0.75.x fixes (especially compaction summary and context boundary) may be relevant to overnight drain quality.

**Suggested next-session scope:**
- App target: dev toolchain (not a specific app, but affects all apps via Pi quality)
- Investigate: `node --version` on Bob's workstation; whether Pi auto-updates or is pinned; impact of compaction/context fixes on overnight bead drain sessions
- Unblocks SHIP decision: if Node is already ≥22.19.0, this becomes a quick "bump Pi pin" story; if not, it's a "upgrade Node" prerequisite story

---

## PARK (4)

1. **Pi v0.74.1 (image generation + Together AI provider)** — Parked: Pi is a coding agent, not an app component. Its image-generation capability is for Pi's own use during development (e.g., generating diagrams in code reviews). It doesn't translate to customer-visible features in Crispi or FlowInCash. Together AI is just another provider option for Pi.

2. **Pi v0.75.1–v0.75.3 (bug fixes: config selectors, Anthropic auth, Bedrock, Bun binaries, MiMo reasoning, HTTP/2 crash)** — Parked: Incremental stabilization fixes. The MiMo reasoning_content fix is interesting (could affect AI quality in overnight drains) but is inherited from `@earendil-works/pi-ai` and doesn't require action from Bob's side.

3. **Pi v0.75.4 (supply-chain hardening) + v0.74.2 (Node 20 error message)** — Parked: Supply-chain hardening is good hygiene (shrinkwrap, lifecycle-script allowlists, smoke-tested installs) but is internal to Pi's release process. The Node 20 error message is a minor UX improvement. Neither unlocks anything for the apps.

4. **Hermes v0.14.0 (remaining features: Teams integration, computer_use cua-driver, OpenAI-compatible local proxy, security hardening, LSP diagnostics, cold-start performance, debloating, /handoff live transfer, Brave/DDG search providers, native button UI)** — Parked: All dev workflow improvements. Microsoft Teams integration is the most interesting for future apps (if a pipeline app needs Teams support), but no pipeline app has that requirement yet. The computer_use cua-driver is intriguing for automated browser testing of web UIs, but requires the Sidecar→Hermes integration path to be migrated first (currently broken/unused per Session 6). Security hardening and performance improvements are already live in the agent — no action needed.

---

## Notes

**Upstream cadence signals:**
- Pi shipped 7 versions in 7 days, including a breaking change (v0.75.0) and a rapid stabilization chain (v0.75.1–v0.75.4). This is an unusually hot week for Pi — suggests active upstream development. Worth monitoring whether this cadence continues or was a one-time burst.
- Hermes shipped one massive release (v0.14.0) with 808 commits. This is clearly a major milestone release, not a typical weekly drop. The next Hermes release may be quieter.

**Pipeline app context (from session handoffs):**
- Crispi-app: live, current focus is MealsPage Yummly redesign (bead `eq19`)
- FlowInCash-Core: live, 22:00 cron draining beads with TEA's bd-gate enforcement now live
- LivingApp-Platform: future app, 0 open issues, has CLAUDE.md orientation protocol
- LivingApp-Sidecar: shared backend, `/hermes` WebSocket route broken with zero consumers (migration deferred in Session 6). This means Hermes tool capabilities (computer_use, vision, etc.) are NOT currently exposed to any app — the integration path needs the B-path migration before Hermes features become app features.

**ADR 002 reminder:** All upstream pins are alert-only. This triage surfaces opportunities; it does not authorize pin bumps. Bob decides when and whether to act.

---

*Generated by Hermes gold-panning cron, 2026-05-22.*
