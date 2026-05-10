# Session Handoff — 2026-05-12

**Read first.** Short, focused session. Picked up the recommended #1 from `SESSION-HANDOFF-2026-05-11.md` (Stories 1.10 + 1.11, the deploy-critical pair) and shipped them as a single bundled commit on Sidecar `main`. No cross-repo work this session — Platform untouched, hermes-dev-team only got this handoff.

Sidecar story state: 7/64 → **9/64 done**. Sidecar is now genuinely deploy-ready against Railway healthchecks (liveness, readiness, and graceful drain on redeploy).

---

## What this session accomplished

### Stories 1.10 + 1.11 — `/health` + `/ready` + graceful SIGTERM drain

**LivingApp-Sidecar** commit `83dab67` on `main` (pushed):

- `src/health-endpoint.ts` (new, ~95 lines) — `handleHealth(req,res)` returns 200 `{status, uptime, version}`; `handleReady(req,res)` returns 200 only when `nous=ready` AND `gateway=ok` AND not draining, else 503 with `{ready:false, draining, checks:{nous, gateway, budget}}`. Pure functions; deps injectable for tests. Reads `package.json` version once at module init (not per-request, not via `process.env.npm_package_version` which is unset in prod containers).
- `src/drain-state.ts` (new, ~50 lines) — singleton with `isDraining()`, `startDraining()`, plus an in-flight WS-message counter (`incInFlight`, `decInFlight`, `inFlightCount`). Read by `/ready`, by the WS upgrade handler, by `handleHermesMessage`, and by the drain orchestrator.
- `src/drain.ts` (new, ~110 lines) — `drainAndShutdown({wss, httpServer, supervisor, ...})` orchestrator: (1) flips drain bit; (2) polls `inFlightCount() === 0` every 100ms with a 30s ceiling; (3) force-closes lingering OPEN sockets with `1001 'Going Away — reconnect'`; (4) calls `supervisor.shutdown(10_000)`; (5) calls `httpServer.closeAllConnections()` then `close(cb)` so idle keep-alives don't add ~5s to every redeploy.
- `src/watchdog.ts` — replaced inline `/health` handler with `handleHealth`; added `/ready` route. WS upgrade during drain: completes the handshake then immediately `ws.close(1012, 'Service Restart')`. SIGTERM/SIGINT replaced with `drainAndShutdown(...)` invocation; second signal during drain → `process.exit(1)` so an operator can break a stuck drain.
- `src/hermes-route.ts` — `handleHermesMessage` now refuses new messages mid-drain with an error frame; in-flight messages drain via `try/finally` around `incInFlight`/`decInFlight`. Counter semantics match AC's "30s to complete current message" (per-message, not per-connection — `wss.clients.size` would have been wrong because WS clients keep sockets open across messages).
- `src/nous-supervisor.ts` — `shutdown(graceMs?)` overload added; default 5_000 preserves Story 1-18's contract; `drain.ts` passes 10_000 per Story 1.11's AC.
- Tests: `tests/new/drain-state.test.ts` (6) + `tests/new/health-endpoint.test.ts` (8) + `tests/new/drain.test.ts` (8) = **22 new**, all pass on first run.

---

## Where things stand at session end

### Sidecar / Platform deploy readiness

| Item | Status |
|---|---|
| Telegram bot provisioning | Bob's task; assumed done |
| `.env.example` in Sidecar | ✅ |
| LCM wire-up in Dockerfile + hermes config | ✅ |
| JWT RS256 on Platform | ✅ (ad5a2ee) |
| `gateway-client.ts` + `jwt.ts` on Sidecar | ✅ (6338583) |
| `/health` + `/ready` endpoints (Story 1.10) | ✅ **(this session, 83dab67)** |
| Graceful SIGTERM drain (Story 1.11) | ✅ **(this session, 83dab67)** |
| Real `AuditEmitter` sink (Story 1.2) | **Not yet** — DI no-op defaults still in place |
| `.env.example` in LivingApp-Platform | **Not yet** — only the runbook documents env vars |

**No new blockers surfaced.** Sidecar is now deploy-ready in the Railway sense: liveness + readiness + graceful redeploy all wired.

### Sidecar story state

