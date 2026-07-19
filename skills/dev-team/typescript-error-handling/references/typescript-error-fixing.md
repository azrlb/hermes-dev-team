# TypeScript Error Fixing Patterns (Detailed Reference)

Detailed fix patterns for batch TypeScript error fixing. See SKILL.md for overview.

## `done` Callback Typing (TS2349)

**Impact:** 50+ errors in a single file (agui.integration.test.ts: 51 errors)

**Root cause:** Vitest's `done` callback in `it('test', (done) => { ... })` is untyped.

**Fix:**
```typescript
// Before
it('should stream events', (done) => {
  done();
});

// After
it('should stream events', (done: (...args: any[]) => void) => {
  done();      // works
  done(err);   // also works for error callbacks
});
```

**Bulk sed:** `sed -i 's/(done)/(done: (...args: any[]) => void)/g' <file>`

**Why variadic:** Some tests call `done(err)` with an error argument, so `() => void` is too narrow.

## Auth Mock Casting (TS2345)

**Impact:** 2 errors in agui.integration.test.ts

**Root cause:** `vi.spyOn(authModule, 'authenticate')` returns a typed spy. The `NormalizedProcedure` wrapper type doesn't match the mock callback.

**Fix:**
```typescript
// Before
vi.spyOn(authModule, 'authenticate').mockImplementation((req, res, next) => { ... });

// After — cast the spy, NOT the callback
(vi.spyOn(authModule, 'authenticate') as any).mockImplementation((req, res, next) => { ... });
```

**Key insight:** Casting the callback `(fn) as any` does NOT work. The type error is on the `mockImplementation` argument, not the callback itself. Must cast the spy object.

## Axios Mock Casting (TS2339)

**Impact:** 25 errors in core-client.test.ts

**Root cause:** `const axiosInstance = (await import('axios')).default.create()` types methods as actual axios methods, not `vi.fn()` mocks.

**Fix:**
```typescript
// Before
axiosInstance.get.mockResolvedValue({ data: mockResponse });

// After
(axiosInstance.get as any).mockResolvedValue({ data: mockResponse });
(axiosInstance.post as any).mockResolvedValue({ data: mockResponse });
(axiosInstance.delete as any).mockResolvedValue({ data: mockResponse });
```

**For .mock.calls:**
```typescript
// Before
const callHeaders = axiosInstance.get.mock.calls[0][1].headers;

// After
const callHeaders = (axiosInstance.get as any).mock.calls[0][1].headers;
```

**Bulk sed:**
```bash
sed -i 's/axiosInstance\.get\.mock/(axiosInstance.get as any).mock/g; \
        s/axiosInstance\.post\.mock/(axiosInstance.post as any).mock/g; \
        s/axiosInstance\.delete\.mock/(axiosInstance.delete as any).mock/g' <file>
```

## `never` Type Narrowing (TS2339)

**Impact:** 16 errors in WebhookHandlerService.test.ts

**Root cause:** TypeScript narrows a variable to `never` when it believes the assignment is impossible. Happens when callback parameter type doesn't match variable type.

**Example:**
```typescript
let receivedEvent: WebhookPayload | null = null;
service.registerHandler('thread.created', async (event) => {
  receivedEvent = event;  // TS thinks this type of event can't be assigned
});
expect(receivedEvent?.type).toBe('thread.created');  // Error: 'type' on 'never'
```

**Fix:** Change variable type to `any`:
```typescript
let receivedEvent: any = null;
// ... rest works
```

**Why `any` is correct here:** The variable is a test accumulator — it captures a value in a callback and asserts on it later. Strict typing adds no safety; the assertion validates the type.

## `Record<string, unknown>` Property Access (TS2322)

**Impact:** 2 errors in BugIngestionService.test.ts

**Root cause:** Helper functions like `createMockBugRow()` return `Record<string, unknown>`, so all properties are `unknown`.

**Fix:**
```typescript
const existingBug = createMockBugRow();  // Returns Record<string, unknown>

// Before
alertName: existingBug.title,  // Error: unknown → string

// After
alertName: String(existingBug.title),
description: String(existingBug.description),
```

**Alternative:** `existingBug.title as string` works too, but `String()` is safer (handles undefined).

## Null Guard After `toBeDefined()` (TS18048)

**Impact:** 8+ errors across multiple test files

**Root cause:** TypeScript doesn't narrow types through Vitest's `expect().toBeDefined()` assertion.

**Fix:**
```typescript
const insertCall = mock.mock.calls.find(
  (call: any[]) => call[0].includes('INSERT INTO bugs')
);
expect(insertCall).toBeDefined();
expect(insertCall[1]).toContain(...);  // Error: possibly undefined

// After
expect(insertCall![1]).toContain(...);  // Works
```

**Pattern:** Any variable checked with `toBeDefined()` or `not.toBeNull()` but then accessed immediately after needs `!`.

## BugCategory Value Mismatch (TS2353/TS2322)

**Impact:** 12 errors in BugIngestionService.test.ts

**Root cause:** Test fixtures use old category values (`'backend'`, `'frontend'`) that were removed from the `BugCategory` type union.

**Fix:**
```typescript
// Old values → New values
'backend'  → 'api'
'frontend' → 'ui'

// In config objects
defaultAssignees: { backend: 'dev-1' }  →  defaultAssignees: { api: 'dev-1' }

// In assertions
expect(result.category).toBe('backend')  →  expect(result.category).toBe('api')
```

**Rule:** Import types from `types.ts` (canonical source), not from the service file.

## Batch Fix Strategy

### Priority Order
1. `done` callback typing (TS2349) — highest volume, sed-replaceable
2. Mock casting (TS2339/TS2349 on mocks) — second highest volume
3. Null guards (TS18048) — mechanical `!` additions
4. Type mismatches (TS2322/TS2345) — requires reading function signatures
5. Missing properties (TS2741/TS2353) — requires understanding the type definition
6. Read-only assignments (TS2540) — requires restructuring the code

### Verification
```bash
# After each file
npx tsc --noEmit 2>&1 | grep "<filename>" | wc -l

# After each batch
npx tsc --noEmit 2>&1 | wc -l  # count should decrease monotonically
```

### Commit Strategy
- Commit per-file or per-pattern for atomic bisection
- Include error count in commit message: `(205→85 tsc errors)`
