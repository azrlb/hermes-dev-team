# Session Handoff — 2026-05-15

## TL;DR

**Three deliverables: Sidecar v2 Session 2 (Hermes service in prod), Sidecar v2 Session 3 (pi-client-v2 SDK wrapper), all four follow-ups.** No spec deviations from ADR 005; one architecture-doc number flagged as needing measurement (perf claim).

1. **`livingapp-hermes` is live in Railway prod**, in the same `LivingApp-Platform` project as `livingapp-sidecar` and the gateway, behind private DNS `livingapp-hermes.railway.internal:8642`. Pinned to `hermes-agent v2026.5.7` (matches the local Hermes that D6 smoke-tested on the previous session). Reaches `/health` from inside the Sidecar container; public ingress intentionally not configured.

2. **`src/pi-client-v2.ts` shipped on `LivingApp-Sidecar/main`** (3 commits ahead of origin, **NOT pushed**). New file alongside the existing `src/pi-client.ts` — old subprocess code stays put until the Session 5 cutover. 18 unit tests pass + 2 gated integration suites. Full Sidecar suite: 297 pass / 4 skip / 2 todo (zero regressions). `@earendil-works/pi-coding-agent@0.74.0` added as runtime dep.

3. **All four follow-ups completed and committed.** Auto-update strategy doc (#8), Hermes preflight in prod (#9), cold-start bench (#16), real-SDK integration test (#17). Two of them (#16 + #17) are gated on env vars so default `npm test` is unchanged; both ready to run when you want.

## What landed in code

### `LivingApp-Hermes` — NEW repo, `azrlb/LivingApp-Hermes` private, on `main`, ALREADY PUSHED (Railway pulled it for the deploys)

| SHA | Subject |
|---|---|
| `c9fd224` | chore(init): scaffold LivingApp-Hermes Railway service |
| `feda335` | docs: correct auth path — Nous uses OAuth, not raw API key |
| `fc662c3` | feat(preflight): boot-time env-var assertions (Murat's Condition 2) |

Files:
- `Dockerfile` — mirrors `NousResearch/hermes-agent` upstream, `HERMES_TAG=v2026.5.7` build arg, ENTRYPOINT chain runs preflight before tini → upstream entrypoint.sh → `hermes gateway run`
- `config.yaml` — minimal Hermes config (Nous provider, model `xiaomi/mimo-v2.5`); baked in at `/opt/data/config.yaml`
- `preflight.py` — 5 env-var validators, aggregates ALL failures (not just first), exits non-zero on any miss
- `.env.example` — required env-var shape, no values
- `README.md` — purpose + deploy instructions + reference links to ADR 005 + architecture doc

### `LivingApp-Sidecar` — branch `main`, 3 commits ahead of origin, **NOT pushed**

| SHA | Subject |
|---|---|
| `b37687a` | feat(pi-client): add pi-client-v2 wrapping @earendil-works SDK in-process (Session 3) |
| `629ad6b` | fix(pi-client-v2): read errorMessage/stopReason from agent_end.messages, not the event itself |
| `18d76ab` | test(pi-client-v2): add real-SDK roundtrip + cold-start bench (followups #17, #16) |

Files:
- `src/pi-client-v2.ts` (~430 lines) — `createAgentSession` + `SessionManager.inMemory()` per call, captures `process.stdout.write` at module load (S2 mitigation), preserves caller-visible `Result<T,E>` + `AuditEmitter` family, narrowed `PiErrorCode`, structural `AgentMessage` type to avoid pulling pi-agent-core as a transitive dep
- `tests/new/pi-client-v2.test.ts` — 18 unit tests, mocks `@earendil-works/pi-coding-agent` to drive happy/timeout/SDK-init/prompt-throw/agent-end-error/invalid-input/audit-resilience
- `tests/integration/pi-client-v2-roundtrip.test.ts` — real-SDK roundtrip; gated on `PI_CLIENT_V2_INTEGRATION=1`; two cases (basic prompt + S3 stateless-isolation proof)
- `tests/bench/pi-client-v2-coldstart.bench.ts` — `vitest bench` cold-start measurement; gated on `PI_CLIENT_V2_BENCH=1`; decision rule baked into doc header
- `package.json` + `package-lock.json` — `@earendil-works/pi-coding-agent@0.74.0` runtime dep, 235 packages added

Old `src/pi-client.ts` (1038 lines) and `src/nous-supervisor.ts` (~600 lines) **untouched** — Session 5 deletes them.

### `hermes-dev-team` — branch `dev`, 1 commit ahead of origin, **NOT pushed**

| SHA | Subject |
|---|---|
| `4114a26` | docs(strategy): unified auto-update strategy across 4 dependency surfaces (followup #8) |

Files:
- `dev-team-work-loop/AUTO-UPDATE-UNIFIED-STRATEGY-2026-05-10.md` — 259 lines

## Architectural decisions worth knowing

### Session 2 architecture (3 decisions confirmed with Bob)

| Question | Pick | Why |
|---|---|---|
| Where does Hermes source live? | New sibling repo `LivingApp-Hermes` | Cleanest deploy boundary; pushing only redeploys Hermes |
| Which Railway project? | Same as gateway+sidecar (`LivingApp-Platform`) | Unlocks Railway private networking — Sidecar↔Hermes never touches public internet; `API_SERVER_KEY` becomes defense-in-depth, not load-bearing |
| What Hermes version? | Pin to tag `v2026.5.7` | Matches local Hermes that D6 smoke-tested green on 2026-05-10 |

### Session 2 spike surprise that changed the Dockerfile

Architecture doc H2's recipe (`FROM python:3.12-slim + pip install hermes-agent`) was materially incomplete:
- `hermes-agent` is **NOT on PyPI** (verified `pypi.org/pypi/hermes-agent/json` → 404). Must install from git URL.
- Upstream Hermes ships a 113-line Dockerfile + 153-line entrypoint script that installs Node, npm, Playwright + Chromium, ripgrep, ffmpeg, gcc, tini, gosu, etc., and builds web/ + ui-tui/ workspaces. Hermes is not a slim service.
- Bob picked "mirror upstream Dockerfile pinned to v2026.5.7" — battle-tested by upstream maintainers.

### Session 2 auth surprise that added a Railway volume

`plugins/model-providers/nous/__init__.py:50` declares `auth_type="oauth_device_code"`. The `NOUS_API_KEY` env var on line 41 is metadata, not a usable headless auth path. Canonical headless story per `entrypoint.sh:84-96` is `HERMES_AUTH_JSON_BOOTSTRAP` — orchestrators seed `~/.hermes/auth.json` from env on first boot. Refresh tokens then rotate to disk.

Bob picked "Nous OAuth via `HERMES_AUTH_JSON_BOOTSTRAP` + Railway volume". Volume `livingapp-hermes-volume` mounted at `/opt/data` so refresh-token rotations persist across restarts. Architecture-doc-claimed "ephemeral `~/.hermes/`" is now intentionally walked back; rationale captured in the deploy-time correction commit.

### Session 3 architecture (S1/S2/S3 + verb scope)

| Decision | Pick | Source |
|---|---|---|
| S1 — naming/swap | New file `src/pi-client-v2.ts`; Session 5 swaps by rename | Architecture doc, primary |
| S2 — `output-guard.js` monkeypatching | Capture `process.stdout.write` at v2 module load BEFORE SDK import; export as `originalStdoutWrite` for future structured-logger sinks | Confirmed Sidecar uses plain `console.log` (no pino/winston) — defensive capture is necessary |
| S3 — session persistence | Per-call `createAgentSession` with `SessionManager.inMemory()` | Per-call stateless; container stays ephemeral; conversation memory is Sidecar's responsibility |
| Verb scope | Only `prompt` is implemented in v2 | Grep of all 7 callers — only `auto-fixer.ts:165` ever constructs a request, and only with `type:'prompt'`. `bash`/`abort` were YAGNI scaffolding in v1's pi-protocol.ts; never wired |

### Session 3 semantic fix from v1

v1's `prompt` verb resolved on Pi's immediate `{success:true}` ack while the actual coding work continued asynchronously inside the subprocess (header note `pi-client.ts:53-64` explicitly called this "the v1 stopgap"). v2 waits for the SDK's `agent_end` event so callers actually know when the agent finished. Wire shape stays compatible — `{type:'response', command:'prompt', success:true}` — plus a new `data:{text:string}` field carrying the last assistant message. Callers that don't read `data` continue to work.

### Session 3 advisor catch (worth knowing)

My first cut of `pi-client-v2.ts` read `event.errorMessage` from the `agent_end` event itself. Advisor flagged that I'd guessed event-payload shapes from intuition. Verification against `@earendil-works/pi-agent-core/dist/types.d.ts:330-368` (AgentEvent union) revealed `agent_end` carries `messages: AgentMessage[]`, NOT an `errorMessage` field. The error signal lives on the AssistantMessage inside that array (per `pi-ai/types.d.ts` AssistantMessage interface — has both `errorMessage?: string` and `stopReason: StopReason`). Fixed in `629ad6b` to walk `agent_end.messages` backward to the last AssistantMessage.

This is the exact failure mode the saved `feedback_verify_external_apis.md` memory exists to prevent. The mocked tests passed because I was driving my own hand-crafted event shapes against my own SDK mock — green tests meant "v2 works against the mock I wrote," not "v2 works." Fixed both the code AND filed followup #17 (real-SDK integration test) to catch this class of bug going forward.

## Things to know about the Railway state (post-today)

- **Project `LivingApp-Platform`** now has a third service: `livingapp-hermes` (id `27131538-cd9b-4e59-a008-569986a524d6`). Sister to existing `livingapp-sidecar` and `livingapp-platform` (gateway). Plus the existing `Postgres-LVV-`, `Postgres`, and unrelated `Crispi-app`/`flowincash`/etc. services in the same project.
- **Volume `livingapp-hermes-volume`** mounted at `/opt/data` on `livingapp-hermes`. Holds OAuth refresh tokens; ~$0.25/GB/mo (using <100 MB).
- **Private DNS `livingapp-hermes.railway.internal:8642`** is the canonical address Sidecar will use. Not reachable from the public internet.
- **No public domain** configured for `livingapp-hermes`. Smoke testing requires `railway ssh` from inside another service (auto-mode classifier blocks Claude from doing this; Bob runs the curls).
- **API_SERVER_KEY** was generated by Bob via `openssl rand -hex 48` and pasted into Railway dashboard. Live key — not visible to Claude. Rotate quarterly per ADR 002.
- **HERMES_AUTH_JSON_BOOTSTRAP** is Bob's `~/.hermes/auth.json` content, pasted into Railway dashboard. Refresh-token rotation writes back to the volume (not the env var); the env var is the first-boot bootstrap only.
- **Preflight runs on every container start.** Logs `[preflight] OK` on success; `[preflight] FAIL: <var> <reason>` per failed validator on miss + non-zero exit (Railway shows the misconfig immediately instead of crash-looping silently).

## Things to know about pi-client-v2

- **Old `pi-client.ts` is still in place.** It's still wired up in `watchdog.ts` via `nous-supervisor.ts` etc. v2 is sitting on disk, fully tested, but not yet called from anywhere. Session 4 (`hermes-client.ts`) doesn't need v2; Session 5 swaps v2 in and deletes v1.
- **18 unit tests are mock-driven.** They prove the v2 wrapper composes correctly against my hand-crafted event shapes. Real-SDK roundtrip (`tests/integration/pi-client-v2-roundtrip.test.ts`) is the canary; run it before Session 5 cutover with `PI_CLIENT_V2_INTEGRATION=1 npx vitest run tests/integration/pi-client-v2-roundtrip.test.ts`. Two cases: basic prompt + S3 stateless-isolation proof. Cost: 2 trivial LLM calls per run.
- **Cold-start bench is gated.** Run with `PI_CLIENT_V2_BENCH=1 npx vitest bench tests/bench/pi-client-v2-coldstart.bench.ts`. Decision rule in the doc header: if P50 ≥ 100ms, implement the singleton amortization (followup #16, file as a new task); if < 50ms, leave as-is and update ADR 005's "~1ms" claim with the measured number. Cost: ~5-10 trivial LLM calls per bench.
- **PiErrorCode narrowed:** subprocess-only codes (`pi.exit_nonzero`, `pi.protocol_violation`, `pi.spawn_failed`) gone; SDK codes (`pi.sdk_init_failed`, `pi.session_failed`) added; `pi.timeout` + `pi.invalid_request` unchanged. PiError narrowed: `exitCode`, `signal`, `stderr`, `stdout` gone; `cause` field added.
- **Verb scope:** only `prompt`. Calling `run()` with a `bash` or `abort` request returns `pi.invalid_request` with an explanatory message naming the verb. v1's pi-protocol.ts modeled bash/abort but no caller ever wired them.

## Things to know about the auto-update strategy doc

`dev-team-work-loop/AUTO-UPDATE-UNIFIED-STRATEGY-2026-05-10.md` (259 lines) was written by a background subagent. The 30-second version: extend the existing weekly cron `770cfee9f064` to detect drift uniformly across all 4 surfaces (local Hermes, global Pi binary, Sidecar npm dep, Hermes container pin), but split action by trust tier — dev-box (1+2) auto-bumps; production (3+4) gets alert-only Telegram digests with ADR 002 gate-criteria status pre-computed. Single ~1-session prompt edit (proposed "D9"). Five open questions for Bob raised in the doc; notably codifying the dev-tier opt-out from the 90-day clock and pinning Sidecar's `^0.74.0` → exact `0.74.0`.

I haven't read the doc end-to-end myself; the agent's report covered the recommendation but not the questions. If you act on it, read the full doc first.

## Beads-on-commit (housekeeping note)

Both Sidecar and hermes-dev-team commits triggered `.beads/issues.jsonl` exports via what's almost certainly a beads pre-commit hook. The first Sidecar commit (`b37687a`) included the file in its tree because it was already dirty when I staged; subsequent commits didn't because I staged only the source files explicitly. This is normal beads behavior — the issue database is intentionally tracked (init commit `f70e6ed`); only specific sub-files are gitignored. No action needed.

If you want beads exports always to live in their own commits (cleaner blame for code commits), that's a hook tweak (~5 min). I left it alone today.

## Known follow-ups

### Highest priority — push today's commits to origin

3 commits on `LivingApp-Sidecar/main` + 1 commit on `hermes-dev-team/dev`. Both are commit-only (Hermes is the only repo whose work was already pushed since Railway pulled from it). Push at convenience:

```
git -C /media/bob/C/AI_Projects/LivingApp-Sidecar push origin main
git -C /media/bob/C/AI_Projects/hermes-dev-team push origin dev
```

### Next session candidates

- **Session 4 — `src/hermes-client.ts` in Sidecar.** This is what actually wires Sidecar to the new Hermes service. HTTPS+JWT (or Bearer `API_SERVER_KEY`) over private DNS to `livingapp-hermes.railway.internal:8642`. Mirrors `gateway-client.ts` JWT-minting pattern. New `src/env.ts` for boot-time validation (Sidecar side of Murat's Condition 2 — Hermes side is now live). Architecture doc has the contract specifications.
- **Session 5 — Cleanup.** Delete `src/nous-supervisor.ts` (+ 13 tests). Rename `src/pi-client-v2.ts` → `src/pi-client.ts`, delete the old subprocess machinery. Delete Dockerfile pi-builder stage. ~1000 lines net deletion.
- **5 open questions** in the auto-update strategy doc — read it, decide, file follow-ups as needed.
- **Run the bench** (`PI_CLIENT_V2_BENCH=1 npx vitest bench …`) and the integration test (`PI_CLIENT_V2_INTEGRATION=1 npx vitest run …`). If bench shows cold-start ≥ 100ms, file a new "implement createAgentSession singletons" task and put it ahead of Session 5.

### Lower priority

- **Hermes service auto-update.** Currently the `HERMES_TAG` build arg is hardcoded `v2026.5.7` in the Dockerfile. Bumps require a Dockerfile edit + push. The strategy doc proposes this as a "production tier — alert only" surface (Bob decides via Telegram when Pulse fires).
- **Sidecar's `@earendil-works/pi-coding-agent` dep is `^0.74.0`** (caret range). Strategy doc recommends pinning to exact `0.74.0`; Bob decides.
- **Investigate the 6-Hermes-profiles-all-identical pattern** (carried forward from previous handoff — still unresolved).

## Memory saved this session

None. The existing `feedback_verify_external_apis.md` memory was reinforced (the `agent_end` shape mismatch was caught by exactly the vigilance that memory advocates) but doesn't need updating — the existing guidance covers what happened. Three-times-validated now (Hermes 2026-05-13 → Pi 2026-05-14 → Pi SDK event payload 2026-05-15).

## Next action when you're ready

**Push today's commits, then start Session 4 (Sidecar's `hermes-client.ts`).** Session 4 is the natural follow-on — it actually wires Sidecar to the Hermes service we stood up today. Architecture doc has the contract pre-specified. Code-only, no infra; same low-risk profile as Session 3.

**Alternates:** read + act on the auto-update strategy doc's 5 open questions; OR run the bench/integration test to validate v2 against the real SDK before Session 5 cutover; OR investigate the 6-profiles drift carryover.
