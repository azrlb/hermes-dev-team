# FlowInCash-Core Implementation Patterns

## QuickBooks SyncClient Architecture

When building features that need QBO API access, bridge the gap between `QuickBooksReadOnlyClient` (accessToken, realmId) and `QuickBooksSyncClient` (tenantId, realmId) by:

1. Extend raw interface in `client-types.ts`
2. Extend SyncClient in `sync-client.ts` via `#withFreshToken()`
3. Define narrow feature-specific interface (e.g., `CapabilityProbeClient`)

## QBO Export Path (Core-lxm.3)

The read-only client (`QuickBooksReadOnlyClient`) is deliberately separate from write operations (R14). For export:

1. Define `QuickBooksWriteClient` interface in `client-types.ts` (separate from read-only)
2. Create `QBOExportClient` in `export-client.ts` that delegates to the write client
3. Create `QBOExportAdapter` in ingest package that maps canonical → QBO payloads
4. Verticals implement the actual API calls; Core depends only on the interface

**Bucket → QBO mapping:**
- `ExpectedIncome` → Invoice (CustomerRef, TxnDate, Line with SalesItemLineDetail)
- `Obligation` → Bill (VendorRef, TxnDate, Line with AccountBasedExpenseLineDetail)
- `MaterialNeed` → Item (Name, Type, UnitPrice)

**Idempotency:** Track exported `sourceRef` values in `ExportIdempotencyTracker`. Re-exporting the same sourceRef returns `skipped_idempotent` without calling the write client.

## LeadTimeLearner Pattern (Core-lxm.5)

Mirrors `PaymentProbabilityEngine` exactly:
- Recency-weighted average (exponential decay, half-life 180 days)
- Cold-start defaults (14 days, 0.4 confidence)
- Per-vendor profiles with confidence scoring (0.4 → 0.95)
- Incremental learning via `learn()` batches
- Confidence = `min(0.95, max(default, countFactor * 0.6 + consistencyFactor * 0.4))`

## Contract Snapshot Updates

When adding exports to `@flowincash/common`, update snapshot:
```bash
npx vitest run --project contracts tests/contracts/common.contract.test.ts -u
```

## Pre-Existing Test Failures (Do NOT Investigate)

- `common/src/errors.ts(72,7)` — Record type mismatch
- `common/src/events.ts(46,18)` — Event payload type
- `common/src/migrations.ts(118,22)` — unknown vs number
- `test-harness/story-1-2` — JSONC parsing of tsconfig.base.json
- `test-harness/ts-project-references` — hermes imports audit without declaration
- `ingest/src/orchestrator.ts(167,28)` — readonly array push (pre-existing)

## Vitest Workspace Projects

Use `contracts` (src-resolved) for attestation, NOT `contracts-dist`.

## Implementation Workflow

1. Read AGENTS.md → bd list → bd show → read story spec
2. Implement → test (`npx vitest run --project {name}`) → snapshot update
3. Typecheck → commit → bd close → push → report

## Pitfalls

- Revert dist files after build: `git checkout -- packages/common/dist/`
- Client-types changes need index.ts export
- SyncClient needs import updates for new types
- Keep probe interfaces narrow
- **ReadonlyArray mutation:** If a function returns `ReadonlyArray<T>` and you need to push to it internally, declare the internal variable as `Array<T>` (mutable), not `ReadonlyArray<T>`. The `skipped` arrays in adapters are a recurring example — the return type is `ReadonlyArray` but the implementation builds with `push()`.
- **LSP false positives on TS18028/TS2802:** The LSP reports "Private identifiers are only available when targeting ES2015+" and "Map can only be iterated through with downlevelIteration" — but the actual tsconfig.base.json targets ES2022, which supports both. These are LSP cache issues, not real compilation errors. Trust `npx tsc --noEmit` over LSP red squiggles. If `tsc` passes, the code is fine.
- **Import paths for cross-package types:** QBO payload types (`QBOCreateInvoicePayload`, etc.) live in `@flowincash/quickbooks`, NOT `@flowincash/common`. When the ingest adapter needs QBO types, import from `@flowincash/quickbooks`.
- **`satisfies` vs `as` in test fixtures:** When defining test fixture objects with `satisfies`, TypeScript enforces strict structural matching — extra properties cause errors. Use `as Type` instead for test fixtures that may have additional properties not in the interface.
