# Session Handoff — 2026-05-16

## TL;DR

**Session 4 done + the entire auto-update strategy locked in and live.** Three production-grade outcomes: (1) Sidecar v2 Session 4 (`hermes-client.ts` + `env.ts` + 26 tests, zero regressions); (2) the 5 open questions from the auto-update strategy doc resolved via BMAD party-mode and shipped as actual code/config; (3) the previously-disconnected `hermes-dev-team/cron/jobs.json` is now *actually* wired to live Hermes via a new `scripts/sync-cron-jobs.py` called from `install.sh`. Real cron run produced clean digest with all 4 surfaces PIN_OK.

One PR awaits Bob's merge (Sidecar #1, vitest devDep bump). One Railway env var needs Bob's dashboard eyeball to verify (HERMES_API_KEY storage form). Otherwise: session ready to wrap.

## What landed in code

### `LivingApp-Sidecar` — branch `main`, ALL pushed

| SHA | Subject |
|---|---|
| `715f0f5` | feat(hermes-client): add HTTPS client + boot-time env validation (Session 4) |
| `45ea559` | chore(deps): pin @earendil-works/pi-coding-agent to exact 0.74.0 + ADR 002 dev-tier addendum |

Plus PR #1 (branch `chore/bump-vitest-4`, awaiting review):
| SHA | Subject |
|---|---|
| `9d449d6` | chore(deps): bump vitest 3.2 → 4.1.5 to clear devDep CVEs |

