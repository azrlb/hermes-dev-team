# Gold-Panning Triage — 2026-06-12

## Sources scanned

- **Pi** (`@earendil-works/pi-coding-agent`): 2 versions in last 7 days (v0.79.0, v0.79.1)
- **Hermes** (`NousResearch/hermes-agent`): 1 release in last 7 days (v0.16.0 "The Surface Release" — 874 commits, 542 merged PRs, 399 issues closed)

---

## SHIP (0)

Nothing meets the SHIP bar this week. Hermes v0.16.0 is a massive release but all customer-visible features (desktop app, web admin panel, Chinese translation) are operator-facing — they improve how Bob interacts with Hermes, not what Bob's apps do for users. The Pi releases are security hardening and developer quality-of-life. Default posture applies: "spine of the business, done right, not in a rush."

---

## RESEARCH (2)

### 1. Hermes v0.16.0 — Kanban Platform Maturity (goal_mode, terminate endpoint, file attachments)

**What changed:** v0.16.0 builds on v0.15.0's kanban multi-agent platform with three concrete improvements: (a) `goal_mode` cards that run workers in a `/goal` loop instead of one-shot dispatch, (b) file attachments on tasks so workers can see referenced files/images, and (c) a `POST /runs/{run_id}/terminate` endpoint for programmatic worker termination.

**Why this matters for Bob:** The dev-team's overnight drain pipeline (22:00/02:00/04:00 crons) currently uses custom orchestration code (vibe-loop, kanban-orchestrator, kanban-worker skills). These v0.16.0 features narrow the gap between "what Hermes kanban can do natively" and "what the custom code does today." The terminate endpoint is particularly relevant — stuck workers currently require manual intervention. File attachments could help Crispi's food recognition workers see images without custom plumbing.

**Research question:** Does v0.16.0's kanban maturity (goal_mode + terminate + file attachments) make it safe to test on a non-production branch? What's the minimal regression suite needed to validate that the overnight drain pipeline still works after upgrading Hermes from v0.13.0 to v0.16.0? The broader question — does native kanban replace the custom orchestration? — remains open and touches ADR 005 territory.

**Suggested next-session scope:**
- App: LivingApp-Sidecar (dev-team infrastructure)
- Investigate: diff the Sidecar's Hermes integration points against v0.16.0's kanban changes. Does the Docker entrypoint change affect the Sidecar's `hermes update` flow? Can the terminate endpoint be wired into the watchdog without touching the composition root?
- What would unblock a SHIP decision: confirmation that the Sidecar's test suite passes against v0.16.0, plus a 3-night soak test on a staging branch showing no regressions in overnight drain behavior.
- Carry-forward: the v0.15.0 kanban research from last week's triage is superseded by this item. The SIGTERM fix (v0.15.2) that was the focus of last week's RESEARCH is now folded into the broader v0.16.0 upgrade question.

### 2. Pi v0.79.0/v0.79.1 — Project Trust Gating for Non-Interactive Runs

**What changed:** Pi v0.79.0 introduces "project trust" — a security gate that asks before loading project-local settings, resources, instructions, and packages. v0.79.1 adds `defaultProjectTrust` to configure this globally (always trust / never trust / ask). The intent is to prevent supply-chain attacks via malicious project configs, but it has a side effect: non-interactive Pi runs (like the ones the dev-team's kanban workers subprocess) could be blocked by the trust prompt unless configured.

**Why this matters for Bob:** If Pi is upgraded to v0.79.0+ without configuring `defaultProjectTrust`, overnight Pi runs could hang waiting for a trust approval that never comes (no human present). v0.79.1's `defaultProjectTrust: "always"` is the mitigation, but it needs to be explicitly set in the Pi config used by kanban workers.

**Research question:** What Pi version are the dev-team's kanban workers currently pinned to? If it's below v0.79.0, does upgrading require a config change to `defaultProjectTrust`? What's the blast radius if a worker's Pi invocation hits the trust prompt?

**Suggested next-session scope:**
- App: LivingApp-Sidecar (dev-team infrastructure)
- Investigate: check the Pi version pinned in the Sidecar's kanban worker config. If upgrading to v0.79.1, verify that `defaultProjectTrust: "always"` can be set in the Pi config file used by workers. Confirm no behavioral change in non-interactive mode.
- What would unblock a SHIP decision: confirmation that Pi v0.79.1 with `defaultProjectTrust: "always"` produces identical output to the current Pi version for the dev-team's standard kanban worker invocations.

---

## PARK (3)

1. **Hermes v0.16.0 Desktop App** — Parked: Brand-new Electron desktop app (macOS/Linux/Windows) with in-app self-update, drag-and-drop, remote gateway connect, multi-profile sessions, Simplified Chinese translation. Operator-facing only — Bob's apps are server-side backends (Crispi, FlowInCash), not desktop apps. Could resurface if Bob ever wants a customer-facing desktop companion app.

2. **Hermes v0.16.0 Web Admin Panel** — Parked: Browser-based administration for Hermes config — channels, MCP catalog, credentials, webhooks, memory, gateway controls. Operator QoL — replaces SSH + config.yaml editing with point-and-click. Useful for Bob personally but doesn't unlock app features.

3. **Hermes v0.16.0 Leaner Skills + NVIDIA Tap** — Parked: Default skill set trimmed (spotify, linear, kanban-codex-lane removed from defaults; baoyu creative set, dspy, minecraft moved to optional). NVIDIA/skills added as trusted tap. Skills moved to optional, not deleted — one `hermes skills install` away. Low risk to existing workflows. NVIDIA tap not relevant to Bob's apps.

---

## Notes

**Upstream cadence:**
- Pi shipped 2 versions in 7 days (v0.79.0, v0.79.1). Both are incremental — security hardening (project trust) and model support (Claude Fable 5). Pi continues in a stable, well-managed phase.
- Hermes shipped 1 major release (v0.16.0 "The Surface Release") — 874 commits, 542 PRs, 399 issues closed. This is the largest release in the observed window. The desktop app was built in a single week (100 PRs, 159 commits). The release cadence suggests the Hermes team is in a high-velocity phase.

**Carry-forward from last week (2026-06-05):**
- RESEARCH: Hermes v0.15.2 Kanban SIGTERM Fix — superseded by this week's v0.16.0 kanban research item. The SIGTERM fix is now part of the broader v0.16.0 upgrade question.
- RESEARCH: Pi v0.76.0 Explicit Session IDs — still open, no new signal this week. Pi v0.79.0/v0.79.1 didn't add session ID features.

**Pipeline app status (from latest session handoff, 2026-05-17 evening):**
- Crispi-app: live, focus on MealsPage Yummly redesign (eq19)
- FlowInCash-Core: live, 22:00 cron draining beads with bd-gate enforcement
- LivingApp-Platform: future app, 0 open issues
- LivingApp-Sidecar: shared backend, `/hermes` WebSocket route broken (migration deferred)

**ADR 002 reminder:** All upstream pins are alert-only. This triage surfaces opportunities; it does not authorize pin bumps. Bob decides when and whether to act.

---

*Generated by Hermes gold-panning cron, 2026-06-12.*
