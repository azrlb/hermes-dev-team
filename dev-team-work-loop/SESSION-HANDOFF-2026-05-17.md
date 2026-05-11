# Session Handoff — 2026-05-17

## TL;DR

**Sessions 6 + 8 shipped in one sitting, as PRs, on a deliberately thinned scope.** The 2026-05-16 handoff's premise that Session 6 was "60–90 min of mechanical Pact tests across N endpoints" didn't survive orientation: Sidecar today makes effectively ONE outbound HTTP call to Hermes (`/health`), and the legacy `/hermes` WebSocket route uses `spawn('hermes')` which has zero consumers and is broken in the slim post-Session-5 container anyway. After surfacing the discovery with a 3-option recommendation (A: thin Pact scaffold; B: full HTTP migration of `/hermes` + Pact; C: skip Pact, do post-deploy smoke), Bob chose **A + C** — ship the Pact scaffold so the pattern exists for future endpoints, and ship the smoke job in the same session for immediate production-risk value.

Two PRs open, both awaiting first CI run + Bob's merge. One new repo-secret needed on the Hermes side for the cross-repo pact pull. One pre-existing CI issue (Sidecar's `ci.yml` heavy job has been red since Sidecar v2 cutover) was discovered but NOT fixed — flagged below.

## What landed in code

### `LivingApp-Sidecar` — PR [#4](https://github.com/azrlb/LivingApp-Sidecar/pull/4)

Branch `chore/session-6-pact-infra`, 2 commits, both pushed.

| SHA | Subject |
|---|---|
| `1ac72f2` | feat(test+ops): Sessions 6+8 — Pact consumer infra + post-deploy smoke |
| `e731892` | fix(ci): allowlist test bearer fixture + reduce smoke cadence to hourly |

Files added/modified:
- `package.json` + `package-lock.json` — `@pact-foundation/pact ^16.4.0` as devDep. New script `test:pact`.
- `tests/pact/hermes-health.pact.test.ts` — PactV3 consumer test for `GET /health` (Bearer auth + `x-request-id` regex matcher → `200 { status: "ok" }` shape).
- `pacts/livingapp-sidecar-livingapp-hermes.json` — generated contract file, committed in-repo per architecture doc CI2.
- `tests/pact/README.md` — pattern doc for adding future endpoint contracts (~10-line copy of the /health test).
- `.github/workflows/post-deploy-smoke.yml` — hourly probe of `https://livingapp-sidecar-production.up.railway.app/ready`. Asserts `ready=true` + `checks.{hermes,gateway,budget}=ok`. Telegram alert is wired but conditional (activates when `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` repo secrets exist; until then, GitHub email on workflow failure is the fallback).
- `.gitleaks.toml` — allowlist additions: `^pacts/.*` (contract files contain example bearers by spec) + the literal `test-api-key-32-characters-long-xx` (the canonical test fixture used in hermes-client unit tests AND the new Pact test). This unsticks a pre-existing gitleaks failure that has been red on main since Session 4 introduced the fixture.

Test suite: **246 pass / 1 skip / 2 todo** (was 245 pre-Pact). Typecheck clean.

### `LivingApp-Hermes` — PR [#1](https://github.com/azrlb/LivingApp-Hermes/pull/1)

Branch `feat/pact-verify-workflow`, 1 commit, pushed.

