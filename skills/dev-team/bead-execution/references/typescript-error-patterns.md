# TypeScript Error Patterns (FlowInCash)

Collected from batch TypeScript error fixing sessions. These are pre-existing
type errors in test files — the tests still RUN, but `tsc --noEmit` reports them.

## Error Code Frequency (updated 2026-07-07, baseline 298→61→0)

| Code | Count | Category | Fix Pattern |
|------|-------|----------|-------------|
| TS2322 | 24+ | Type not assignable | Align types, cast `as any` |
| TS2345 | 9+ | Argument type mismatch | Cast mock args `as any` |
| TS2353 | 8+ | Unknown property on mock/Request | Cast mock objects `as any`, remove extra props |
| TS18048 | 6+ | Possibly undefined | Change `Partial<Request>` to `any`, add `!` |
| TS2339 | 4+ | Property doesn't exist | Cast to `any`, remove non-existent fields |
| TS2741 | 2+ | Missing required property | Add missing fields to mocks |
| TS2739 | 2+ | Missing required properties | Add missing fields, conform to interface |
| TS2305 | 1+ | No exported member | Fix import name, add export |
| TS2820 | 1 | Wrong case string literal | Fix literal case ('GREEN' → 'green') |

## Common Fix Patterns

### 0. Production Type Drift — Interface Changes Break Test Fixtures (TS2353/TS2739/TS2322)

**Symptom:** Test fixtures use old property names or missing required fields after production types evolve.

**Common drifts observed:**
- `merchant` → `merchantName` (Purchase interface rename)
- `status` field became required on Purchase
- `id: number` → `id: string` (Purchase, VoiceInteraction)
- `transactionId: number` → `transactionId: string`
- `Transaction` export removed → use `TransactionHistory`
- `BankCSVFormat` gained required `separator` field
- `CSVImportResult` gained required `transactionCount` field
- `TicketCategory` union lost `'spam'` → use `'security'` or `'other'`
- `SpendingPatternAnalysis` has `recommendations` not `insights`

**Fix:** Read the production interface, conform all test fixtures. NEVER loosen production types.

### 1. `done` Callback Typing (TS2349 — highest volume, 50+ errors per file)

**Symptom:** `This expression is not callable.` on `done()` in `it('test', (done) => { ... })`

**Fix:** Add type annotation to `done` parameter:
```typescript
it('should do something', (done: (...args: any[]) => void) => {
  done();      // works
  done(err);   // also works
});
```

**Bulk fix:** `sed -i 's/(done)/(done: (...args: any[]) => void)/g' <file>`

### 2. Auth Mock Casting with NormalizedProcedure (TS2345)

**Symptom:** `Argument of type '...' is not assignable to parameter of type 'NormalizedProcedure<...>'`

**Fix:** Cast the entire `vi.spyOn()` result to `any`:
```typescript
(vi.spyOn(authModule, 'authenticate') as any).mockImplementation((req, res, next) => { ... });
```

**Key:** Casting just the callback does NOT work. Must cast the spy object.

### 3. Axios Instance Mock Casting (TS2339)

**Symptom:** `Property 'mockResolvedValue' does not exist on type '...'`

**Fix:** Cast the method to `any`:
```typescript
(axiosInstance.get as any).mockResolvedValue({ data: mockResponse });
```

**Bulk fix:**
```bash
sed -i 's/axiosInstance\.get\.mock/(axiosInstance.get as any).mock/g' <file>
```

### 4. `never` Type Narrowing Bypass (TS2339)

**Symptom:** `Property 'X' does not exist on type 'never'`

**Fix:** Change variable type to `any`:
```typescript
let receivedEvent: any = null;  // instead of WebhookPayload | null
```

### 5. `Record<string, unknown>` Property Access (TS2322)

**Symptom:** `Type 'unknown' is not assignable to type 'string'`

**Fix:** Cast properties: `String(existingBug.title)` or `existingBug.title as string`

### 6. Null Guard After `toBeDefined()` (TS18048)

**Symptom:** `'insertCall' is possibly 'undefined'` after `expect(insertCall).toBeDefined()`

**Fix:** Non-null assertion: `expect(insertCall![1]).toContain(...)`

### 7. BugCategory Value Mismatch (TS2353/TS2322)

**Symptom:** `'backend' does not exist in type 'Partial<Record<BugCategory, string>>'`

**Fix:** Map old values: `'backend'` → `'api'`, `'frontend'` → `'ui'`

## Batch Fix Strategy

1. Fix production code first (real bugs, not type noise)
2. Group test files by error pattern (same fix applies to many files)
3. Work sequentially — parallel subagents cause file conflicts
4. Verify after each file: `npx tsc --noEmit 2>&1 | grep <filename> | wc -l`
5. Verify after each batch: `npx tsc --noEmit 2>&1 | wc -l` (count should decrease monotonically)
6. Commit per-file or per-pattern for atomic bisection

## Quick-Reference: FlowInCash Type Facts (2026-07-07)

| Type | Key Fields | Common Test Mistake |
|------|-----------|-------------------|
| `Purchase` | `id: string`, `merchantName: string`, `status: required`, `amount: number` | Uses `id: number`, `merchant`, missing `status` |
| `User` | `firstName`, `lastName`, `preferences`, `createdAt`, `updatedAt` | Uses `name` instead of firstName/lastName |
| `VoiceInteraction` | `id: number`, `transactionId?: string` | Uses `transactionId: number` |
| `TicketCategory` | `'bug' \| 'feature_request' \| 'billing' \| 'support_question' \| 'bank_connection' \| 'security' \| 'other'` | Uses `'spam'` (not valid) |
| `BankCSVFormat` | requires `separator: string` | Missing separator |
| `CSVImportResult` | requires `transactionCount: number` | Missing transactionCount |
| `SpendingPatternAnalysis` | has `recommendations`, NOT `insights` | Accesses `.insights` |
| `TrafficLightDecision` | lowercase: `'green' \| 'yellow' \| 'red'` | Uses `'GREEN'` |
| Express `Request` | no `user` property on base type | Tests add `user` to `Partial<Request>` |
| `index.ts` exports | `FlowInCashServer`, not `app` | Tests import `{ app }` |
| vitest | no `fail` export | Needs custom `function fail(msg): never` |

## Priority Order for Bulk Fixing

1. `done` callback typing (TS2349) — highest volume, sed-replaceable
2. Mock casting (TS2339/TS2349 on mocks) — second highest volume
3. Null guards (TS18048) — mechanical `!` additions
4. Type mismatches (TS2322/TS2345) — requires reading function signatures
5. Missing properties (TS2741/TS2353) — requires understanding the type definition
6. Read-only assignments (TS2540) — requires restructuring the code
