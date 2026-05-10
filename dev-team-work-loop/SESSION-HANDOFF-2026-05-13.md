# Session Handoff — 2026-05-13

## TL;DR

**Story 1.2 (audit emitter) shipped end-to-end AND deployed to production.** Both repos merged. Platform gateway service created in Railway and live for the first time ever. Sidecar wired to the gateway with a fresh RS256 keypair and redeployed. Full audit pipeline (Sidecar → Gateway → postgres-LVV) is now operational.

The session-handoff-from-2026-05-12 statement that "endpoint exists Platform-side from 1-19" was empirically wrong; 1-19 was DDL only. Caught at orientation. Saved as `feedback_verify_handoff_claims.md` — second incident this project of cross-repo claims drifting from reality.

## What's live in production

| Component | URL | Status |
|---|---|---|
| Gateway service | `https://livingapp-platform-production-cab4.up.railway.app` | ✅ `/api/v1/health` → 200; audit POST endpoint returns 401 without JWT (route + auth wired) |
| Sidecar service | `https://livingapp-sidecar-production.up.railway.app` | ✅ `/health` → 200 with JSON status; cleanly booted, no errors |
| Postgres-LVV | (Railway internal) | ✅ Was already live; gateway connects via `${{Postgres-LVV-.DATABASE_URL}}` reference |

## What landed in code

### LivingApp-Platform (merged to main)
- **PR #1 (squash `5161c45`)** — Story 1.2 Platform half: `gateway/src/db.ts` plumbs `traceId?` through `insertAuditLog`; `gateway/src/routes/apps.ts` adds `POST /api/v1/apps/:appName/audit` (JWT-authed + appScope-guarded, body validation, `X-Idempotency-Key` stash into `detail._idempotencyKey`); 13 new tests in `tests/gateway/apps-audit-post.test.ts`. Gateway suite 123 → 136.
- **PR #2 (squash on main)** — Deploy fix: added `npm start` script + moved `tsx` to `dependencies` in `package.json`. Required for Railway nixpacks builder (which prunes devDeps in production install).

### LivingApp-Sidecar (direct push to main, commit `4e8d1ce`)
- `src/audit-emitter.ts` (new) — bounded retry queue (500), exp backoff, sustained-failure-60s Telegram alert, circuit-breaker coordination (sleeps `retryAfterMs` while degraded — no double-pressure on the open breaker).
- `src/gateway-client.ts` — added `setAuditEmitter()` instance method (composition-root late-binding for circuit-state self-emits).
- `src/nous-supervisor.ts` — removed inline divergent `AuditEmitter`/`AuditEvent`; aligned onto `pi-client.ts` canonical async interface; emits wrapped in `safeEmit`. (Closed the 1.18-era debt.)
- `src/pi-client.ts` — extended `AuditKind` union with 4 variants (`nous.crash`, `nous.supervisor_gave_up`, `audit.queue_overflow`, `audit.delivery_stuck`).
- `src/watchdog.ts` (`main()`) — composition-root wiring: gateway-client + audit-emitter constructed; `setAuditEmitter()` swap; `getNousSupervisor({ auditEmitter })`.
- `tests/new/audit-emitter.test.ts` (new) — 12 cases.
- `tests/new/gateway-client.test.ts` — +1 case (setAuditEmitter late-bind).
- `tests/new/nous-supervisor.test.ts` — type swap + assertion shape update.
- Spec at `_bmad-output/implementation-artifacts/1-2-emit-audit-row-for-every-sidecar-action.md`.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — 1-2 backlog → done.

Sidecar suite 266 → 279 green.

## Production deploy work this session

A surprise discovery mid-session: **the LivingApp-Platform gateway had never been deployed as a Railway service before today.** The Sidecar had been running with no working JWT signing key (Story 1.8 shipped the code two weeks ago but env vars were never provisioned), and there was nothing for it to talk to anyway. Story 1.2 forced the issue.