| SHA | Subject |
|---|---|
| `b981807` | feat(ci): Pact provider verification workflow (Murat's Condition 1) |

Files added:
- `.github/workflows/pact-verify.yml` — sparse-checks-out `LivingApp-Sidecar` (via `SIDECAR_PACT_PAT` secret) to read `pacts/livingapp-sidecar-livingapp-hermes.json`, builds the Hermes Docker image, boots it with stub env vars satisfying `preflight.py`, waits for `/health`, runs `pactfoundation/pact-ref-verifier` Docker image against the live container. Build fails on any contract drift between `HERMES_TAG` pin bumps.

## Architectural decisions worth knowing

### The thin Pact scope (A+C path) — recorded

**Why this matters going forward:** any AI agent picking up Sidecar v2 work needs to understand WHY the Pact scope is currently `/health`-only and not the inference path the 2026-05-16 handoff anticipated.

The handoff scoped Session 6 as "one Pact test per Sidecar→Hermes endpoint, mostly mechanical, 60–90 min." Reality on the ground:

| Codepath | Today |
|---|---|
| `health-endpoint.ts` `/ready` aggregator | Only reads `hermesClient.getHealth()` — IN-MEMORY circuit state, not an HTTP call. The async `.health()` method exists but no production caller exists today. |
| `hermes-route.ts` `/hermes` WebSocket | Uses `spawn('hermes', ...)` (legacy v1 path). The `hermes` CLI binary doesn't exist in the slim node:22-slim container post-Session-5, so the route is broken in production. BUT — verified: zero consumers across all 4 dependent apps (Crispi-app, Crispi-MicroApps, FlowInCash, FlowInCash-Core, FlowInCash-CloudComm, FliC-MicroApps), so nobody notices. |

Bob's framing was "spine of the business, done right, not in a rush." Three options were presented:
- **A — Thin Pact scaffold** (~45 min): infra + `/health` contract + pattern doc.
- **B — Full migration + Pact** (~2–3h): migrate `/hermes` WebSocket from CLI spawn → HTTP streaming via `hermes-client`, then Pact-test inference endpoints + `/health`. But: ships a feature with no consumer to validate it.
- **C — Defer Pact, do post-deploy smoke instead** (~30–45 min): higher immediate-risk leverage.

**Decision: A + C.** Lock in the Pact pattern so the next real endpoint inherits it cheaply; ship smoke immediately for current production-risk value. Path B is the right thing to do AFTER there's a frontend consumer for `/hermes` (Crispi or FlowInCash voice UI).

### `hermes-route.ts` is in limbo — needs explicit decision

The `/hermes` WebSocket route exists in code but is broken in production. The migration (B-path) was deferred this session. Outstanding question:

- **If `/hermes` will ship in a voice UI eventually:** B-path work is required before that UI ships. Should be a dedicated session that migrates the route to use `hermes-client.post('/v1/chat/completions', payload, { stream: true })` with token streaming, then adds Pact tests for the inference endpoints alongside.
- **If `/hermes` won't ship:** delete `src/hermes-route.ts` + `tests/hermes-route.test.ts` + the `/hermes` WS upgrade handler in `watchdog.ts` + the `/hermes/audio/*` HTTP handler. Net ~600 lines deletion.

Recommend Bob make this call before the next dev cycle that touches Sidecar internals — keeping a broken-in-prod-with-no-consumers route is technical debt that compounds.

### Cross-repo pact pull: `SIDECAR_PACT_PAT` secret required

Both repos are private. The `pact-verify` workflow uses `actions/checkout@v4` with `repository: azrlb/LivingApp-Sidecar` to sparse-checkout the `pacts/` dir. That needs a fine-grained PAT.

**First-run setup (Bob's action, ~2 min):**
1. GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token.
2. Scope: only `azrlb/LivingApp-Sidecar`. Permission: `Contents: read`. No other perms.
3. Expiration: 1 year (long, since this is CI plumbing — easier to rotate when due than to chase expired tokens).
4. On `azrlb/LivingApp-Hermes` repo → Settings → Secrets and variables → Actions → New repository secret. Name: `SIDECAR_PACT_PAT`. Value: paste token.

Without this secret, the Hermes PR's first CI run will fail fast on the sparse-checkout step. Non-destructive failure (no half-state), but PR shows red until secret is provisioned.

## Three things flagged for next session

### 1. **Pre-existing Sidecar CI failure on `main` is unrelated to this PR**

Confirmed via `gh run list --branch main --limit 8`: every push to `main` since 2026-05-10 05:59 UTC shows the `Build image, verify pins, integration test` heavy job FAILING. Root cause (not investigated in this session, but high-confidence guess): `ci.yml` lines 56–124 parse `hermes/config.yaml` `upstream_pins.{pi_sha, chromium_version, python_version, nous_hermes_tag}` and pass them as Docker build-args. Session 5's Dockerfile rewrite deleted the entire pi-builder stage; those pins are stale or the config.yaml shape changed.

**On PR #4:** `lint + typecheck + unit tests` PASSES (our changes don't regress what works). `build-and-verify` and `secret-scan` show fail in the first run — the former is the pre-existing breakage; the latter was the gitleaks/test-bearer issue, which is fixed in `e731892`. Should be 1-fail (the unrelated heavy job) after the new CI run completes.

**Action for tomorrow:** decide whether `ci.yml`'s heavy job should be repaired or rewritten given v2's actual Dockerfile. Probably rewrite — the existing 3-stage build-arg machinery is Sidecar v1 era.

### 2. **Provider container boot in CI: not locally validated this session**

The `pact-verify.yml` workflow boots the Hermes container with stub env vars (`HERMES_AUTH_JSON_BOOTSTRAP='{"tokens":{}}'`) sufficient to satisfy `preflight.py` — but it was NOT verified locally that `hermes gateway run` (the upstream binary inside the container) ACTUALLY starts cleanly with stub bootstrap JSON and serves `/health` returning 200. Cold-build of the Hermes Dockerfile was kicked off but hadn't completed by session end (5–10 min total).

**Risk if it doesn't boot cleanly:** first CI run on `LivingApp-Hermes` after the PAT is provisioned will fail at the "Wait for /health to respond" step. Diagnosable from `docker logs` in the workflow output.

**Mitigation paths if it fails:**
- Likely fix: minimal valid bootstrap JSON includes more than just `tokens={}` — upstream entrypoint at `/opt/hermes/docker/entrypoint.sh:84-96` is authoritative for what fields are required.
- Fallback: the pact verifier replays the exact example bearer from the pact file; if Hermes's API server `/health` doesn't require auth, the bearer mismatch wouldn't matter and we'd see a different failure mode.

**Recommendation:** before merging Hermes PR #1, manually run the docker boot locally (the command is documented in the workflow's comments) to verify the stub env-var set is sufficient. ~10 min of investment to avoid a red first CI run.

### 3. **GHA-minute budget on the smoke workflow**

Started at `*/15` (96 runs/day, ~1440 min/month, 72% of the 2000-min free-tier budget on one workflow). Reduced to hourly in `e731892` (~96 min/month). If Bob wants tighter SLA, change `'0 * * * *'` back to `'*/15 * * * *'` and accept the budget impact — every other workflow combined uses well under 500 min/month historically.

## Things to know about the Railway state

No Railway changes this session. Confirmed live: `https://livingapp-sidecar-production.up.railway.app/ready` returns `{"ready":true,"draining":false,"checks":{"hermes":"ok","gateway":"ok","budget":"ok"}}` — every dependency green at session end.

The smoke workflow's `repository_dispatch: railway-deploy` trigger is wired but unused — if Bob wants instant post-deploy verification, configure Railway's deploy webhook to POST to `https://api.github.com/repos/azrlb/LivingApp-Sidecar/dispatches` with `{"event_type":"railway-deploy"}`. Optional v2 enhancement.

## Memory NOT changed this session

No new memory files added — the cross-cutting lessons from this session (scope-discovery triage; decide-for-Bob framing) are already captured in existing files:
- `user_solo_creator_no_code.md`
- `feedback_decide_for_bob.md`
- `feedback_verify_handoff_claims.md`

The session's specific decisions (thin-Pact-A+C, the gitleaks fixture allowlist, the smoke cadence) are documented inline in PRs and commits — those are the canonical record, not memory.

## Known follow-ups

### High priority — Bob's actions

1. **Provision `SIDECAR_PACT_PAT` on LivingApp-Hermes** — 2 min, blocks Hermes PR #1's CI from going green.
2. **Merge order**: Sidecar PR #4 first, then Hermes PR #1. (Hermes verification reads Sidecar's pact file from main; merging Hermes first means it tries to read a non-existent file.)
3. **Optionally**: provision `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` on Sidecar to activate Telegram alerts on smoke-job failure. Until then, email-on-failure from GHA's default notifier is the fallback.
4. **Resolve `hermes-route.ts` direction**: will the `/hermes` WebSocket ship in a voice UI, or be deleted? See "in limbo" section above. Affects whether the next Sidecar session is a migration or a deletion.

### Next session candidates

- **Repair `ci.yml`'s heavy build-and-verify job** — references deleted Sidecar v1 pi-builder pins. Probably rewrite around the v2 Dockerfile shape. Decoupled from Session 6/8 work, but blocks main-branch CI from being green.
- **Friday 2026-05-15 first gold-panning run** (per prior handoff's schedule — fires `0 10 * * 5`). Output will land in `dev-team-work-loop/GOLD-PANNING-2026-05-15.md`. Worth reviewing within a day to feed SHIP items into the next BMAD story-creation session.
- **First post-deploy-smoke run** within an hour of Sidecar PR #4 merging to main. Verify it actually pings `/ready` end-to-end and the summary lands in the GHA run UI.
- **First Hermes pact-verify run** after Hermes PR #1 merge + secret provision. This is the test of whether the stub-env-vars-and-pact-replay scheme actually works end-to-end. If it fails, see "container boot" risk section.
- **FlowInCash-Core parallel-work review** (carried forward from 2026-05-16 handoff). Murat persona + `bmad-code-review` skill against whatever the Hermes-dev Kanban flow produced there.

### Lower priority

- **Session 7 — Spec updates** (carried forward): Story 1.18 superseded note, sprint-status.yaml. Not urgent.
- **Cosmetic — delete dead `hermes/` directory in Sidecar repo** (carried forward): config files for the deleted embedded-Hermes setup. Functionally inert since the v2 Dockerfile doesn't COPY it.
- **6-Hermes-profiles-all-identical pattern** — still carried forward from earlier handoffs, still unresolved.

## Next action when you're ready

**Bob's 5-minute kick-off path:**
1. Provision `SIDECAR_PACT_PAT` secret on LivingApp-Hermes (instructions above).
2. Merge Sidecar PR #4 first.
3. Merge Hermes PR #1.
4. Watch the first scheduled `post-deploy-smoke` run and the first `pact-verify` run land green (or read the failure details if not).

After that, the candidate session shortlist is: (a) decide `hermes-route.ts`'s fate, (b) repair `ci.yml`'s broken heavy job, (c) FlowInCash-Core parallel-work review. Recommendation: (a) first — it's a single product decision that unblocks a meaningful chunk of follow-on work.
