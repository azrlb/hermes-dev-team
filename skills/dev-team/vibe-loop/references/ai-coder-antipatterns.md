# AI-Coder Anti-Patterns — Quinn's Mandatory Checklist

Loaded by Phase 10c (Quinn Adversarial Review). Each anti-pattern is a class of bug that AI coders produce more often than human coders, in ways that pass naive test suites. Quinn MUST grep for these on every file touched by a session and report any hit as a finding.

This catalog is grown from real findings against Hermes-dev-team output (see `dev-team-work-loop/CODE-REVIEW-*.md` files for the source incidents). When a NEW class of AI-coder failure shows up in a code review, append it here so future Quinn passes catch it.

---

## Crypto / Auth anti-patterns

### AP-CRYPTO-1 — Non-timing-safe comparison of secrets, tokens, or HMACs

**Pattern (any language, any of these forms):**
- JavaScript / TypeScript: `signature !== expected`, `token === userInput`, `hmac == providedHmac`
- Python: `signature != expected` on bytes/strings, `hmac.compare_digest` NOT used
- Any language: a `!=` / `==` / `!==` / `===` against a value that is a secret, signature, HMAC, MAC, token, password hash, session id, or any other security-critical equality check

**Why it's wrong:** byte-by-byte comparison short-circuits at first mismatch. Network attacker with retries can recover the secret one byte at a time.

**Right pattern:**
- JS/TS: `crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b))` — with a prior length check (timingSafeEqual throws on unequal lengths)
- Python: `hmac.compare_digest(a, b)`

**How Quinn checks:** grep changed files for `signature\|token\|hmac\|mac\|secret\|password.*hash\|session.*id` near `==\|!=\|===\|!==`.

---

### AP-CRYPTO-2 — HMAC computed over re-serialized JSON

**Pattern:** Webhook auth middleware that:
1. Mounts AFTER a body-parsing middleware (e.g. `express.json()`, FastAPI default JSON parse)
2. Computes HMAC over `JSON.stringify(req.body)` or `json.dumps(request_body)`

**Why it's wrong:** the provider signed the RAW bytes. After parse → re-stringify, key order / whitespace / unicode escape / number formatting differ. HMAC will NEVER match real provider traffic. Tests pass only because the test signs its own re-stringified payload.

**Right pattern:**
- Mount the route with `express.raw({type:'application/json'})` (or FastAPI `Request` + `await request.body()`).
- HMAC over the raw `Buffer` / `bytes`.
- ONLY parse JSON after verification.

**How Quinn checks:** for any file containing both `crypto.createHmac` / `hmac.new` AND a request-body access, verify the body is read in raw form, not re-stringified.

---

### AP-CRYPTO-3 — Replay-window middleware exists but is not wired

**Pattern:** Code defines a `validateWebhookTimestamp` or `preventReplayAttack` helper, but the route only mounts the signature-verification middleware. Or the replay store is in-memory (a JS `Map` / Python `dict`) on a multi-process service.

**Why it's wrong:** a captured webhook can be replayed indefinitely. On multi-pod / multi-process deploys, an in-memory map gives the illusion of replay protection on a single pod and nothing on the others.

**Right pattern:**
- Always require a timestamp header.
- Fold the timestamp into the HMAC payload: `hmac(secret, timestamp + '.' + raw_body)`.
- Reject requests where `|now - timestamp| > 300s`.
- Replay store: Redis (or any shared store), keyed by signature+timestamp, with TTL ≥ the freshness window.

---

## Test-quality anti-patterns

### AP-TEST-1 — Fake-passing test (`expect(true).toBe(true)` and equivalents)

**Pattern (any test framework):**
- `expect(true).toBe(true)` / `expect(1).toBe(1)` / `assert True` / `assert 1 == 1`
- A test whose body has no calls to the system under test
- A test that asserts only on values it constructed locally without invoking production code

**Why it's wrong:** satisfies a traceability matrix entry ("AC X.Y.Z covered") while exercising zero production behavior. Will not fail if the production code is deleted.

