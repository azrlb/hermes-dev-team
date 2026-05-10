# Session Handoff — 2026-05-14

## TL;DR

**Two layered wins, one architectural pivot, zero production deploys.** Today was design + plumbing rather than a ship day.

1. **Sidecar v2 architecture decided.** BMAD party-mode roundtable (Winston + Amelia + John + Murat) returned a unanimous 4/4 verdict for **Option B**: keep TS Sidecar, extract Hermes to its own Railway service, consume Pi via the official `@earendil-works/pi-coding-agent` JS SDK in-process. Eliminates the entire spawn-and-coordinate failure surface that produced the 2-month broken Hermes integration AND the silent JWT env-var miss in Story 1.8. Three Railway services post-migration (Sidecar, Hermes, Gateway); zero subprocesses inside Sidecar.

2. **Dev-team migration shipped end-to-end.** Pi MCP server, Pi extensions, global pi binary, auto-update cron, auto-updater SKILL, README — all migrated off the deprecated `@mariozechner/pi-coding-agent` fork onto canonical `@earendil-works/pi-coding-agent@0.74.0`. Local Hermes upgraded 211 commits (was 195-behind at session start, then 211 by mid-session). Validated end-to-end with a vibe-loop smoke test that produced working `sum(a, b)` + tests in 3ms.

3. **Mid-design correction caught early.** The Sidecar v2 plan initially documented `hermes --gateway` as the API server invocation (per an earlier source-code reading). Local spike on the upgraded canonical Hermes proved the actual invocation is `hermes gateway run` with `API_SERVER_ENABLED=true` env (the api_server is a "platform" inside the messaging-gateway umbrella runtime). Better to discover this in design than mid-deploy.

## What landed in code (today)

### hermes-dev-team — branch `chore/d0-pause-auto-update-pi-hermes` merged to `dev` (FF, 7 commits)

| SHA | Subject |
|---|---|
| `af79a45` | chore(cron): pause auto-update-pi-hermes pending @earendil-works migration (D0) |
| `1a10125` | chore(cron): rewrite auto-update-pi-hermes prompt to track @earendil-works (D1) |
| `0e5840f` | chore(mcp): bump pi-agent MCP server to @earendil-works/pi-coding-agent (D2) |
| `0867a47` | chore(pi-extensions): migrate to @earendil-works + fix ctx.sessionId rename (D5) |
| `9e3ae95` | docs(migration): README links + auto-updater SKILL → @earendil-works (D7) |
| `ae8427b` | chore(cron): re-enable auto-update-pi-hermes after migration verified (D6 green) |

Plus design docs (committed as part of the plan):
- `dev-team-work-loop/DEV-TEAM-MIGRATION-2026-05-10.md` — full D0-D7 plan (8 sessions including D8 added mid-flight)
- `dev-team-work-loop/CRON-AUTO-UPDATE-REWRITE.md` — replacement spec for the cron job

**NOT pushed to origin.** All 7 commits exist locally on `dev`. Push when comfortable.

### LivingApp-Sidecar — `main`, commit `d200aeb` (1 commit, 5 files)

- **NEW** `docs/adr/005-sidecar-v2-option-b.md` — decision-of-record + party-mode verdict + Murat's three non-negotiable conditions (Pact contracts, boot-time env-var assertions, post-deploy smoke vs Railway URLs)
- **NEW** `_bmad-output/planning-artifacts/sidecar-v2-architecture.md` — implementation reference (service inventory, decision points H1-H4 + S1-S3 + CI1-CI2, inter-service contracts, file delete/create lists, migration sequencing, rollback story)
- **NEW** `_bmad-output/implementation-artifacts/1-18-research-deploy-plan.md` — 12 verified findings with primary-source citations (research artifact / audit trail)
- **MODIFIED** `_bmad-output/implementation-artifacts/1-18-nous-hermes-co-location-subprocess-supervisor.md` — flipped to SUPERSEDED 2026-05-10
- **MODIFIED** `docs/adr/003-pi-mono-build-uses-npm.md` — flipped to RETIRED 2026-05-10