Steps taken:
1. **Generated a fresh RS256 keypair** locally via openssl (2048-bit RSA). Files held in `/tmp/jwt-gen-180344/` during the session, shredded after wiring.
2. **Created `livingapp-platform` Railway service** in the existing project (Bob Banks's Projects workspace, project ID `97a44a19...`). Empty service first via `railway add --service livingapp-platform`, then env vars set via `railway variable set`, then GitHub repo connected via Railway web UI ("Connect Repo" → `azrlb/LivingApp-Platform` → main).
3. **Set 4 env vars on the gateway:** `JWT_PUBLIC_KEY_ACTIVE` (the public half of the keypair), `LOG_DRAIN_SECRET` (random 32-byte hex), `GATEWAY_START=true`, `DATABASE_URL=${{Postgres-LVV-.DATABASE_URL}}` (Railway reference variable).
4. **First build failed** — missing `npm start` script + `tsx` not in production deps. Fixed via PR #2; second build succeeded in 135s.
5. **Generated public domain** via `railway domain --service livingapp-platform`.
6. **Set 2 env vars on the sidecar service:** `JWT_PRIVATE_KEY_ACTIVE` (matching private key), `PLATFORM_GATEWAY_BASE_URL=https://livingapp-platform-production-cab4.up.railway.app`. Triggered Sidecar redeploy.
7. **Sidecar redeploy succeeded.** Runtime logs clean: `[Watchdog] Sidecar listening on port 8080`, `[Watchdog] Ready. Waiting for log events...`.
8. **Smoke tests passed.**

## Things to know about the production env

- **There are TWO postgres services in the project** — `Postgres-LVV-` (with trailing dash, used by the gateway) and `Postgres` (separate). The gateway's `DATABASE_URL` reference uses `Postgres-LVV-`. If you ever migrate or deduplicate these, update the reference.
- **Old `SIDECAR_JWT_SECRET` env var on the sidecar is dead config.** It was the old HMAC-style secret from before the RS256 upgrade. Nothing reads it anymore. Safe to delete in a future cleanup.
- **No Telegram notifier is wired in production yet.** The audit emitter accepts a `TelegramNotifier` via DI; default is no-op. So even if the audit pipeline jams, no alert will fire — failures are silent (queue caps at 500, oldest dropped). Wire a real Telegram sink when one exists.
- **Gateway uses `tsx` at runtime** (compiles TypeScript on demand). Slightly slower cold-start than pre-compiled JS. Future improvement: add a `tsc` build step + change `start` to `node dist/gateway/src/index.js` (matches Sidecar's pattern).

## Architectural decisions worth knowing about

1. **Action enum kept open.** `architecture.md:267` explicitly leaves the FR17 enum open with `|...`. Existing `pi.*` and `gateway.*` emit kinds project to `action=kind`; FR17 callers (skill-router/watchdog) use `emitAction()` which carries the FR17 enum.
2. **Two API surfaces on the audit emitter:** `emit(AuditRow)` (canonical, for internal observability) + `emitAction(EmitActionArgs)` (FR17, for state-changing actions).
3. **Endpoint path is `/audit`, not `/audit-logs`.** Architecture.md says `/audit-logs` but existing GET shipped at `/audit`; first-to-ship sets canonical (per `feedback_cross_repo_naming.md` memory).
4. **Checksum + createdAt are Platform-derived.** Sidecar does NOT compute or send them; Postgres `NOW()` and `gateway/src/db.ts:226-228` own those.
5. **trace_id is in the schema but excluded from the checksum.** Lets backfill (Story 1.9) happen without invalidating prior rows' tamper-detection.

## Known follow-ups

### Highest priority — Hermes integration: research-first redesign

**Status:** the Sidecar's Nous Hermes integration (Story 1.18) does not work in production. Code shipped + 10 supervisor tests pass + the `/ready` endpoint correctly reports it as unhealthy. But during the wrap-up of this session, we discovered the integration was built on partially-wrong assumptions about how `hermes-agent` actually deploys. **We do not yet know enough to fix it correctly.** Next session must do docs-first research before any code changes.

**What's verified-wrong:** spawn command (`python -m hermes_agent` → should be `hermes gateway start`), port default (8765 → 8642), missing env vars (`API_SERVER_ENABLED=true`, `API_SERVER_PORT`, `API_SERVER_HOST`), missing config files (`~/.hermes/config.yaml`, `~/.hermes/.env`).

**What's unknown — research must answer with citations:**
1. **Daemonization model.** Hermes has a PID file at `~/.hermes/gateway.pid` and references `systemctl`/`launchctl`. Does `hermes gateway start` fork a daemon and exit? If so, the supervisor's spawn-and-watch-PID model needs adjustment (e.g., poll the PID file, or check for a `--foreground` flag).
2. **Persistent state.** SessionStore + pairing are SQLite under `~/.hermes/`. Railway containers are ephemeral → need a Railway volume mount or external persistence.
3. **API_SERVER_KEY** — docs say required for non-loopback only. We bind loopback (`127.0.0.1`), so probably not needed — but verify.
4. **Existing stub investigation.** A `hermes-sidecar/` Python directory exists in the `LivingApp-Platform` repo (with `main.py` + `gateway/client.py` + `config/settings.py` per `__pycache__` artifacts). May be a half-finished wrapper from a previous attempt. Inspect before designing from scratch — could be salvageable or could be a wrong-turn to remove.

Hermes-agent is the right tool — it has multiple deployment modes (API server, ACP, MCP, library) supporting non-personal-assistant use cases. The shape (HTTP server on localhost + supervisor) is supported. Only the specific deploy mechanics need research.

**Verified Hermes docs read this session (seed for next session):**
- https://hermes-agent.nousresearch.com/docs/guides/python-library
- https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server
- https://hermes-agent.nousresearch.com/docs/developer-guide/gateway-internals

**Acceptance criteria for "we know how to deploy this":** a research story produces a verified deploy plan covering all 4 unknowns above with citations (doc URL + quote OR successful local-test demonstration). Only after that lands should Story 1.18 be rewritten with the corrected deploy and `nous-supervisor.ts` updated.

**Companion artifacts:** updated warnings on `architecture.md` (Sidecar↔Nous Hermes bullet) and Story 1.18 spec; companion memory `~/.claude/projects/.../memory/feedback_verify_external_apis.md`. Sidecar Dockerfile already has a `python -c "from run_agent import AIAgent"` smoke check that proves the install works (passes today) — that's the safety net for "install broke" but not for "deploy model wrong."

**Stub to inspect:** there's a `hermes-sidecar/` Python directory in the `LivingApp-Platform` repo with `main.py` + `gateway/client.py` + `config/settings.py` (per `__pycache__` artifacts). Could be a half-finished wrapper from a previous attempt. Worth inspecting before designing from scratch.

### Smaller follow-ups

- **Sidecar GitHub auto-deploy is not wired.** The `livingapp-sidecar` Railway service has `source: {repo: null}`. Every push for the past 2 months never auto-deployed. Tonight's `railway up` was the first fresh build in months. Connect via Railway UI: Service → Settings → Source → Connect Repo → `azrlb/LivingApp-Sidecar` → main.
- **Gateway `tsx`-at-runtime** could be replaced with a `tsc` build step for faster cold-starts.
- **Old `SIDECAR_JWT_SECRET` on the sidecar service** is dead config (was the pre-RS256 HMAC secret). Safe to delete.
- **Pre-existing test failures on Platform** (`tests/graduation/*.test.ts` + `tests/builder/g1-request-validator.test.ts`) — missing `await` on `getAuditLogs()` and a schema-type mismatch. Verified identical on pre-change tip; not in scope.

## Next action when you're ready

**Story 1.3 (cost attribution + budget circuit breaker)** is the natural next step — it depends on `audit-emitter.ts` (done + live) and shares the gateway-client pipeline. Spec lives in `_bmad-output/planning-artifacts/epics.md` line 247. Single-owner cluster on `skill-router.ts` per sprint-status — serialize with 1.5/1.6/1.13.

**Alternates:**
- **Story 1.9 (trace_id propagation)** — small plumbing job; would close the loop on Story 1.2 (the column + emitter exist; values still need to flow from WS → Pi → Nous → Gateway).
- **Sidecar `/ready` endpoint fix** (~10 min, see follow-ups above).
- **Generate end-to-end test traffic** to verify audit rows actually land in postgres-LVV. Easiest way: trigger a WS connection to the Sidecar and check the `audit_logs` table afterwards via `GET /api/v1/apps/:appName/audit` on the gateway.

## Memory saved this session

- `feedback_verify_handoff_claims.md` — verify cross-repo artifacts named in handoffs before designing around them. Two incidents now (1-8 env-var prefix, 1-2 endpoint-existence) = pattern, not coincidence.
