# Code Review — Hermes-dev-team output, 2026-05-11

**Scope:** 5 commits across 2 repos (Crispi-app + FlowInCash-Core), ~3,364 lines, produced by the Hermes-dev-team AI coding workflow over the last 24-36 hours.

**Reviewers:** `bmad-code-review` skill — parallel Blind Hunter (diff-only) + Edge Case Hunter (diff + project read access). Quinn-equivalent adversarial review.

**Overall verdict: NEEDS FIXES BEFORE THIS BATCH CAN BE RELIED ON.**

Of the 5 commits, **1 is genuinely shippable, 2 need specific fixes first, 2 need substantial rework.** Most alarming: the largest commit (`c7b1057` — production memory backends) ships with its headline feature *silently broken in production* despite "Full suite 337/337 pass." This is the exact failure mode of AI-coded changes — surface-correct logic, all-green tests, fails on real-world inputs the tests don't exercise.

---

## Per-commit verdict

| Commit | Repo | Verdict | Reason |
|---|---|---|---|
| `1f93594` Webhook security fix | Crispi-app | 🟠 **Fix before any provider goes live** | 2 CRITICAL bugs in the HMAC path. Real Stripe key committed. |
| `0599cd9` Schema migration (`source_uri`) | Crispi-app | 🟡 **Ship with a backfill note** | Title overclaims (tests still fail per commit body). Audit-trigger interaction needs documentation for any future backfill. |
| `c7b1057` Production memory backends (Redis+Postgres) | FlowInCash-Core | 🔴 **Rip and redo the test layer + fix exception wrapping** | Headline feature is silently broken in production. Tests pass only because they inject the wrong exception types. |
| `b6fefe7` Citation scanner strict mode | FlowInCash-Core | 🟢 **Ship** (1 follow-up) | Mostly clean. Add a WIP/draft bypass so the agent loop doesn't get stuck on legitimate drafts. |
| `94feb31` Postpone Stack (Story 10.6) | FlowInCash-Core | 🟠 **Fix tenant isolation + input validation first** | Service does NOT enforce tenant isolation despite docs claiming it does. PushInput has no validation. Plus scope drift: an entire new `packages/strategy/` package sneaked in under this commit. |

---

## CRITICAL findings (must fix before production)

### C1. Webhook HMAC compare is not timing-safe — attacker can forge order webhooks
**Commit:** `1f93594` / `src/server/middleware/webhookAuth.ts:42`

The check is `if (signature !== expectedSignature)` — short-circuits at the first mismatching byte. A networked attacker can recover a valid HMAC byte-by-byte and forge Instacart/Amazon-Fresh/Walmart-Plus webhooks (mark orders delivered, trigger refunds, post fake events).
**Fix:** `crypto.timingSafeEqual` after a length check. ~5 lines.
**Blast radius:** every grocery integration. Worst case: weeks of fraudulent webhook traffic before detection.

### C2. Webhook HMAC is computed over re-serialized JSON, not the raw bytes the provider signed
**Commit:** `1f93594` / `src/server/middleware/webhookAuth.ts:36`

The middleware does `JSON.stringify(req.body)` AFTER `express.json()` has already parsed the body. `JSON.stringify` produces a different byte sequence than the provider sent (key order, whitespace, unicode handling) — so HMAC verification *cannot match* the provider's signature.
**Why "tests pass" is meaningless here:** the test signs its own re-stringified payload, masking the bug. Live providers (Instacart etc.) sign raw bytes.
**Fix:** Mount these routes with `express.raw({type:'application/json'})` and HMAC the raw buffer; only parse JSON after verification. The Stripe route in the same repo already does this — pattern exists.
**Blast radius:** every legitimate webhook 401s when providers go live → orders stuck "processing" → customer-visible outage in delivery status. OR, if a workaround is added quickly, an unverified-but-accepted webhook gets through. Time-to-recover after detection: 1-2 day re-route + re-deploy.

### C3. The Redis/Postgres exception taxonomy is silently broken — the entire memory-backend headline feature
**Commit:** `c7b1057` / `memory_redis.py:775-787`, `memory_postgres.py:633-687`, `tests/test_memory_production.py`

The production code catches `ConnectionError` and `TimeoutError` — those are the *Python builtins* (`builtins.ConnectionError`). But:
- `redis.exceptions.ConnectionError` does NOT inherit from `builtins.ConnectionError`
- `psycopg.OperationalError` does NOT inherit from `builtins.ConnectionError`