**NOT pushed to origin.** Local main, 1 commit ahead.

### LivingApp-Platform — no changes today

## Architectural pivot — what changed and why

**Original plan (early in session):** patch Story 1.18's broken `nous-supervisor.ts` spawn args (wrong CLI flag, wrong port, missing env vars) + ship the 1.18 fix.

**What changed it:** primary-source verification surfaced THREE compounding revelations:

1. **Pi has NO HTTP server mode.** The previous "extract Pi to its own Railway service" plan (Option A) would require building + maintaining a custom HTTP-to-JSONL wrapper from scratch. That wrapper IS a second supervisor.

2. **Pi DOES have an official JS SDK** (`@earendil-works/pi-coding-agent` exports `createAgentSession`, `AgentSessionRuntime`, etc.). Native Node import; no subprocess.

3. **Sidecar (and dev-team) was on a deprecated fork.** `@mariozechner/pi-coding-agent` is npm-deprecated with explicit message: *"please use @earendil-works/pi-coding-agent instead going forward."* Sidecar's Dockerfile cloned from `badlogic/pi-mono` which has been moved/abandoned.

These dropped the architecture from a 4-service multi-protocol mess to **3 services + in-process Pi via SDK**. The first party-mode (before the Pi findings) had voted Option A 2-1; the second party-mode (after the findings) returned unanimous 4/4 for Option B.

**Bonus mid-spike correction:** discovered the actual API server invocation is `hermes gateway run` with `API_SERVER_ENABLED=true`, NOT `hermes --gateway` flag (which was documented in early drafts of ADR 005 + architecture doc). All three docs updated. The `gateway` umbrella runtime hosts `api_server` as one of its platforms (alongside Telegram/Discord/WhatsApp).

## Dev-team migration walkthrough (D0–D8)