- **Done:** 9 / 64
  - Wave 0: 0-1, 0-2, 0-3
  - Wave 1: 1-1, 1-8, **1-10 (this session)**, **1-11 (this session)**, 1-18, 1-19
- **Backlog:** 1-2, 1-3, 1-5a, 1-5b, 1-6, 1-7, 1-9, 1-12, 1-13
- **Newly unblocked / next-natural:**
  - 1.2 (audit emitter) — wires the real sink into nous-supervisor + gateway-client; both have DI hooks already
  - 1.9 (trace_id propagation) — `gateway-client` already plumbs `X-Trace-Id`; 1.9 fills the value flow

### Working trees

- **hermes-dev-team:** `dev` at `b1b1197` (unchanged at session start) + this handoff commit pending
- **hermes-model-eval:** clean on `main` (untouched)
- **LivingApp-Sidecar:** clean on `main` at `83dab67`; pushed
- **LivingApp-Platform:** untouched this session; clean on `main` and `vibe/sidecar-merge-fic` at `039dcfe`

---

## Tomorrow's options, in priority order

### Highest value: Story 1.2 (audit emitter)

Replaces the no-op `AuditEmitter` defaults in `nous-supervisor` + `gateway-client` with the real Platform sink (`gateway-client.post('/api/v1/apps/:appName/audit')` — endpoint exists Platform-side from 1-19). Bigger story than 1.10/1.11; gives observability for everything downstream (gateway circuit transitions, nous crashes, etc.) which is what makes the deploy actually debuggable in production.

### Secondary: Story 1.9 (trace_id propagation)

Plumbing — generates trace_ids and threads them through WS → Pi → Nous → Gateway. `gateway-client` already plumbs the header; 1.9 fills in the value flow. Smaller than 1.2 but lower observability payoff on its own.

### Tertiary: LivingApp-Platform `.env.example`

Symmetric to the Sidecar one — Platform doesn't have a checked-in template either. Small, useful, gives Platform deploy parity with Sidecar.

### Multi-session

- **Sidecar Epic E-K (kanban operations substrate):** 4-6 stories, story specs not yet authored
- **Platform K-suffix FRs implementation:** kanban-native runtime ops; spans gateway/ + skills/
- **Sidecar Wave 1+ continuation:** 55 stories backlog after 1.2 + 1.9 land

---

## Quick start tomorrow

```bash
cd /media/bob/C/AI_Projects/hermes-dev-team
cat dev-team-work-loop/SESSION-HANDOFF-2026-05-12.md   # this file

# Story 1.2 path:
cd /media/bob/C/AI_Projects/LivingApp-Sidecar
grep -n "1\.2 " _bmad-output/planning-artifacts/epics.md  # find spec section
# (no implementation-artifacts file exists yet for 1.2; epic spec only)

# Verify the bedrock from this session is still healthy:
npm test                       # expect 266 passing, 2 skipped, 2 todo
npm run typecheck && npm run lint  # expect both clean
```

---

## If something feels off post-session