**Right pattern:** every test must call at least one function/method from the production codebase AND assert on its output.

**How Quinn checks:** grep test files for `expect\(true\)\.toBe\(true\)\|assert True\|assert 1 == 1`. For any test whose `describe`/`it` mentions an AC, verify the test body imports from the production source.

---

### AP-TEST-2 — Self-grading test (test signs its own input + computes its own oracle)

**Pattern:** A test that uses the same code path under test to generate both the input AND the expected output.

Examples:
- Webhook test signs a payload with `crypto.createHmac(...)` using the SAME library/format the production verifier uses, then verifies via that verifier. Passes whether or not the verifier matches real provider behavior.
- A serialization roundtrip test that calls `serialize(x)` then `deserialize(s)` and asserts equality — passes even if `serialize` and `deserialize` are both inverses of each other but neither matches the wire format.

**Why it's wrong:** the test grades the system against itself, not against an external truth. AI coders favor this pattern because it always passes.

**Right pattern:**
- Use a captured real example from the external system (a recorded webhook from the provider's docs, a fixture sample from a real wire trace).
- Or call an independent library/spec implementation to generate the oracle.

**How Quinn checks:** for any test exercising a serializer / deserializer / signer / verifier pair, verify the test fixture is sourced from outside the production codebase (a hardcoded captured payload, a vendor's example, etc.) — NOT generated by the same module.

---

### AP-TEST-3 — Tests inject language builtins instead of real library exceptions

**Pattern (Python especially):**

Production code:
```python
try:
    await redis.get(key)
except ConnectionError as exc:    # this is builtins.ConnectionError
    raise MemoryConnectionError(...) from exc
```

Test:
```python
mock.get = AsyncMock(side_effect=ConnectionError("refused"))  # also builtins
with pytest.raises(MemoryConnectionError):
    await store.get_session(...)
```

Test passes. Production breaks: `redis.exceptions.ConnectionError` does NOT inherit from `builtins.ConnectionError`. Same for `psycopg.OperationalError`, `requests.exceptions.ConnectionError`, etc.

**Why it's wrong:** the production try/except will catch a different exception class than the one tested. The wrapping is silent dead code under real failures.

**Right pattern:**
- Production: `from redis.exceptions import ConnectionError as RedisConnectionError; except RedisConnectionError: ...`
- Test: inject the SAME exception class the library actually raises, not its builtin namesake.

**How Quinn checks:** for any try/except block catching `ConnectionError`, `TimeoutError`, `OperationalError`, or similar generic names — verify (1) the import is from the relevant library, not stdlib, and (2) the test uses the library's class. This is the C3 finding from 2026-05-11.

---

### AP-TEST-4 — Catch-all `except Exception` in error-wrapping path

**Pattern:** After 1-2 specific exception classes, a `except Exception:` clause wraps "everything else" as a generic error.

**Why it's wrong:** swallows `asyncio.CancelledError` (on older Python), `KeyboardInterrupt` subclasses, AND any programming bug (`AttributeError`, `TypeError`) introduced later. Bugs hide as "generic infra error."

**Right pattern:** explicitly enumerate the expected error classes. Let unexpected ones propagate.

**How Quinn checks:** grep for `except Exception` in the diff. Each occurrence requires a justification — if there isn't one in a comment, it's a finding.

---

## Multi-tenant / boundary anti-patterns

### AP-TENANT-1 — Service method takes a resource id but no tenant id, with a comment claiming "the repo enforces it"

**Pattern:**

```ts
class FooService {
  // Comment: "tenant scoping is enforced at the repository layer"
  async resolve(id: string, update: Update) {
    const item = await this.repo.findById(id);  // tenant id NOT passed
    ...
  }
}
```

**Why it's wrong:** if any one implementation of the repo port forgets the tenant clause (or worse, the in-memory test impl doesn't enforce it at all), tenant-A's caller can mutate tenant-B's data by guessing the id. The comment lies — the service is the wrong layer to outsource a security invariant from.

**Right pattern:** thread `tenantId` (or whatever the isolation boundary is) through every service method that accesses tenant-scoped data. Assert `loaded.tenantId === args.tenantId` after the load. Make the repo port REQUIRE `tenantId` as a parameter on `findById` / `update` / `delete` — fail at the type system, not at convention.

**How Quinn checks:** for any service whose model has a `tenantId` (or `orgId` / `accountId`) field, verify EVERY mutator method on the service takes that id as a parameter.

---

### AP-INPUT-1 — Public boundary accepts string/object input without schema validation

**Pattern:** a service method or HTTP handler accepts `input: SomeType` where `SomeType` has fields like `pushedAt: string` or `reviewDate: string` — and the method body uses them directly (lexicographic compare, date arithmetic, DB writes) without parsing or validating.

**Why it's wrong:** caller passes `pushedAt: "today"` → service compares `reviewDate < "today"` lexicographically → garbage behavior. Empty strings, malformed ISO, wrong timezone — all silent failure modes.

**Right pattern:** Zod (TS) / Pydantic (Python) schema parse at the top of every public method. Reject malformed inputs with typed error before any business logic runs.

**How Quinn checks:** for any exported function / service method taking an object with string fields named like `*Date`, `*At`, `*Id`, `*Email`, `*Url` — verify there is a schema parse at the top, NOT just TypeScript typing (TypeScript types vanish at runtime).

---

## Key-design anti-patterns

### AP-KEY-1 — Composite key built by string-joining user-controlled values

**Pattern:** `f"prefix:{tenant_id}:{user_id}:{skill_id}"` where any component might legitimately contain `:`.

**Why it's wrong:** federated SSO `user_id` values like `oidc:alice@example.com` collapse the namespace. `(tenant=t, user=oidc:alice, skill=foo)` collides with `(tenant=t, user=oidc, skill=alice:foo)`. Cross-user data exposure.

**Right pattern:** URL-encode each component, OR explicitly reject `:` (or whatever separator) in each component at the validator, OR use a structured key (JSON blob, hash).

---

## Commit-message / scope anti-patterns

### AP-COMMIT-1 — Commit title says "X complete" while body admits X is partial

**Pattern:** Title: `fix(db): add missing source_uri column to ontology_version table`. Body: `Note: After this migration, allergen tests still fail because...`

**Why it's wrong:** session-handoff trust depends on commit titles meaning what they say. The next agent reading `git log --oneline` doesn't see the body and thinks the work landed.

**How Quinn checks:** parse commit body for phrases like "still fail", "still need", "TODO", "did not yet", "next session". If found, the commit title must explicitly say "partial" / "WIP" / "(N of M)" or the commit is a finding.

---

### AP-COMMIT-2 — Scope drift: commit touches files outside its stated subject

**Pattern:** A commit titled `Core-25f: Postpone Stack — Story 10.6` also adds an entire new `packages/strategy/` directory with 450 LOC of unrelated code.

**Why it's wrong:** reviewers tracing Story 10.6 acceptance miss the stowaway. The hidden code ships un-reviewed. AI coders are prone to this because they "fix the failing tests" by importing whatever they need, and the imports drag in whole packages.

**How Quinn checks:** `git show --stat <sha>` — file paths should all be under directories related to the commit's stated subject. Cross-package additions in a single commit are a finding unless the commit message explicitly enumerates them.

---

### AP-COMMIT-3 — "All tests pass" claim as evidence of correctness

**Pattern:** commit body contains `Full suite: N/N pass` or `tests: all green` as the primary evidence for a feature claim.

**Why it's wrong:** when the same agent writes both the feature AND its tests, "all tests pass" is the floor, not the ceiling. AP-TEST-1, AP-TEST-2, and AP-TEST-3 are all consistent with "all tests pass." See C3 incident 2026-05-11: 337/337 passed while the headline feature was silently broken.

**How Quinn checks:** "all tests pass" is acknowledged but given LOW evidentiary weight. Quinn must independently identify at least ONE test that injects a real external value (library exception class, captured wire payload, etc.) — not a synthetic generated by the same module.

---

## Secrets anti-patterns

### AP-SECRET-1 — Real provider keys committed under "test only" justification

**Pattern:** `process.env.STRIPE_SECRET_KEY = 'sk_test_51STwc30...'` in a test-setup file, with a comment "safe for CI" or "test key only."

**Why it's wrong:** even Stripe TEST keys identify the account, can call live test-mode APIs, pollute the dashboard, and leak if the repo is cloned to attacker-controlled infra. There is no "safe to commit" secret.

**Right pattern:** test-setup files use `sk_test_dummy_*` placeholders. Real keys live in CI secret store. Pre-commit gitleaks scan blocks commits that match real-key shapes.

**How Quinn checks:** grep diff for `sk_test_`, `sk_live_`, `sk-ant-`, `sk-or-v1-`, `pk_live_`, `pk_test_`, `whsec_`, `xoxb-`, `xoxa-`, `ghp_`, `github_pat_`, and PEM `-----BEGIN PRIVATE KEY-----`. Any hit is a finding. (gitleaks is the production guard; Quinn is the secondary.)

---

### AP-TEST-5 — Journey-level coverage gap (UI surfaces without end-to-end flow tests)

**Pattern:** A story ships a UI surface (page, dialog, multi-step form) whose test suite covers rendering, button states, and individual interactions — but no integration test exercises the full user journey end-to-end (form entry → submission → confirmation gate → API call → UI update).

**Why it's wrong:** Individual component tests validate pieces in isolation. When the same agent writes both feature and tests, the connective tissue between steps (callback chains, state propagation across view transitions, stale closures in `useCallback` dependency arrays) goes untested. The Crispi-app-2x20.9 incident (2026-05-12) shipped a ProfileManagementPage where `handleConfirmConstraints` never called `submitProfile` — the profile name was silently lost at the gate transition. Individual tests for the form, the gate, and the page all passed. The P0 bug was invisible because no test exercised the full Journey-1 flow: create profile → add hard constraint → gate appears → confirm → profile submitted.

**Right pattern:**
- For any story that ships a UI surface named in the UX design spec (e.g., `_bmad-output/planning-artifacts/ux-design-specification.md`), an integration test MUST exist for each user journey the surface participates in.
- The test must exercise the full flow: user input → intermediate state transitions → final outcome (API call, navigation, state change).
- Individual component tests (rendering, button states, a11y) are necessary but NOT sufficient.

**How Quinn checks:**
1. Read the story spec's acceptance criteria. Identify any that describe a multi-step user flow (look for: "user creates X → Y appears → user confirms → Z happens").
2. Search the test files for the story. For each multi-step AC, verify an integration test exists that exercises the full flow, not just individual steps.
3. If the story references a UX design spec journey (e.g., "Journey 1", "Journey 4"), verify at least one test is named or described with that journey identifier.
4. Missing journey-level tests are P0 findings (the 2x20.9 incident proved that component-level coverage creates false confidence in broken flows).

**Incident:** Crispi-app-2x20.9 — ProfileManagementPage Journey-1 flow broken. Component tests passed; no integration test existed. Quinn checkpoint reported "0 P0/P1" while the primary user flow was non-functional.

---

## How to extend this file

When a new AI-coder failure mode shows up in a code review:

1. Add a section under the right category (Crypto / Test-quality / Multi-tenant / Key-design / Commit / Secrets / new category).
2. Use the same shape: **Pattern**, **Why it's wrong**, **Right pattern**, **How Quinn checks**.
3. Cite the original incident in `dev-team-work-loop/CODE-REVIEW-*.md` so future readers can see the real example.
4. Reference the new AP-XXX code in Phase 10c's checklist (if it warrants explicit per-file enforcement).