Files:
- `src/hermes-client.ts` (~310 lines) — Bearer API_SERVER_KEY auth (no JWT mint, no 401-retry, no protocol-version/idempotency headers — third-party LLM server, not a peer service). Circuit breaker, AuditEmitter, generic post/get + health() helper. 60s default timeout. x-request-id forwarded for sidecar log correlation.
- `src/env.ts` — zod `validateEnv()` (Murat's Condition 2). Required vars: PORT, PLATFORM_GATEWAY_BASE_URL, JWT_PRIVATE_KEY_ACTIVE, HERMES_BASE_URL, HERMES_API_KEY. Aggregates ALL failures, prints `[env] FAIL: <var> <reason>` lines mirroring Hermes preflight.py.
- `tests/new/hermes-client.test.ts` — 17 unit tests covering happy path, auth errors, 4xx healthy, circuit breaker (5xx + network + timeout + HALF_OPEN single-flight + recovery + re-trip), config errors, invalid JSON, defaults.
- `tests/new/env.test.ts` — 9 unit tests (happy path + missing vars + length-validated secrets + URL form + PORT range).
- `package.json` — `@earendil-works/pi-coding-agent` flipped from `^0.74.0` to exact `0.74.0`.
- `docs/adr/002-upstream-keep-current-strategy.md` — appended `## Addendum: Dev-tier exception` codifying the surface-1+2 carve-out (track latest as feature, not exception). Cites cron `770cfee9f064` as enforcement; includes rollback story for dev-tier breakage; cites memory file references.
- `pi-client.ts` + `pi-client-v2.ts` — AuditKind union extended with `hermes.circuit_open` / `hermes.circuit_half_open` / `hermes.circuit_closed`.

Both files ship **unwired**. Session 5 cutover wires `validateEnv()` + `hermes-client` into `watchdog.ts` `main()` alongside `nous-supervisor` deletion.

Tests: 323 pass / 4 skip / 2 todo on the suite, zero regressions across all changes.

### `hermes-dev-team` — branch `dev`, ALL pushed

| SHA | Subject |
|---|---|
| `872a8f2` | feat(cron): D9 — extend auto-update-pi-hermes to 4 surfaces + opportunity digest |
| `1b3d0e8` | feat(cron): add friday-gold-panning routine — weekly opportunity triage |
| (next commit) | feat(scripts): sync-cron-jobs.py — merge repo cron defs into ~/.hermes (Issue 1) + cron prompt fixes (Issues 2, 3) |

Files:
- `cron/jobs.json` — D9 prompt rewrite of job `770cfee9f064` (10,611 chars):
  - MAINTENANCE section: surfaces 1+2 unchanged auto-bump; surfaces 3+4 NEW alert-only with ADR 002 gate enum (`PIN_OK` / `STALE_BUMP_DUE` / `CVE_FAST_TRACK` / `DEPRECATED_PIN`).
  - Surface 3 dual-source CVE (GHSA + npm audit; captures `cve_source`).
  - Surface 4 CVE via `gh api repos/NousResearch/hermes-agent/security-advisories` (corrected from initial wrong endpoint).
  - OPPORTUNITY section: pulls last 7 days of npm + GitHub releases, LLM-summarizes, tags each `Unlocks: <yes|no|needs-deeper-look>`.
  - REPORT section: 🛠 MAINTENANCE + 🚀 OPPORTUNITY blocks, prefix-precedence rule with explicit "compute LAST" guidance (corrected from initial bug).
- `cron/jobs.json` also adds new job `d8149b81e971` (friday-gold-panning, schedule `0 10 * * 5`):
  - Re-pulls upstream releases independently of the Sunday digest, triages into SHIP/RESEARCH/PARK against Bob's apps.
  - Writes full triage to `dev-team-work-loop/GOLD-PANNING-<DATE>.md` and commits to dev branch (no push — Bob does that).
  - Telegram summary with bucket counts + handoff filename.
  - Constraints: never edits prod code, never auto-bumps pins, research+triage only.
- `scripts/sync-cron-jobs.py` — NEW (~190 lines). Merges repo's `cron/jobs.json` into `~/.hermes/cron/jobs.json`. Preserves runtime fields (last_run_at, last_status, etc.) and live-only jobs. Idempotent. Backups before write. Called from `install.sh`.
- `install.sh` — extended with `Cron jobs:` section that invokes `scripts/sync-cron-jobs.py`.
- `dev-team-work-loop/SESSION-HANDOFF-2026-05-16.md` — this file.

### `~/.hermes/cron/jobs.json` — REAL prod cron store, now in sync

5 active jobs as of session end:
| ID | Name | Schedule | Source |
|---|---|---|---|
| `8f6267bb7447` | Morning AI News & Tool Discovery | `0 8 * * *` | Live-only (Bob added) |
| `8595f1a42166` | Morning Priority Check-In | `30 7 * * *` | Live-only (Bob added) |
| `770cfee9f064` | auto-update-pi-hermes | `0 3 * * 0` | **Repo** (synced via install.sh) |
| `d8149b81e971` | friday-gold-panning | `0 10 * * 5` | **Repo** (synced via install.sh) |
| `8194bfcabc06` | remind-bob-support-inboxes | `0 9 25 3 *` | **Repo** (synced via install.sh — 1-shot 2027-03-25, may be stale) |

Backup at `~/.hermes/cron/jobs.json.bak-20260510_161851` (and another from when I first manually merged: `.bak-2026-05-16`).

## Architectural decisions worth knowing

### The 5 OQs from `AUTO-UPDATE-UNIFIED-STRATEGY-2026-05-10.md` — RESOLVED

Method: BMAD party-mode round (Winston / Amelia / Murat / John). Bob's framing: "spine of the business — 4 apps depending on it. Stable, done right, not in a rush."

| OQ | Vote | Decision |
|---|---|---|
| #1 — Dev-tier carve-out from ADR 002 | 4-0 Addendum | Codified as "Addendum: Dev-tier exception" in ADR 002. Dev-tier track-latest is a *feature* of the pinning strategy (early-warning canary), not an exception. |
| #2 — Sidecar npm pin format | 3-1 Exact | `^0.74.0` → exact `0.74.0`. Production version changes are deliberate, reviewed events. Caret + lockfile is operationally fragile; exact-pin makes every bump a PR-visible event. |
| #3 — Bridge-period staleness ownership | Synthesized: handoff loop | Cron alerts → next dev-team session via SESSION-HANDOFF. Don't build doomed automation Pulse will replace. (Murat dissented preferring auto-PR-opener — overridden because it assumes Bob would maintain throwaway code; AI team will instead.) |
| #4 — CVE detection source | Synthesized: dual-source | GHSA + npm audit for surface 3. Defense-in-depth wins for the spine. Surface 4 uses `gh api repos/.../security-advisories` (the correct endpoint for git-tag CVEs). |
| #5 — Cron retirement when Pulse ships | Synthesized: belt-and-suspenders | Run cron + Pulse in parallel for 1 month after Pulse ships, then disable cron. Pulse is brand-new code; trust must be earned. (Winston/Amelia dissented preferring atomic cutover — overridden because we have evidence "perfect on day one" is not how things ship here.) |

The override pattern matters: per Bob's clarification mid-session, the AI team OWNS technical recommendations rather than asking Bob to pick between options. This is now codified in `~/.claude/projects/.../memory/feedback_decide_for_bob.md`.

### Bob is non-technical — collaboration model codified

Mid-session Bob clarified: "I am a solo creator whos dev team is bmad method. hermes dev-team and claude. I have no knowledge of software, code structure so i need my ai team to frame all those decisions and guide me to what is best."

Two new memory files:
- `user_solo_creator_no_code.md` — Bob is product owner / direction-setter, not engineering manager. Frame in business/risk terms (blast radius, customer impact, time-to-recover), not technical tradeoffs.
- `feedback_decide_for_bob.md` — Default mode: AI team owns recommendations. Reserve `AskUserQuestion` for genuine product-level questions ("should this app feature X or Y?"), not technical option-picking.

This changes how I should work going forward. Three rounds of `AskUserQuestion` mid-session produced no answers — they were the wrong unit of question.

### Cutting-edge as market differentiator — opportunity layer added

Bob asked: "how do we keep track of hermes and pi updates as they are coming out 1/week and adding more functionality rapidly. I want to be able to stay on the cutting edge as a market differentiator."

The auto-update doc was defensive (don't get bitten by drift). The reframing added an offensive layer:

| Layer | Function | How shipped |
|---|---|---|
| Awareness | "What's new in each release? What could it unlock?" | D9 OPPORTUNITY section in cron `770cfee9f064` |
| Experimentation | Try the new thing safely on dev box | Dev-tier carve-out (already-existing; codified in ADR 002 addendum) |
| Adoption | Triage opportunities into ship/park/research | NEW cron `d8149b81e971` (friday-gold-panning) |

Roadmap-integration layer (turning "ship this" into actual story creation) is parked. The next BMAD story-creation session will pick up SHIP items from gold-panning's handoff file.

### Repo ↔ prod cron divergence — discovered + fixed

Mid-session discovery: `hermes-dev-team/cron/jobs.json` was a dead file. Hermes reads `~/.hermes/cron/jobs.json` exclusively, which contained only the 2 morning briefings. Job `770cfee9f064` (auto-update-pi-hermes) had been "in the repo" for ~6 weeks across multiple D-series commits (D0, D1, D6, D9) but had NEVER been wired to the live scheduler. Same for the friday-gold-panning add I made earlier in this session.

Root cause: `install.sh` only symlinked `pi/` and `hermes/plugins/`; nothing touched cron/jobs.json.

Fix: `scripts/sync-cron-jobs.py` performs a structural merge:
- Repo "spec" fields (prompt, schedule, enabled, model, etc.) overwrite live values for matching ids
- Live "runtime" fields (last_run_at, state, etc.) are PRESERVED — repo never clobbers scheduler state
- Live-only jobs (Morning AI News, Morning Priority Check-In) preserved as-is
- Idempotent — re-runs with no changes are no-ops
- Backups live file before write

Why a sync script and not a symlink: Hermes re-writes `~/.hermes/cron/jobs.json` on every tick to update runtime fields. A symlink would push those updates into the git-tracked repo file, producing constant noisy commits and mixing scheduler state with version control.

`install.sh` now invokes the sync after the symlink calls. Documented memory: `reference_local_cron_runner.md` (already exists, covers `hermes cron` CLI).

### Live cron run successful — validates the whole pipeline

Manually triggered `hermes cron run 770cfee9f064 && hermes cron tick`. Output landed at `~/.hermes/cron/output/770cfee9f064/2026-05-10_16-12-27.md`. Real Telegram digest delivered to Bob.

Observed behavior:
- All 4 surfaces report PIN_OK. No CVE, no stale, no deprecated.
- Hermes (dev) was 27 commits behind upstream — auto-bumped via `hermes update` (dev-tier policy worked).
- Pi was already at 0.74.0 (matches our pin).
- OPPORTUNITY section found 3 Pi releases + 1 Hermes release in last 7 days, 3 tagged `Unlocks: yes`:
  - Pi 0.73.0 — incremental bash output streaming → could give Crispi real-time progress UI
  - Pi 0.73.1 — interactive OAuth login selection → could simplify FlowInCash OAuth
  - Hermes v2026.5.7 "Tenacity" — durable kanban with heartbeat/reclaim → exactly what dev-team work-loop needs
- Friday gold-panning tail-tag appeared correctly.

Two prompt issues observed in the live run, both fixed in this session:
1. Agent emitted `🚨 MANUAL INTERVENTION NEEDED` prefix optimistically, then noted it should be removed. Fix: prompt now explicitly says "compute the prefix LAST after every section finishes."
2. Surface 4 CVE check used wrong endpoint (`SecurityAdvisoryEcosystem` GraphQL has no `GITHUB` value). Fix: switched to `gh api repos/NousResearch/hermes-agent/security-advisories`.

Both fixes propagated to BOTH the repo and the live `~/.hermes/cron/jobs.json`. Next Sunday 03:00 run will use the corrected prompt.

## Things to know about the Railway state

- **`livingapp-sidecar` Railway service now has 2 NEW env vars:**
  - `HERMES_BASE_URL=http://livingapp-hermes.railway.internal:8642` (literal — verified)
  - `HERMES_API_KEY=${{livingapp-hermes.API_SERVER_KEY}}` (intended as cross-service reference; **see action item below**)
- These were set via `railway variables --set ... --skip-deploys` (no immediate redeploy). Will take effect on next Sidecar deploy.
- Both required by `src/env.ts` `validateEnv()` once Session 5 wires it into watchdog `main()`.

### ✅ RESOLVED 2026-05-16 — HERMES_API_KEY is a true Railway reference (definitively tested by live rotation)

Final state: Bob deleted the literal-stored `HERMES_API_KEY`, re-created it via Railway's explicit Reference picker UI on the dashboard, then rotated `API_SERVER_KEY` on the Hermes service to invalidate two leaked-in-transcript values. CLI verification confirmed `HERMES_API_KEY` on Sidecar auto-rotated to the new value (prefix changed, length 96 ✓). When future rotations happen, propagation is automatic.

Resolution path was painful: typing `${{...}}` syntax into a value field stores as LITERAL even though Railway's dashboard renders it back as the syntax AND auto-resolves it on the copy button — both misleading signals. Only definitive test is rotation. Saved as memory `reference_railway_cli_quirks.md` so future sessions don't re-flail.

### Original action item (resolved)

When I ran `railway variables --service livingapp-sidecar` to verify the set succeeded, the listing showed the key's RESOLVED value (a hex string fragment) rather than the reference syntax. Two possibilities:
1. **Stored as Railway reference** (`${{livingapp-hermes.API_SERVER_KEY}}`) — the CLI's listing always shows resolved values, but the underlying definition is the reference. Auto-rotation would work: when you rotate `API_SERVER_KEY` on the Hermes service, `HERMES_API_KEY` on Sidecar updates automatically.
2. **Stored as a literal copy** — the CLI's `--set` flag may have evaluated the reference at SET time and stored the literal. Auto-rotation would NOT work; you'd need to re-run the `railway variables --set 'HERMES_API_KEY=...' --service livingapp-sidecar` command after each rotation.

**To verify (30 seconds in dashboard):** open Railway dashboard → LivingApp-Platform → livingapp-sidecar → Variables tab. If `HERMES_API_KEY` shows a 🔗 (chain) icon next to its name, it's a reference (option 1, ideal). If it just shows the value, it's a literal (option 2 — re-set on rotation).

If literal: re-set via the dashboard with the reference syntax `${{livingapp-hermes.API_SERVER_KEY}}` (the dashboard preserves references better than the CLI does in my experience).

## Things to know about the cron infrastructure

- **`hermes cron` CLI** is the runner (saved as `reference_local_cron_runner.md`). Subcommands: `list`, `create`, `add`, `edit`, `pause`, `resume`, `run` (queue for next tick), `tick` (run due jobs immediately), `status`, `remove`.
- **Live store: `~/.hermes/cron/jobs.json`** — Hermes writes runtime state here on every tick. Mode 600.
- **Repo store: `hermes-dev-team/cron/jobs.json`** — version-controlled "specs". Only spec fields meaningful here (prompt / schedule / enabled / model / etc.); runtime fields shouldn't be edited in the repo.
- **Sync mechanism: `scripts/sync-cron-jobs.py`** — called from `install.sh`. Run `install.sh` again after editing repo's `cron/jobs.json` to propagate to live. Or run the script directly. `--dry-run` shows the diff.
- **Live-only jobs preserved**: Morning AI News (8am) and Morning Priority Check-In (7:30am) are not in the repo and will not be touched by the sync.
- **One-shot job inserted from repo**: `8194bfcabc06` (remind-bob-support-inboxes, fires once 2027-03-25). If this reminder is stale (you already have the support inbox details), `hermes cron pause 8194bfcabc06` to disable.

## Known follow-ups

### High priority — Bob's actions

1. **Merge PR #1 on Sidecar** (vitest 3.2 → 4.1.5). https://github.com/azrlb/LivingApp-Sidecar/pull/1. Clears 3 devDep CVEs (picomatch / postcss / vite via vitest transitive). Zero test regressions; safe to merge.
2. **Verify HERMES_API_KEY in Railway dashboard** (see "⚠ Action item" above). 30 seconds.

### Next session candidates

- **Session 5 — cleanup cutover.** Delete `src/nous-supervisor.ts` (~600 lines + 13 tests) + the old `src/pi-client.ts` subprocess machinery (~600 lines). Rename `src/pi-client-v2.ts` → `pi-client.ts`. Wire `validateEnv()` + `hermes-client` into `watchdog.ts` `main()`. Delete Dockerfile pi-builder stage. Net ~1000 lines deletion. **Prerequisites:** PR #1 merged + HERMES_API_KEY verified.
- **First friday-gold-panning run** — fires Friday 2026-05-22 at 10:00. Will produce `dev-team-work-loop/GOLD-PANNING-2026-05-22.md` with SHIP/RESEARCH/PARK buckets. Worth reviewing within a day so SHIP items can flow into BMAD story creation.
- **Run pi-client-v2 bench + integration test** before Session 5 cutover (per prior handoff): `PI_CLIENT_V2_BENCH=1 npx vitest bench tests/bench/pi-client-v2-coldstart.bench.ts` and `PI_CLIENT_V2_INTEGRATION=1 npx vitest run tests/integration/pi-client-v2-roundtrip.test.ts`. Cost: ~5-10 trivial LLM calls per run.

### Lower priority

- **The live cron's first real Sunday run** is 2026-05-17 03:00. Verify the corrected prefix logic + Surface 4 CVE endpoint work end-to-end. Output goes to `~/.hermes/cron/output/770cfee9f064/`.
- **Sidecar PR-merge convention** — auto-mode classifier increasingly blocks direct main commits in long sessions. Future devDep / chore work probably wants a feature-branch + PR pattern rather than direct-to-main. Pattern from this session: `chore/<scope>` branch + `gh pr create --base main`.
- **6-Hermes-profiles-all-identical pattern** — carried forward from prior handoffs, still unresolved.
- **Hermes container auto-update** — currently `HERMES_TAG` is hardcoded `v2026.5.7` in the Dockerfile. Bumps require Dockerfile edit + push. The cron's Surface 4 alert flags when this is stale; bumping is manual per ADR 002 cost-regression gate.

## Memory saved this session

Three files added to `~/.claude/projects/-media-bob-C-AI-Projects-hermes-dev-team/memory/`:
- `user_solo_creator_no_code.md` — Bob's collaboration profile (non-technical solo creator; AI team is the dev team)
- `feedback_decide_for_bob.md` — AI team owns technical recommendations; reserve AskUserQuestion for genuine product-level questions
- `reference_local_cron_runner.md` — `hermes cron` CLI is the runner for `~/.hermes/cron/jobs.json`; don't re-search the filesystem

## Next action when you're ready

**Merge PR #1 + verify HERMES_API_KEY in Railway dashboard.** Both are sub-2-minute tasks. Then either:
1. **Session 5 cleanup cutover** — natural next step on the Sidecar v2 plan; deletes ~1000 lines, biggest visible diff yet.
2. **Wait for Friday's first gold-panning run** (2026-05-22) and pick up actionable SHIP items from there.
3. **Investigate the 6-profiles-all-identical pattern** carried forward from earlier handoffs.

Recommendation: Session 5. The Hermes integration is now structurally sound; finishing the cleanup removes the visible "v1 still in place" weight from the codebase and unblocks the rest of the v2 plan.

---

## ✅ Session 5 done + deployed — addendum 2026-05-10 18:00 PT

Session 5 cleanup cutover completed in-session and shipped to production live.

**PRs merged:**
- **#2** — Session 5 cleanup cutover (-4,500 net lines: nous-supervisor / nous-client / v1 pi-client subprocess machinery deleted; pi-client-v2 renamed to canonical pi-client; watchdog composition root rewritten with validateEnv + hermes-client; Dockerfile 199 → 59 lines).
- **#3** — Dockerfile hotfix (`groupadd: GID '1000' already exists` build error; switched from `groupadd/useradd sidecar` to `USER node` since node:22-slim ships its own non-root user at UID/GID 1000).

**Production state:**
- `livingapp-sidecar` deployment `ef0ed872-c5e9-4c90-bf92-7f622fd33cff` SUCCESS at 18:00:23 PT.
- `/ready` returns HTTP 200 with `{"ready":true,"draining":false,"checks":{"hermes":"ok","gateway":"ok","budget":"ok"}}` — confirms the Session 5 health-endpoint rename (`nous` → `hermes`) is live, both circuit breakers report healthy.
- Boot logs include `[Watchdog] Hermes client: ok (http://livingapp-hermes.railway.internal:8642)` — the new composition-root output. Zero `Nous supervisor` references; the subprocess machinery is gone in production.
- The 19+ hour `Nous supervisor: failed` saga that motivated ADR 005 is over.

**Test suite:** 245 pass / 1 skip / 2 todo on Sidecar/main (was 323; -78 from deleted suites; zero functional regressions).

**Two friction items discovered + worth flagging for next session:**
1. **Railway GitHub auto-deploy is NOT wired up for `livingapp-sidecar`.** Merging a PR doesn't trigger a redeploy — had to invoke `railway up` manually twice. Worth wiring up the GitHub integration so future Sidecar PRs auto-deploy on merge. Small Railway dashboard config (Service → Settings → Source).
2. **Railway dashboard "Redeploy" button rebuilds from a stale source snapshot, not from the latest GitHub main.** The first attempted deploy (45439548 SUCCESS) actually rebuilt the v1 image — same broken `Nous supervisor: failed` code — because Bob clicked Redeploy after the first failure. The fix was to run `railway up` from local main again. Lesson: prefer "Deploy" or `railway up`, avoid "Redeploy" unless you specifically want to re-run the same image.

**Memory updates this session (2026-05-16 + 2026-05-10 deploy session):**
- `user_solo_creator_no_code.md` — Bob's profile (non-technical solo creator)
- `feedback_decide_for_bob.md` — AI team owns recommendations
- `reference_local_cron_runner.md` — `hermes cron` CLI is the runner
- `reference_railway_cli_quirks.md` — CLI shows resolved values; references via dashboard only

**Sidecar v2 roadmap remaining:**
- Session 6 — Pact contract tests on Sidecar↔Hermes (Murat's Condition 1)
- Session 7 — Spec updates (Story 1.18 superseded note, sprint-status.yaml)
- Session 8 — Post-deploy smoke vs Railway URLs (Murat's Condition 3)
- Cosmetic — delete the dead `hermes/` directory in the Sidecar repo (was config files for the deleted embedded-Hermes setup; functionally inert since the Dockerfile no longer COPYs it)

After Session 8 ships, all 3 of Murat's load-bearing conditions are met and Sidecar v2 is structurally complete. The spine is ready for the 4 dependent apps Bob is building.