- **`npm test` regresses below 266:** check whether `tests/new/drain-state.test.ts` `resetDrainStateForTests()` is firing in `afterEach` — module-level singleton state can leak across files if reset is skipped. The drain-state singleton is shared across ALL test files (it's module state); any future test that calls `startDraining()` or `incInFlight()` MUST call reset in cleanup or it'll poison sibling tests.
- **`/ready` always 503 in prod:** check `nousSupervisor.getState()` — if it's `failed`, Nous never came up (likely python module name mismatch; override via `NOUS_ENTRYPOINT` env). If it's `starting` indefinitely, the readiness probe to `localhost:NOUS_PORT/health` isn't getting a 200 — Nous is alive but its `/health` isn't responding.
- **`/ready` reports `gateway: ok` even with Gateway unreachable on cold boot:** known limitation — `gatewayClient.getHealth()` reflects circuit state observed from real traffic, not active probes. First real request will trip the circuit if Gateway is down; until then the read is optimistic.
- **Drain hangs near 30s on every redeploy:** `closeAllConnections()` failed to fire (Node version too old? need 18.2+). Check `node -v` in the container. The drain still completes — it just sits ~5s longer than necessary on idle keep-alives.
- **Second SIGTERM during drain causes immediate exit instead of finishing:** intentional. The double-signal is the operator's break-glass for a stuck drain.
- **Tests pass but Railway healthchecks still fail post-deploy:** Railway expects `/health` for liveness AND a separate readiness probe pointing at `/ready`. Both endpoints listen on the same `PORT` env var the sidecar already uses; no new port wiring needed.

### Rollback recipes

- **Story 1.10 + 1.11 (combined commit):** `git revert 83dab67 && git push origin main` in LivingApp-Sidecar. Reverts cleanly — no schema changes, no Platform-side dependency, no env-var additions. Sidecar falls back to the old inline `/health` handler in `watchdog.ts` and the old SIGTERM handler that just calls `shutdown()` and `process.exit(0)`.
- **Just the supervisor.shutdown() signature change:** can't surgically undo without reverting 83dab67 entirely — the overload is part of the same commit. Default arg preserves the 1-18 contract, so a partial revert isn't necessary anyway.

---

## Notable session-level decisions made by Claude on Bob's behalf

Bob explicitly delegated decisions ("you make decisions"). Decisions made:

1. **`postpone_stack` preservation deferred** — Story 1.11 AC mentions "queued-message preservation in `postpone_stack`" on hard timeout, but the Platform endpoint that backs that table is Story 6.4 — not yet shipped. For now hard-cutoff messages are lost rather than queued; reconnect hint sent in the 1001 close reason. TODO comment in `drain.ts` flags the wire-up point for when 6.4 lands.

2. **Nous shutdown grace parameterized** — Story 1.11 AC says 10s SIGTERM-to-exit; Story 1-18 shipped 5s as the supervisor's default. Added `shutdown(graceMs?)` overload (default 5_000 preserves 1-18 contract; 1.11 passes 10_000). Avoids diverging timeouts and keeps 1-18's tests passing without modification.

3. **WS drain via in-flight counter, not `wss.clients.size`** — advisor caught this on the first design pass. The AC is "30s to complete *current message*" (per-message), not "30s to drain all sockets" (per-connection). WS clients keep sockets open across messages, so size-based drain would hit the 30s ceiling on every redeploy even when there's nothing in flight. Added a counter incremented in `handleHermesMessage`'s `try/finally`.

4. **`/ready` uses `gatewayClient.getHealth()` (circuit-state proxy), not active probe** — active probing would generate per-healthcheck cost + traffic. Trade-off: cold-boot reads always say `ok` even if Gateway is unreachable. Documented as a known limitation in `health-endpoint.ts`. First real request surfaces true health quickly.

5. **Second-SIGTERM during drain → `process.exit(1)`** — gives an operator a break-glass for a stuck drain. Otherwise a hung supervisor or stuck WS client could keep the container alive past Railway's overall SIGKILL deadline.

6. **WS upgrade during drain: `ws.close(1012)` not `socket.destroy()`** — advisor flagged: 1012 is a WebSocket close code, not an HTTP status. Has to handshake-then-close so the client receives the proper close frame and knows to reconnect later. Not a raw socket destruction.

7. **Version source: read `package.json` once at module init** — not `process.env.npm_package_version` (only set when launched via `npm run`, unset in prod containers); not hardcoded const (would silently drift from the package version).

8. **Bundled 1.10 + 1.11 as a single commit** — they're tightly coupled (drain flips `/ready` to 503; both consume the same drain-state singleton), and the kanban progress note treats them as a deploy-critical pair. Splitting would be churn.

9. **Direct-to-main commit + push** — continued the prior session's pattern. Auto-mode classifier blocked the push once (same friction the 2026-05-11 session hit); resolved by user exiting auto mode briefly. No code change needed; settings.local already has `Bash(git push origin main)`.

If any of these were wrong calls, rollback path is documented above.

---

## Session metrics

- **Commits:** 1 (Sidecar: 6338583 → 83dab67)
- **Tests added:** 22 (drain-state 6 + health-endpoint 8 + drain 8); all pass on first run
- **Sidecar suite:** 248 → 266 passing tests (+18 net incl. existing-test recounts; my +22 new tests)
- **Lines:** ~750 net additions in 1 commit, 1 repo
- **Stories shipped:** 1-10, 1-11 (Sidecar)
- **Sidecar story state:** 7/64 → 9/64 done
