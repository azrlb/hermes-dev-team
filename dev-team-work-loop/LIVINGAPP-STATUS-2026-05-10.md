# LivingApp + Sidecar Dev Status — 2026-05-10

**Why this exists:** before deploying to Railway, we needed a clear picture of how much of the LivingApp Sidecar + Platform work is actually shipped vs in-progress. The 2026-05-09 eval session implied Railway was the "next step" — this status check moves that off the docket until the listed blockers clear.

---

## Sidecar — 70% feature-complete, IN PROGRESS

**Where it is:**
- PRD v2 DRAFT (2026-04-14) + PRD-ADDENDUM-2026-05-08-plugins-and-kanban.md (PENDING INTEGRATION — awaiting PM decision post-model-eval)
- Wave 0 (Bedrock) — **DONE** ~30 days ago: Docker provision, ADR template, CI guardrails, Pi RPC, Platform gateway client, Hermes subprocess supervisor, Platform DDL coordination
- Wave 1+ (Capability) — **IN PROGRESS**: Story 1.1 (Pi non-blocking RPC) recently landed with 5 adversarial review passes

**Done (clearly shipped):**
- Docker image green (3-stage: pi-builder → ts-builder → runtime)
- Dockerfile pins enforced via hermes/config.yaml (pi_sha, NOUS_TAG, chromium, python)
- CI/CD: lint, typecheck, unit tests <2 min; heavy build + integration on push:main + PR ready_for_review
- ESLint + gitleaks + API path-prefix guardrail
- Base TS scaffold complete (watchdog.ts, personas.ts, pi-client.ts, auto-fixer.ts)

**In progress:**
- Wave 1 capability stories
- 30+ open beads issues

**Not started:**
- Epic E-D (Proactive Ops + anomaly alerts) — blocked on Telegram bot provisioning (~20 min ops task per NEXT-SESSION)
- Epic E-E (Autoresearch growth loops)
- Epic E-K (Kanban operations substrate from PRD addendum) — blocked on PM decision

**Blockers to Railway deploy:**
1. **Telegram bot token provisioning** — CRITICAL ops task, ~20 min via BotFather
2. **PRD addendum integration** — PM must decide if E-K (Kanban) merges; held pending model-eval result
3. **Platform integration** — Platform branch dirty (see below); audit_logs + JWT middleware require Platform DDL coord
4. **Credentials** — `.env.example` missing in Sidecar; Resend, Postmark, OpenRouter, Hermes credential store

---

## Platform — 60% feature-complete, IN PROGRESS

**Where it is:**
- Architecture v3-beads-pi-subagents-complete (in `_bmad-output/planning-artifacts/architecture.md`)
- 9 FR groups (FR-P1 through FR-P9) decomposing to ~60 requirements
- No standalone PRD addendum yet — Sidecar's addendum explicitly notes Platform addendum is a separate parallel work item

**Done (clearly shipped):**
- Express gateway + db.ts implemented
- Middleware (auth, cost tracking, audit) scaffolded
- Telegram webhook handler + callback routing (12 tests passing)
- Postgres migration from SQLite complete
- SMB Epic 6 skills (6 skills): PayrollAlert, PlanApprove, PlanGenerator, ForecastContentBuilder, DailyBriefing, WeeklyForecast — all landed with 12–16 tests each
- QA review: 2 critical + 4 high severity findings resolved
- Mission 1 & 2 layers (3 Pi extensions + 2 Hermes skills per layer)

**In progress:**
- Auto-updater Hermes skill
- Mission 2 Layer 2: story-implementer Hermes skill
- support-concierge, growth-runner refinement

**Not started:**
- Dashboard / observability UI (backlog only)
- Autoresearch cross-pollination engine (strategy defined)
- Health PDF report generation (deferred to Sidecar Phase D)

**Blockers to Railway deploy:**
1. **Branch state** — currently on `vibe/sidecar-merge-fic` with uncommitted `.beads/issues.jsonl` and stale cache. Must merge or clean before deploy
2. **Platform PRD addendum** — missing; Sidecar addendum says Platform parallel addendum is required to align kanban substrate (FR-P3, FR-P4, FR-P7)
3. **External credentials** — `.env.example` shows only DATABASE_URL + GATEWAY_JWT_SECRET; missing Resend, Postmark, Stripe webhooks, QuickBooks OAuth
4. **Integration test coverage** — vitest available, coverage threshold not enforced in CI; pre-deploy baseline undocumented

---

## Railway-readiness verdict

**Sidecar: IN-PROGRESS — not ready**
**Platform: IN-PROGRESS — not ready**

**Combined unblock time: ~3–5 hours of operational work** (not coding):
1. Merge / clean the Platform `vibe/sidecar-merge-fic` branch
2. Author Platform PRD addendum (parallel to Sidecar's — kanban substrate FR-P3/P4/P7)
3. Provision Telegram bot via BotFather → add to Railway secrets
4. Complete `.env.example` files in both repos
5. Sidecar PM decision on E-K kanban substrate addendum

After these, Railway deploy is appropriate. Until then, deploy is premature.

---

## How this connects to the 2026-05-09 eval session

- The eval surfaced Hermes plugins (LCM, hermes-agent-self-evolution, Memory Provider, Context Engine) that are referenced in the Sidecar PRD addendum but not yet integrated into Platform
- The block-watcher fix (commit 0be4e58 in hermes-dev-team) is a dev-team-side fix and does NOT impact Sidecar/Platform readiness
- The current eval re-run (mimo-v2.5-pro vs mimo-v2.5, 2026-05-10) is the input the PM needs before deciding whether to integrate the PRD addendum

So the chain is: **eval re-run finishes → PM decides on PRD addendum → Platform addendum authored → branches cleaned → Telegram + creds provisioned → Railway deploy**.
