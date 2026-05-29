# Gold-Panning Triage — 2026-05-29

## Sources scanned

- **Pi** (`@earendil-works/pi-coding-agent`): 3 versions in last 7 days (v0.75.5, v0.76.0, v0.77.0)
- **Hermes** (`NousResearch/hermes-agent`): 3 releases in last 7 days (v0.15.0, v0.15.1, v0.15.2)

---

## SHIP (0)

Nothing meets the SHIP bar this week. The Hermes v0.15.0 Velocity Release is the biggest signal — but it's a 1,302-commit, 747-PR major version bump with extensive kanban internals changes. Defaulting to RESEARCH per ADR 002 discipline: "stay pinned unless the bump is incremental and the unlock is clear." A blind bump of this magnitude touches ADR 005-adjacent territory (kanban composition root, worker SIGTERM handling, Docker entrypoint). Not a Friday afternoon decision.

---

## RESEARCH (2)

### 1. Hermes v0.15.0 Kanban Multi-Agent Platform

**What it is:** Hermes's kanban subsystem grew by 104 PRs into a full multi-agent orchestration layer. Headline features: triage auto-decomposes one task into a tree of sub-tasks, `hermes kanban swarm` creates a complete swarm graph (root → parallel workers → gated verifier → gated synthesizer → shared blackboard), per-task model overrides, per-task worktree paths, scheduled start times, configurable claim TTL, retry fingerprinting, stale-task detection, and respawn guards.

**Why it matters for Bob:** The dev-team's custom kanban orchestration code (vibe-loop, kanban-orchestrator skill, kanban-worker skill) was built because upstream kanban lacked these capabilities. If v0.15.0's built-in features now cover the same ground, Bob's custom code becomes maintenance overhead instead of competitive advantage. Conversely, if the built-in features are incomplete or conflict with the custom orchestration, upgrading could break the overnight drain pipeline.

**Research question:** Does `hermes kanban swarm` + auto-decomposition replace (or conflict with) the dev-team's `kanban-orchestrator` and `kanban-worker` skills? What's the migration path? Does the per-task model override feature reduce the $5/day budget pressure by letting boilerplate workers use cheaper models?

**Suggested next-session scope:**
- App: LivingApp-Sidecar (dev-team infrastructure)
- Investigate: diff the v0.15.0 kanban API surface against the dev-team's custom orchestration code. Specifically: does auto-decomposition handle the "one bead → N sub-tasks" pattern that vibe-loop currently manages manually? Does `swarm` handle the role-boundary discipline (8/8 PASS tests)?
- What would unblock a SHIP decision: confirmation that the built-in features are a superset of the custom code, plus a tested bump on a non-production branch.

### 2. Pi v0.76.0 Explicit Session IDs for Automation

**What it is:** Pi now accepts `--session-id <id>` on the CLI, letting scripts create or resume an exact project-local session. Previously, session management was implicit — each Pi invocation either resumed the latest or created a new one, making it hard for cron jobs to target specific work contexts.

**Why it matters for Bob:** The dev-team runs overnight cron jobs that spawn Pi workers (via `pi-coding-agent`). Without explicit session IDs, each cron invocation starts a fresh session or ambiguously resumes. Session IDs would let: (a) cron jobs resume exactly where the previous night left off, (b) multiple concurrent workers target different sessions without collision, (c) debugging sessions to be replayed by ID.

**Research question:** Can the dev-team's `kanban-worker` skill be updated to pass `--session-id` when invoking Pi, and would this improve overnight drain reliability? Are there edge cases (session corruption, disk space from accumulated sessions, cross-session context bleed)?

**Suggested next-session scope:**
- App: hermes-dev-team (dev-team infrastructure)
- Investigate: test `--session-id` in a manual Pi invocation, verify session persistence across invocations, check if the dev-team's RPC-based Pi usage already handles this or if it needs a code change.
- What would unblock a SHIP decision: confirmation that session IDs survive Pi restarts and don't cause context bleed between workers.

---

## PARK (5)

1. **Pi v0.75.5** — Parked: incremental TUI improvements (cleaner read output, Windows file tools, package update reliability). Not relevant to Bob's Linux setup. The custom adaptive thinking opt-in is interesting but not a clear unlock.

2. **Pi v0.77.0 (Claude Opus 4.8, selective tool disablement, headless Codex login)** — Parked: new model support and `--exclude-tools` are nice-to-haves for worker specialization, but no concrete use case identified yet. Headless Codex subscription login is only relevant if Bob adds Codex as a provider.

3. **Hermes v0.15.1 + v0.15.2 (bug fixes)** — Parked: dashboard reload loop fix, kanban worker SIGTERM, Docker --insecure, MCP bare command resolution, plugin.yaml packaging. All will ship automatically when v0.15.0 is eventually bumped. No independent action needed.

4. **Hermes v0.15.0 Bitwarden Secrets Manager** — Parked: replaces N per-provider API keys with one bootstrap token. Elegant, but credential management isn't a pain point right now. Resurface if key rotation becomes tedious.

5. **Hermes v0.15.0 skill bundles / MCP catalog / ntfy** — Parked: skill bundles (one slash command loads a whole workflow) are a convenience feature. MCP catalog with interactive picker is nice for discovery. ntfy as the 23rd messaging platform is irrelevant (Telegram is sufficient). None are critical path.

---

## Notes

- **Unusual release cadence:** Hermes shipped 3 releases in 24 hours (v0.15.0 → v0.15.1 → v0.15.2). The v0.15.1 patch was a same-day hotfix for a dashboard infinite-reload loop that hit Docker/loopback users. This is healthy — the Velocity Release was large and the team caught regressions fast. But it means v0.15.0 is now effectively v0.15.2; any bump should target the latest patch.

- **Pi release cadence is steady:** 3 versions in 6 days, all incremental. No major architectural shifts. Pi is in a stable, well-managed phase — good for Bob's "spine of the business" posture.

- **Hermes v0.15.0 scope warning:** 1,302 commits, 747 PRs, 282K insertions. This is the largest Hermes release in the ADR 002 era. The 76% refactor of `run_agent.py` is backward-compatible by design, but the kanban internals changes are extensive. Any bump needs a full regression pass on the Sidecar's autonomous operations before touching production.

- **ADR 002 timing:** The Hermes pin is currently at a pre-v0.15.0 version. Per ADR 002's bump heuristic, the "cost-regression PR goes green 3 weeks in a row" gate hasn't been evaluated for v0.15.0 yet. The 47% fewer per-turn function calls claim is promising for the $5/day budget but needs empirical validation on Bob's actual workloads.