| Session | What happened | Status |
|---|---|---|
| D0 | Paused `auto-update-pi-hermes` cron (was reinforcing deprecated fork weekly via `npm install -g @mariozechner@latest`) | ✅ committed |
| D1 | Rewrote cron prompt to track canonical `@earendil-works/pi-coding-agent`; added self-protection guards (abort if symlink still on @mariozechner; refuse npm-deprecated packages) | ✅ committed |
| D2 | Bumped `mcp-servers/pi-agent/package.json`: `@mariozechner@^0.63.0` → `@earendil-works@0.74.0`. `npm install` produced lockfile + 336 packages. Verified all 8 SDK exports the worker thread destructures (`AuthStorage`, `createAgentSession`, etc.) are present | ✅ committed |
| D3 | Local Hermes upgrade via `hermes update` — Bob ran. 211 commits behind → 0. HEAD now `d62808c37`. CLI surface intact | ✅ done by Bob |
| D4 | All 6 dev-team profiles + default verified in registry post-upgrade. `hermes doctor` fully green (Nous Portal logged in; ⚠ items are optional providers Bob doesn't use) | ✅ verified, no commit needed |
| D5 | 3 Pi extensions migrated (import string updates) + **1 breaking-change fix**: `ctx.sessionId` no longer exists in canonical SDK; replaced with `ctx.sessionManager.getSessionId()` per `ReadonlySessionManager` interface | ✅ committed |
| D7 | README links + auto-updater SKILL aligned with canonical upstream. SKILL got the same self-protection guards as the cron | ✅ committed |
| D8 | Global `/usr/local/bin/pi` swap from `@mariozechner@v0.67.68` to `@earendil-works@0.74.0`. Bob ran `sudo npm uninstall + install`. Symlink target now correctly resolves; cron's self-protection guard would PASS | ✅ done by Bob |
| D6 | End-to-end smoke test: `cd /tmp/d6-smoke && hermes chat --yolo -s dev-team/vibe-loop -q "<minimal sum function spec>"`. Bob ran. Result: vibe-loop produced `src/sum.ts` + `src/sum.test.ts` + `tsconfig.json`; 2/2 vitest tests passed in 3ms | ✅ green |
| (final) | Cron re-enabled per acceptance criteria (D2-D6 verified) | ✅ committed |

D6 was the key validation. The dev-team is now demonstrably operational on canonical upstream.

## Things to know about the dev env (post-today)

- **Local Hermes:** v0.13.0 / canonical HEAD `d62808c37` at `/local-AI-Stack/home-hermes/hermes-agent` (venv at `~/.hermes/hermes-agent/venv/`); symlink `/home/bob/.local/bin/hermes`
- **Local Pi:** `@earendil-works/pi-coding-agent@0.74.0` installed globally; symlink `/usr/local/bin/pi → /usr/local/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js`
- **`@mariozechner/pi-coding-agent` is GONE from `/usr/local/lib/node_modules/`.** Don't reinstall it. The cron + auto-updater SKILL now have explicit guards that abort if they ever see it.
- **Auto-update cron** is re-enabled and will run its first canonical-upstream check on the next Sunday 03:00.
- **Hermes doctor** is fully green for Bob's stack (Nous Portal). Optional-provider warnings (Codex / Gemini / MiniMax) are unused.
- **6 Hermes profiles** (`dev-orchestrator`, `hermes-detector`, `hermes-health-check`, `hermes-lander`, `hermes-verifier`, `pi-coder`) are all structurally identical (same model `xiaomi/mimo-v2.5-pro` via `nous` provider). Worth a flag for future cleanup — they may be 6 names for the same config, intentional or drift.

## Things to know about the Sidecar v2 plan

- **Architecture:** TS Sidecar + Hermes own Railway service (`livingapp-hermes`) + Pi via JS SDK in-process. 3 services, 0 subprocesses, 0 supervisors.
- **Hermes service command:** `hermes gateway run` (NOT `hermes --gateway`). Activated by `API_SERVER_ENABLED=true` env. Default port 8642, default host 127.0.0.1. For Railway (public-internet), MUST set `API_SERVER_KEY` (covered in Decision H4).
- **Pi consumption:** `import { createAgentSession } from '@earendil-works/pi-coding-agent'` in-process. No subprocess. Sidecar owns conversation context (`--no-session` mode for ephemeral).
- **Code to be deleted in execution:** `src/nous-supervisor.ts` (~600 lines + 13 tests), `src/pi-client.ts` subprocess machinery (~600 lines, becomes ~150-line SDK wrapper), `Dockerfile` Stage 1 (pi-builder, ~95 lines).
- **Code to be added:** `src/hermes-client.ts` (HTTPS+JWT mirror of `gateway-client.ts`), `src/pi-client-v2.ts` (SDK wrapper, then renamed to `pi-client.ts` after swap), `src/env.ts` (zod-validated boot-time assertions).
- **Three load-bearing conditions (Murat's, non-negotiable):** Pact contracts on Sidecar↔Hermes, boot-time env-var assertions, post-deploy smoke vs Railway URLs.

## Pi SDK footgun to watch for

The Pi SDK's `output-guard.js` monkeypatches `process.stdout.write` to redirect output. The MCP server (`mcp-servers/pi-agent/index.mjs`) handles this via worker-thread isolation. The Sidecar may need a similar mitigation depending on how it uses stdout (probably fine since Sidecar logs are already structured/non-stdio). **Verify in Sidecar v2 session 3** before committing the SDK migration.

## Known follow-ups

### Highest priority — Sidecar v2 session 2 (Hermes service Railway provisioning)

Real infra change: new Railway service `livingapp-hermes` (likely new sibling repo `LivingApp-Hermes` per Decision H1). Dockerfile per Decision H2 (Python 3.12 + uv pip install hermes-agent + smoke check + non-root user + foreground `hermes gateway run` as CMD). Env vars per Decision H3 (entrypoint script writes `~/.hermes/.env` from Railway env at container start). Auth per Decision H4 (`API_SERVER_KEY` as Railway-managed secret + Sidecar's `hermes-client.ts` includes Bearer token).

Costs: ~$5-10/mo additional. Touches production Railway. Deserves its own dedicated session.

### Medium priority

- **Push today's commits to origin.** Both `hermes-dev-team/dev` and `LivingApp-Sidecar/main` have 1+ commits ahead of origin. Bob hasn't been asked to push; do at convenience.
- **`/tmp/d6-smoke/` is gone** — already cleaned. No action.
- **`LivingApp-Platform/hermes-sidecar/` stub deletion** — unrelated parallel `hermes-cfo-sidecar` project (FlowInCash architecture); confirmed not salvageable for Nous integration. Recommend deletion as a separate cleanup commit on LivingApp-Platform. Deferred.

### Low priority

- **Hermes 6 profiles all identical** — investigate whether intentional (kanban routing labels) or drift. Architectural smell, not migration concern.
- **`pi-dispatcher` SKILL.md line 84** has a Pi CLI invocation example using stable flags (`--print --no-tools --provider --model`). Re-verify flags after canonical Pi has run in a real dev-team workflow (D6 implicitly did this).
- **Branch `chore/d0-pause-auto-update-pi-hermes`** has a misleading name now (the pause was just D0; the branch has the whole D0-D8 migration). It's already merged to dev (FF), so the branch can be deleted at convenience.

## Architectural decisions worth knowing about

1. **Option B over Option A (party-mode unanimous).** The architectural lesson from 2 months of silent breakage isn't "Hermes is bad" — it's that *co-location masquerades as simplicity while hiding contract violations.* Separate services fail loud on day one when contracts are wrong. But Option A (extract Pi too) was more expensive than expected because Pi has no HTTP mode (would require custom wrapper). Pi's JS SDK collapses one entire contract boundary into a typed in-process function call.

2. **Dev-team migration folded into Sidecar v2.** Originally separate; combined mid-planning when we realized fixing only the Sidecar would leave us building Sidecar v2 USING the broken stack the Sidecar v2 is curing. The dev-team is the meta-layer that builds the apps; if it's fragile, what it builds will be fragile.

3. **The cron's self-protection guard is non-negotiable.** Without it, a future accidental `npm install -g @mariozechner/pi-coding-agent` would silently re-corrupt the env and the cron wouldn't notice. The guard ABORTS rather than guesses.

4. **`hermes gateway run`, not `hermes --gateway`.** Subcommand + sub-subcommand form. `hermes gateway` is the umbrella messaging-gateway runtime; `api_server` is one of its platforms; activate via `API_SERVER_ENABLED=true`. Documented in ADR 005 + architecture doc + research artifact Finding 2.

## Next action when you're ready

**Sidecar v2 Session 2 — Hermes service Railway provisioning.** Architecture doc (`LivingApp-Sidecar/_bmad-output/planning-artifacts/sidecar-v2-architecture.md`) has the decision points (H1-H4) pre-resolved with recommended answers. Plan-of-record is at `~/.claude/plans/recursive-sparking-key.md`.

**Alternates if you want a different starting point:**

- **Push today's commits to origin** (small, safe, makes today's work durable beyond local disk)
- **Sidecar v2 Session 3** (Sidecar SDK migration in-place — no Hermes service needed yet; just the `pi-client.ts` SDK refactor against the current TS Sidecar)
- **Branch cleanup** — delete the merged `chore/d0-pause-auto-update-pi-hermes` branch
- **Investigate the 6-Hermes-profiles-all-identical pattern** — small architectural-hygiene task

## Memory saved this session

None. The existing `feedback_verify_external_apis.md` memory was reinforced (Pi findings + the `hermes gateway run` correction were both same-pattern surprises) but doesn't need updating — the memory's existing guidance ("verify external library APIs against primary docs before extending integration code") covers what we did today. The pattern is now twice-validated (Hermes 2026-05-13 + Pi 2026-05-14).

If anything new is worth saving, it's the meta-pattern: **"a deprecated upstream fork that's actively maintained by a cron"** is a specific failure class — auto-update mechanisms can mechanically reinforce wrong-upstream-identity errors. But this is more of an aphorism than actionable guidance; not saving as a memory.