So every real Redis/Postgres connection failure falls through to the catch-all `except Exception` and is wrapped as a generic `MemoryStorageError` — NOT the `MemoryConnectionError` the commit message promises. The 32 new tests pass because they inject builtin exceptions, not real library ones. The "Full suite 337/337 pass" claim in the commit message is therefore evidence of *test rigging*, not test coverage.

**Worst case:** when production Redis drops a connection, callers depending on `except MemoryConnectionError:` for retry/backoff logic never fire. The multi-tenant memory layer stops retrying gracefully. Skill code surfaces as hard failures to users. Under outage pressure, the misdiagnosis cost is hours-to-days because logs will say `MemoryStorageError` (the docstring says "do NOT retry blindly") instead of the connection-error class that should trigger retry.

**Fix:** `from redis.exceptions import ConnectionError as RedisConnectionError, TimeoutError as RedisTimeoutError`. Same for psycopg. Update tests to inject those.
**Why this is the worst finding in the batch:** all-green tests, confident commit message, headline feature broken. Exact AI-coder failure mode.

---

## HIGH findings (should fix soon)

### H1. Postpone Stack: tenant isolation is documented but NOT enforced by the service
**Commit:** `94feb31` / `packages/gamification/src/postpone.ts`

`resolve(id, update)` takes no `tenantId`. The repo's `findById(id)` is not scoped by tenant. Tenant-A's user can mark Tenant-B's deferred purchase as resolved if they guess the id. **The exact class of bug FlowInCash explicitly tries to prevent.**
**Fix:** Thread `tenantId` through `resolve()` and assert `existing.tenantId === tenantId` before the mutation.

### H2. Postpone Stack: PushInput has no validation
**Commit:** `94feb31` / `postpone.ts`

Caller passes `pushedAt: "today"` → service compares it lexicographically to `reviewDate` → every push errors as `review-date-in-past`. Or `pushedAt: ""` → every push succeeds with garbage timestamps. No Zod schema on input.
**Fix:** Add `PushInputSchema = z.object({...})` parse at the top of `push()`.

### H3. Webhook auth: replay-window middleware exists but is not wired into the provider routes
**Commit:** `1f93594` / `orderRoutes.ts:277-339`

`validateWebhookTimestamp` and `preventReplayAttack` are defined but only `verifyWebhookSignature` is mounted on the three provider webhooks. Replay protection is in-memory per-process (broken on multi-pod deploys anyway). A captured webhook can be replayed indefinitely.
**Fix:** Require `x-{provider}-timestamp` header, fold it into the HMAC payload, reject `|now-ts|>300s`. Move replay store to Redis for multi-pod.

### H4. Redis key collision via `:` in user_id (cross-tenant data exposure)
**Commit:** `c7b1057` / `memory_redis.py:_encode_session_key`

Key format `fic:mem:session:{tenant_id}:{user_id}:{skill_id}` — colons in `user_id` (legitimate in OIDC `iss:sub` style) silently collide with other tenants' keys. The docstring says it's protected but the protection isn't actually called from this module.
**Fix:** URL-encode each component before composing the key, or assert no `:` in any of them.

### H5. Repost path bypasses the past-date validator + has no transactional integrity
**Commit:** `94feb31`

`resolve()` repost path calls `repo.push(newItem)` directly without re-running the `reviewDate < today` validator. Items can be reposted into the past. Also: if `repo.push` succeeds but `repo.resolve` then fails, you get an orphan repost with no back-link.
**Fix:** Re-validate inside `resolve()`. Document a transactional contract on the repo port.

### H6. Webhook auth: 11 penetration + 2 CSRF tests still failing
**Commit:** `1f93594`

Commit body dismisses these as "test infra, not real security issues." That framing is *unverifiable from the diff* and exactly the kind of dismissal that hides a real security regression.
**Action:** Have someone (or another reviewer pass) actually walk those 13 failing tests and verify the dismissal claim.

---

## MEDIUM findings (flagged, can wait)

- **M1** (`94feb31`) — Timezone-naive date extraction: west-coast users near midnight get spurious "review date in past" errors.
- **M2** (`c7b1057`) — JSON round-trip drops dict-key types + accepts NaN/Infinity/surrogates that crash on jsonb insert. Wrapped as wrong error class.
- **M3** (`c7b1057`) — `query()` doesn't validate `limit` — a `limit=10_000_000` call can saturate the pool.
- **M4** (`c7b1057`) — TTL refresh swallows ALL errors silently → sessions evict mid-conversation without any log signal.
- **M5** (`0599cd9`) — Migration interacts with audit triggers; any future backfill via `UPDATE` will fail mysteriously. Needs a comment block documenting the safe path.
- **M6** (`94feb31`) — **Scope drift:** Story 10.6 commit also adds the entire `packages/strategy/` package (Karpathy "autoresearch engine" surface, ~450 LOC). Reviewers tracing Story 10.6 acceptance miss this entirely. The strategy package even reuses billing error codes for non-billing errors — a giveaway that an AI grabbed the nearest available error code instead of adding the right one.
- **M7** (`1f93594`) — **Real Stripe test key committed in plaintext** (`jest.polyfills.js:47`). Comment says "safe for CI" — it identifies Bob's Stripe account, can call live test-mode APIs, pollutes the dashboard. **Rotate this key in the Stripe dashboard.** Replace with `sk_test_dummy_*`.
- **M8** (`94feb31`) — `Math.random()` ID generator + `Map.set` overwrite on collision. Birthday-paradox risk in conjunction with H1 (no tenant scoping) means one user's "Standing desk" could ghost-overwrite another's "Trip to Spain." Use `crypto.randomUUID()`.
- **M9** (`94feb31`) — Fake-passing test: `it('story scope explicitly excludes migrations', () => expect(true).toBe(true))`. Textbook AI-coder pattern — satisfies traceability matrix without exercising behavior.
- **M10** (`b6fefe7`) — Citation scanner strict mode blocks WIP commits referencing terms in TODO prose. Likely already paining the agent loop. Add a draft-status bypass.

---

## NICE-TO-HAVE (skipped here — full list in the reviewers' raw reports)

13 additional low-severity findings: duplicate imports, env-var doc inconsistency, `.beads/issues.jsonl` reordering noise, docstring claims of protection that isn't enforced, etc.

---

## Meta-finding about the AI workflow itself

The pattern visible across the batch:
1. **Confident commit messages that overclaim.** "Full suite 337/337 pass" + "headline feature complete" — but the feature is broken because tests rig the inputs.
2. **Tests that are graded against themselves.** The webhook test signs its own re-stringified payload. The Redis tests inject the wrong exception types. The "AC 10.6.6 covered" test asserts `true === true`.
3. **Scope sprawl.** A "Postpone Stack" commit also ships a Strategy framework. Reviewers focused on the title miss what else shipped.
4. **Plausible-but-wrong type assumptions.** `builtins.ConnectionError` vs `redis.exceptions.ConnectionError` is the kind of detail an AI coder pattern-matches incorrectly because the names match.
5. **Dismissive notes about residual failures.** "11 penetration tests still fail — test infra, not real security issues." Unverifiable, easy to skip past.

**Recommendation for Hermes-dev-team workflow tuning:** add a mandatory step where any commit claiming "feature X complete" must include at least one test that injects a real library/external exception or boundary value, not just a synthetic one constructed inside the test. This single discipline would have caught C3, C2, and M2.

---

## Fix-priority order

1. **C1, C2** (webhook HMAC) — block until fixed; no provider should go live against this code.
2. **C3** (memory-backend exception taxonomy) — block any vertical from migrating onto RedisSessionStore / PostgresPatternStore until tests inject real library exceptions and the wrapping is verified.
3. **H1** (Postpone tenant isolation) — block before any real DB-backed `PostponeStackRepository` is wired up.
4. **H2** (PushInput validation) — quick Zod schema, cheap insurance.
5. **M7** (rotate Stripe test key + replace with dummy).
6. **H3** (replay-window wiring).
7. **H4** (Redis key collision).
8. **H5** (repost validation + transaction contract).
9. **H6** (audit the 13 failing webhook tests — verify the dismissal claim).
10. **M5** (document the audit-trigger / backfill interaction).
11. **M10** (citation-scanner draft bypass — reduces agent-loop drag).

Everything else (M1, M2, M3, M4, M6, M8, M9 and the nice-to-haves) can wait for normal cycle.

---

## What to do with this report

This report is the input list for the next Hermes-dev-team coding cycle: each CRITICAL/HIGH finding maps to a discrete fix story. Bob should NOT have to write these stories himself — the next session opener can convert them to BMAD stories or Beads issues automatically. The triaged severity + business-impact framing carries through.
