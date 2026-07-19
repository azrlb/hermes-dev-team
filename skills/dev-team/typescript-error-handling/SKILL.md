---
name: typescript-error-handling
description: Guidelines for handling TypeScript errors in brownfield projects, particularly focusing on test file fixes and systemic approaches to reducing error counts.
---

# TypeScript Error Handling in Brownfield Projects

When working on brownfield projects with existing type checking issues, follow these guidelines:

## THINK BEFORE ACTING (MANDATORY)

Before ANY fix, action, or change — pause and answer these questions:

1. **What is the ROOT CAUSE?** (not just the symptom)
2. **What is the MATH?** (display sizes, scale factors, dimensions, costs)
3. **What is the CONTEXT?** (where does this output appear? what is the display environment?)
4. **Have I VERIFIED?** (check the output BEFORE showing it to the user)

If you cannot answer all four, STOP and investigate before acting. Speed is not the goal — getting it RIGHT the first time is. Every quick fix that fails wastes the user time and trust.


## Priority Approach
1. **Production types are source of truth** - Always conform test fixtures to production types, never loosen production types
2. **Fix in order of risk** - Priority order:
   - JR1.1: production non-billing (~22 errors) - LOW RISK
   - JR1.2: production billing (~22 errors) - HIGHER RISK
   - JR1.3: test fixtures heavy clusters (~138 errors)
   - JR1.4: test fixtures remaining (~116 errors)

## Common Error Patterns to Fix

### TS2349: `done` Callback Typing (most common in integration tests — 50+ errors per file)

**Symptom:** `This expression is not callable.` on `done()` calls in `it('test', (done) => { ... })`

**Root cause:** Vitest's `done` callback parameter is untyped. TypeScript infers it as `unknown`.

**Fix:** Add explicit type annotation to the `done` parameter:
```typescript
// WRONG
it('should do something', (done) => { done(); });

// CORRECT — type as variadic function to support done() and done(err)
it('should do something', (done: (...args: any[]) => void) => { done(); });
```

**Bulk fix:** `sed -i 's/(done)/(done: (...args: any[]) => void)/g' <file>`

**Scope:** `agui.integration.test.ts` had 51 TS2349 errors, ALL from untyped `done`.

### TS2345: Auth Mock Casting with NormalizedProcedure

**Symptom:** `Argument of type '...' is not assignable to parameter of type 'NormalizedProcedure<...>'` on `vi.spyOn(authModule, 'authenticate').mockImplementation(...)`

**Root cause:** Vitest's `spyOn` infers mock type from the module export. The callback doesn't match `NormalizedProcedure`.

**Fix:** Cast the entire `vi.spyOn()` result to `any` — NOT the callback:
```typescript
// WRONG — casting callback doesn't help
vi.spyOn(authModule, 'authenticate').mockImplementation((req, res, next) => { ... }) as any;

// CORRECT — cast the spy object
(vi.spyOn(authModule, 'authenticate') as any).mockImplementation((req, res, next) => { ... });
```

### TS2339: Axios Instance Mock Casting

**Symptom:** `Property 'mockResolvedValue' does not exist on type '...'` on `axiosInstance.get.mockResolvedValue(...)`

**Root cause:** Axios instance methods are typed as actual methods, not `vi.fn()` mocks.

**Fix:** Cast the method to `any`:
```typescript
// WRONG
axiosInstance.get.mockResolvedValue({ data: mockResponse });

// CORRECT
(axiosInstance.get as any).mockResolvedValue({ data: mockResponse });
(axiosInstance.post as any).mockResolvedValue({ data: mockResponse });
```

**Bulk fix:** `sed -i 's/axiosInstance\.get\.mock/(axiosInstance.get as any).mock/g' <file>`

### TS2339: `never` Type Narrowing Bypass

**Symptom:** `Property 'X' does not exist on type 'never'` on variables assigned inside callbacks.

**Root cause:** TypeScript narrows a variable to `never` when the assignment seems impossible (callback type mismatch).

**Fix:** Change variable type to `any`:
```typescript
// WRONG — TS narrows to never after assignment
let receivedEvent: WebhookPayload | null = null;
service.registerHandler('thread.created', async (event) => {
  receivedEvent = event;  // TS thinks impossible
});

// CORRECT
let receivedEvent: any = null;
```

### TS2322: `Record<string, unknown>` Property Access

**Symptom:** `Type 'unknown' is not assignable to type 'string'` when accessing properties on `Record<string, unknown>`.

**Root cause:** Helper functions return `Record<string, unknown>`, so all properties are `unknown`.

**Fix:** Cast properties: `String(existingBug.title)` or `existingBug.title as string`

### TS18048: Null Guard After `toBeDefined()`

**Symptom:** `'insertCall' is possibly 'undefined'` even after `expect(insertCall).toBeDefined()`.

**Root cause:** TypeScript doesn't narrow types through Vitest matchers.

**Fix:** Non-null assertion: `expect(insertCall![1]).toContain(...)`

### TS2353/TS2322: BugCategory Value Mismatch

**Symptom:** `'backend' does not exist in type 'Partial<Record<BugCategory, string>>'`

**Root cause:** Test fixtures use old category values removed from the type union.

**Fix:** Map old values: `'backend'` → `'api'`, `'frontend'` → `'ui'`. Import types from `types.ts`, not the service file.

### TS2540: Cannot assign to read-only property
- **Issue**: Assigning to read-only properties like `request.path`
- **Fix**: Remove the assignment entirely, as these properties are handled by the framework
- **Pattern**: Remove lines like `mockRequest.path = '/path';`

### TS2322: Type mismatch (number vs string)
- **Issue**: Assigning numeric values where strings are expected
- **Fix**: Cast values or use appropriate types
- **Pattern**: Convert `10.0` to `'10.0'` where needed

### TS2345: Argument type mismatch (most common in test files)
- **Issue**: Mock objects don't fully satisfy service interface constructors
- **Fix**: Cast mock at call site: `mockVariable as any`
- **Pattern**: Test mocks are partial implementations — `as any` at constructor call preserves mock type for assertions

### TS2339: Property does not exist on type
- **Issue**: Accessing removed/renamed properties, or accessing `mockResolvedValue` on untyped axios methods
- **Fix**: For removed properties — cast to any or update to current property name. For axios — add `: any` type annotation on the axios instance variable
- **Pattern**: Two sub-patterns: (1) property was removed from type, (2) mock method not recognized because type is too specific

### TS2353: `user` property on Express Request mock (very common in auth tests)

**Symptom:** `Object literal may only specify known properties, and 'user' does not exist in type 'Partial<Request>'`

**Root cause:** Express `Request` type doesn't include a `user` property (it's added by auth middleware at runtime). Tests that set `mockRequest = { user: someUser }` fail because `Partial<Request>` doesn't have `user`.

**Fix:** Change the mockRequest declaration from `Partial<Request>` to `any`:
```typescript
// WRONG — Partial<Request> doesn't have 'user'
let mockRequest: Partial<Request>;
mockRequest = { user: mockUser };  // TS2353

// CORRECT
let mockRequest: any;
mockRequest = { user: mockUser };  // works
```

**Scope:** AuthController.test.ts (5 errors), TellerOnboarding.test.ts (3 errors), security.test.ts (2 errors) — any test file that mocks authenticated requests.

**Why `as any` on the assignment doesn't work:** TypeScript checks the object literal against the variable's type at assignment time. Casting the right side (`{ user: ... } as any`) works but is less clean than changing the variable type.

### TS-V2.1: Native Mobile Kotlin Version Alignment (`NoClassDefFoundError`)

**Symptom:** Standalone release `.apk` compiles cleanly and installs onto mobile devices, but flashes the splash screen and crashes immediately upon launch back to the phone homescreen. Under `adb logcat`, you see:
`java.lang.NoClassDefFoundError: Failed resolution of: Lexpo/modules/kotlin/types/AnyTypeCache;`

**Cause:** Multi-dependency version mismatch (mismatching `expo` vs `expo-asset` packaging parameters across React Native upgrades).

**Fix:** Align structural native SDK layers using the auto-fix alignment tool:
```bash
npx expo install --fix
cd android && ./gradlew clean && ./gradlew assembleRelease
```

### TS-V2.2: Native Component Entry Mismatch (Invariant Error)

**Symptom:** React Native release app exits instantly upon loading. `adb logcat` reports:
`com.facebook.react.common.JavascriptException: Invariant Violation: "main" has not been registered.`

**Cause:** Android package wrapper `MainActivity.kt` boots native segment `"main"`, but the Javascript `index.js` entry point registers your project name under `package.json`'s variable `appName` (e.g. `"flowincash-mobile"`).

**Fix:** Hardcode/align the component registry string directly matching native parameters inside `index.js`:
```javascript
AppRegistry.registerComponent('main', () => App);
```

### TS-V2.3: Cross-TestSuite Cache Leaks (Database Connection Pool Deadlock)

**Symptom:** Following successful integration or e2e test execution, consecutive developer login attempts on standard servers return persistent database connection warnings: `Database pool not initialized`.

**Cause:** Test environments invoke a shared `await closeDatabase()` utility on test teardown, which leaks and forcefully terminates the active connection pool of separate running servers (like port `3000` or Vite), leaving ports listening but connections dead.

**Fix:** Fully flush listening processes and restart:
```bash
kill -9 $(lsof -t -i:5173 -i:5174 -i:3000 2>/dev/null) 2>/dev/null || true
npm run dev:full
```

### TS2739: Missing properties from interface (User, Purchase, etc.)

**Symptom:** `Type '{ id: number; email: string; name: string; }' is missing the following properties from type 'User': firstName, lastName, preferences, createdAt, updatedAt`

**Root cause:** Test fixtures use old/incomplete object shapes that don't match current production interfaces.

**Fix:** Add the missing fields to the mock object. Use `as const` on string literal union values:
```typescript
const mockUser = {
  id: '1',
  email: 'user@example.com',
  firstName: 'Test',
  lastName: 'User',
  preferences: {
    spendingMode: 'think_over' as const,
    delayPeriodHours: 24,
    notificationSettings: { emailEnabled: true, pushEnabled: true, smsEnabled: false, dailyReviewTime: '09:00', weeklyReportEnabled: true },
    autoTransferEnabled: false,
    riskTolerance: 'moderate' as const
  },
  createdAt: new Date(),
  updatedAt: new Date()
};
```

**Why `as const`:** Without it, `'think_over'` is inferred as `string`, not `'fast_loose' | 'think_over'`. The `as const` narrows the literal type to match the union.

### TS18048: Property is possibly 'undefined' (mockRequest.query/params)

**Symptom:** `'mockRequest.query' is possibly 'undefined'` when accessing properties on Express request mocks.

**Root cause:** `Partial<Request>` makes all properties optional (`T | undefined`).

**Fix:** Same as TS2353 above — change mockRequest type to `any`. Or add non-null assertions (`mockRequest.query!.search`).

### TS2322: `string` not assignable to `{ word: string; severity: KeywordSeverity }` (KeywordDetection config)

**Symptom:** Test passes `['test']` where `Array<{ word: string; severity: KeywordSeverity }>` is expected.

**Fix:** Wrap strings in objects: `[{ word: 'test', severity: 'medium' as const }]`

### TS2322: `'completed'` not assignable to `'categorizing'` (narrow array type)

**Symptom:** Array inferred as narrow type from first element, then second element with different literal fails.

**Fix:** Widen the array type: `const arr: Array<{ status: string; ... }> = [...]`
- **Issue**: `Array.find()` returns `T | undefined`, test accesses without null check
- **Fix**: Non-null assertion: `variable!.property` or `variable![index]`
- **Pattern**: Use `!` when you know the find will succeed (test controls the data)

### TS2305: Module has no exported member
- **Issue**: Type was renamed but test imports old name
- **Fix**: Import with alias: `import type { NewName as OldName } from '...'`
- **Pattern**: Common after refactoring — check the actual export name in the source module

### TS1378: Top-level await not allowed
- **Issue**: tsconfig uses `module: commonjs` but vitest test uses top-level `await import()`
- **Fix**: `// @ts-expect-error vitest supports top-level await in ESM mode`
- **Pattern**: vitest handles ESM regardless of tsconfig — only `tsc --noEmit` complains

### TS2304: Cannot find name 'fail'
- **Issue**: `fail()` is a Jest global but not available in vitest
- **Fix**: `throw new Error('Expected error to be thrown')`
- **Pattern**: Jest API differences between jest and vitest

### Vitest: vi.mock doesn't override class singletons
- **Issue**: Code exports `export const thing = new Thing()` (singleton). Test uses `vi.mock('./module', () => ({ thing: mockThing }))` but production code still gets the real singleton.
- **Root cause**: `vi.mock` replaces the module namespace, but if the production code accesses the singleton via `thing.purchases.postpone.list()` (property chain), the mock object must have the EXACT same property shape. Also, `vi.mock` hoists to top of file — if the factory creates objects inline, they can't reference variables declared later.
- **Fix**: Declare the mock function in outer scope BEFORE `vi.mock`, then reference it inside the factory:
  ```typescript
  const mockList = vi.fn().mockResolvedValue([]);
  vi.mock('../../core-client', () => ({
    coreClient: {
      purchases: {
        postpone: {
          list: (...args: any[]) => mockList(...args),
        },
      },
    },
  }));
  ```
  Then in `beforeEach`: `vi.clearAllMocks(); mockList.mockResolvedValue([]);`
- **Alternative**: If the singleton is truly unmockable, delete the stale tests — they test a mock, not the real code. Check if passing tests already cover the same code paths.
- **Pattern**: Common in brownfield projects where DI was removed in favor of module-level singletons (e.g., `coreClient`, `subscriptionServiceInstance`). Tests written during the DI era set `(action as any).someService = mock` which no longer works.

### TS7016: Could not find a declaration file for module (dynamic imports)
- **Issue**: Dynamic `import('library')` for packages without bundled type declarations (e.g., pdfkit, some older npm packages)
- **Fix**: Add `// @ts-ignore` before the import statement:
  ```typescript
  // @ts-ignore — library has no bundled type declarations
  const Library = (await import('library-name')).default;
  ```
- **Alternative**: Create a `src/@types/<library>.d.ts` with `declare module 'library-name' { ... }` for more type safety
- **Pattern**: Common when using dynamic imports to avoid hard dependency at module load time. The `// @ts-ignore` is acceptable because the import itself works at runtime — only the type checker complains.

### TS2769: No overload matches this call (union return types from dynamic imports)
- **Issue**: Libraries like `pptxgenjs` have `write()` methods that return `Promise<string | ArrayBuffer | Blob | Uint8Array>` — a union type. `Buffer.from()` doesn't accept the full union, so TypeScript rejects it even with `as ArrayBuffer`.
- **Fix**: Cast to `any` at the call site:
  ```typescript
  const result = await library.write({ outputType: 'arraybuffer' });
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return Buffer.from(result as any);
  ```
- **Why `as any` works here**: The runtime type IS an ArrayBuffer (we specified `outputType: 'arraybuffer'`), but TypeScript's return type is the full union. The cast is safe because we control the input parameter.
- **Pattern**: Any time a library method returns a discriminated union based on an input parameter, TypeScript can't narrow the return type. `as any` is the pragmatic fix.

### TS2459: Module declares locally but not exported
- **Issue**: Importing a type that exists in the module but isn't in its export list
- **Fix**: Import from the file that actually exports it (often `types.ts`)
- **Pattern**: Types move between files during refactoring — check the actual export location

### TS2308: Barrel Export Name Conflicts (adding new services to index.ts)

**Symptom:** `error TS2308: Module './NewService' has already exported a member named 'X'. Consider explicitly re-exporting to resolve the ambiguity.`

**Root cause:** Two service files in the same barrel directory both export an interface/type with the same name (e.g. `Obligation`). When the barrel `index.ts` does `export * from './ServiceA'` and `export * from './ServiceB'`, TypeScript detects the ambiguous re-export.

**Fix:** Rename the new type to be more specific — prefix with the service domain. E.g. `Obligation` → `TieredObligation`. The barrel export (`export * from './TieredObligationService'`) then re-exports the new name without conflict.

**Verification:** After adding an `export *` line to barrel index.ts, run `npx tsc --noEmit 2>&1 | grep TS2308` to catch conflicts early.

**Pitfall:** The error reports the *conflicting* module (e.g. `JobPrioritizationService`), not your new file. Don't try to fix the existing service — rename yours.

**Prevention:** Before adding a new service to a barrel, grep all existing services in that directory for the type names you plan to export:
```bash
grep -rn "export.*interface\|export.*type " src/services/integration/ | grep -v index.ts
```

## Key Principles
1. **Production types are source of truth** - Always conform test fixtures to production types, never loosen production types
2. **Maintain existing tests** - Preserve behavioral contracts while fixing types
3. **Systematic reduction** - Focus on high-frequency error patterns to maximize impact quickly
4. **Source files first** - Fix source file errors before test file errors (source errors often cascade into test errors)
## Workflow

### TS2307: Cannot find module (dead-code stubs)
- **Issue**: Import references a module that was planned but never implemented
- **Fix**: Create a minimal stub file that satisfies the import:
  ```typescript
  // src/models/ForecastSnapshot.ts
  export interface ForecastSnapshotData { id?: string; user_id: string; /* ... */ }
  export class ForecastSnapshot {
    static async create(_data: ForecastSnapshotData): Promise<ForecastSnapshotData> {
      throw new Error('Not implemented');
    }
    static async findAll(_opts: { where?: { user_id: string } }): Promise<ForecastSnapshotData[]> {
      return [];
    }
    static async destroy(_opts: { where?: { id: string }; id?: string }): Promise<number> {
      return 0;
    }
  }
  ```
- **Pattern**: Match the API surface used by importing code (grep for usage before writing stubs). Return sensible defaults (empty arrays, throw "not implemented"). This is NOT dead code deletion — it's preserving planned code paths while satisfying the type checker.

### Source-File Error Triage (50+ source errors)
When source files (not just test files) have type errors, fix in this order:

1. **Missing type exports** (TS2305) — Add the missing type/enum to the source module. Often a `SubscriptionTier` union type or interface that was used in routes but never exported.
2. **Missing static methods** (TS2339 on `typeof Service`) — Routes call `ServiceClass.method()` as static, but the class only has instance methods. Add static wrappers that instantiate internally:
   ```typescript
   static async getSubscriptionStatus(userId: string) {
     const service = new SubscriptionService();
     return service.getUserTier(userId);
   }
   ```
3. **Express params casting** (TS2345: `string | string[]`) — Express `ParamsDictionary` values are `string | string[]`. Fix: `const id = req.params.id as string;`
4. **Null-guard decrypt results** (TS2345: `string | null`) — `encryptionService.decrypt()` returns `string | null`. Add: `if (!result) continue;` or `throw new Error('...')`
5. **Interface expansion** (TS2353: property not in type) — Add missing properties to the interface (e.g., `tellerTokens` to `OnboardingOptions`, new plan types to `StripePriceKey`)

### Batch Error Fixing (large error counts)

1. **Count errors:** `npx tsc --noEmit 2>&1 | grep "error TS" | wc -l`
2. **Group by file:** `npx tsc --noEmit 2>&1 | grep "error TS" | sed 's/(.*//' | sort | uniq -c | sort -rn`
3. **Fix biggest files first** — most errors per fix effort
4. **Use `as any` liberally in test files** — strict typing in tests is lower priority than getting the suite green
5. **Verify after each batch:** `npx tsc --noEmit 2>&1 | grep "error TS" | wc -l`
6. **For files with 1-5 errors:** fix inline with `execute_code` + `patch` tool
7. **For files with 10+ errors:** delegate to subagent, then verify afterward (agents can introduce regressions)

### Parallel Runtime + Type Fixes

When fixing both runtime failures and type errors:
1. Fix runtime failures FIRST (they block test execution)
2. Run `npx vitest run` to confirm all tests pass
3. THEN fix type errors (they block commits but not test execution)
4. Run `npx tsc --noEmit` to confirm 0 errors
5. Final: run both to confirm nothing broke

### TS2322: `id: number` not assignable to `id: string` (interface field type change)

**Symptom:** `Type 'number' is not assignable to type 'string'` on `id: 1` inside Purchase or similar objects.

**Root cause:** Production interface changed `id` from `number` to `string` (e.g., `Purchase.id: string`), but test fixtures still use numeric literals.

**Fix:** Change numeric id values to string literals:
```typescript
// WRONG
const purchase: Purchase = { id: 1, ... };
// CORRECT
const purchase: Purchase = { id: '1', ... };
```

**Scope:** AlexaVoicePurchase.integration.test.ts had 10 errors from this pattern. Every Purchase object in the test used numeric `id`.

### TS2820: Wrong case in string literal union

**Symptom:** `Type '"GREEN"' is not assignable to type '"red" | "yellow" | "green"'. Did you mean '"green"'?`

**Root cause:** Test uses uppercase string literal (`'GREEN'`) but the production type expects lowercase (`'green'`).

**Fix:** Match the exact case:
```typescript
// WRONG
decision: 'GREEN'
// CORRECT
decision: 'green'
```

**Pitfall:** Some APIs normalize case at runtime (e.g., traffic light engine maps `'GREEN'` → `'green'`), so the test passes at runtime but fails at compile time. The fix is to use the type-correct value.

### TS2322: MockInstance type mismatch on vi.spyOn() assignments

**Symptom:** `Type 'MockInstance<(userId: string) => Promise<LinkTokenResult>>' is not assignable to type 'MockInstance<(this: unknown, ...args: unknown[]) => unknown>'`

**Root cause:** `vi.spyOn(Service.prototype, 'method').mockResolvedValue(...)` infers a specific MockInstance type from the method signature, but the variable it's assigned to has a generic `MockInstance` type (e.g., from `ReturnType<typeof vi.spyOn>`).

**Fix:** Cast the entire spy assignment to `any`:
```typescript
// WRONG — specific MockInstance doesn't match generic variable type
createLinkTokenSpy = vi.spyOn(PlaidIntegrationService.prototype, 'createLinkToken').mockResolvedValue({...});

// CORRECT
createLinkTokenSpy = vi.spyOn(PlaidIntegrationService.prototype, 'createLinkToken').mockResolvedValue({...}) as any;
```

**Scope:** onboarding.integration.test.ts had 10 errors from this pattern. All `vi.spyOn().mockResolvedValue()` assignments needed `as any`.

### TS2345: Constructor argument count mismatch

**Symptom:** `Expected 0-2 arguments, but got 3` on a constructor call.

**Root cause:** Test passes more arguments than the constructor accepts. The constructor may have been refactored to accept fewer parameters.

**Fix:** Remove the extra argument or cast the whole call:
```typescript
// WRONG — constructor only takes 2 params
new PurchaseQueueAction(mockStreaming, mockInterceptionService, mockPurchaseRepo)
// CORRECT — remove extra arg
new PurchaseQueueAction(mockStreaming, mockPurchaseRepo)
```

### TS2740: Missing Mock properties (replacing vi.fn() with plain function)

**Symptom:** `Type '() => Promise<...>' is missing the following properties from type 'Mock<Procedure>': getMockName, mockName, mock, mockClear, and 14 more.`

**Root cause:** Test replaces a `vi.fn()` mock with a plain async function, losing all Mock utility methods.

**Fix:** Cast the replacement to `Mock` or `any`:
```typescript
// WRONG
mockAnalysisWithAlternatives.calculateImpact = () => Promise.resolve({...});
// CORRECT
mockAnalysisWithAlternatives.calculateImpact = vi.fn().mockResolvedValue({...}) as any;
// OR
(mockAnalysisWithAlternatives as any).calculateImpact = () => Promise.resolve({...});
```

### TS2353: `merchant` not in Purchase type (renamed property)

**Symptom:** `Object literal may only specify known properties, and 'merchant' does not exist in type 'Purchase'`

**Root cause:** Production interface renamed `merchant` to `merchantName`.

**Fix:** Use the current property name:
```typescript
// WRONG
const purchase: Purchase = { merchant: 'Amazon', ... };
// CORRECT
const purchase: Purchase = { merchantName: 'Amazon', ... };
```

**Prevention:** Always check the current interface before writing test fixtures: `grep -n "interface Purchase" src/models/Purchase.ts`

### TS2741: Missing required properties on interface (status, separator, etc.)

**Symptom:** `Property 'status' is missing in type '{ id: string; amount: number; ... }' but required in type 'Purchase'`

**Root cause:** Test fixtures use old/incomplete object shapes that don't match current production interfaces. Production added required fields (e.g., `status` on Purchase, `separator` on BankCSVFormat, `transactionCount` on CSVImportResult).

**Fix:** Add the missing required fields to the test fixture:
```typescript
// WRONG — missing required 'status' field
const purchase: Purchase = { id: '1', merchantName: 'Amazon', ... };
// CORRECT
const purchase: Purchase = { id: '1', merchantName: 'Amazon', status: 'pending', ... };
```

**Bulk detection:** When a type error says "Property X is missing in type Y but required in type Z", grep the test file for the object literal and add the missing field. Common missing fields: `status` (Purchase), `separator` (BankCSVFormat), `transactionCount` (CSVImportResult).

### TS2353: `isPending`/`isRecurring` not in Purchase type (removed properties)

**Symptom:** `Object literal may only specify known properties, and 'isPending' does not exist in type 'Purchase'`

**Root cause:** Test fixtures use properties that were removed from the production interface. `isPending` and `isRecurring` were boolean flags on Purchase that no longer exist.

**Fix:** Remove the obsolete properties from the test fixture:
```typescript
// WRONG — isPending was removed from Purchase interface
const purchase: Purchase = { id: '1', merchantName: 'Amazon', isPending: false, ... };
// CORRECT
const purchase: Purchase = { id: '1', merchantName: 'Amazon', ... };
```

**Detection:** If `sed -i '/isPending:/d'` and `sed -i '/isRecurring:/d'` fix the errors, the properties were simply removed from the interface. Do NOT add them back — the production code no longer uses them.

### TS2339: Property does not exist on SpendingPatternAnalysis

**Symptom:** `Property 'insights' does not exist on type 'SpendingPatternAnalysis'`

**Root cause:** Test accesses a property that was removed or renamed in the interface. `SpendingPatternAnalysis` has `recommendations` but not `insights`.

**Fix:** Use the correct property name or cast:
```typescript
// WRONG
expect(result.analysis.insights).toBeDefined();
// CORRECT — use the actual property
expect(result.analysis.recommendations).toBeDefined();
// OR cast if the property exists at runtime but not in types
expect((result.analysis as any).insights).toBeDefined();
```

### TS2322: `null` not assignable to `ParamsDictionary | undefined`

**Symptom:** `Type 'null' is not assignable to type 'ParamsDictionary | undefined'` when setting `params: null` in an Express mock.

**Root cause:** Express `Request.params` is `ParamsDictionary | undefined`, not `null`.

**Fix:** Cast the mock object as `any`:
```typescript
// WRONG
mockRequest = { body: null, query: undefined, params: null };
// CORRECT
mockRequest = { body: null, query: undefined, params: null } as any;
```

## Pitfalls

- **`patch` tool fuzzy matching fails with repeated code patterns.** When a file has the same code pattern repeated (e.g., `const mockUser = { id: 1, email: 'user@example.com', name: 'Test User' }` appearing 3+ times), the `patch` tool can't disambiguate and may match the wrong occurrence or refuse to patch. Fix strategies: (1) Use more unique surrounding context in the old_string. (2) Use `replace_all=true` if the fix is identical for all occurrences. (3) Fall back to `terminal` with `sed` or `python3` for targeted edits. (4) For files with 5+ repeated patterns, read the whole file first, then use `write_file` to rewrite the affected sections. AuthController.test.ts required 4 separate patch attempts because `const mockUser = { id: 1, email: 'user@example.com', name: 'Test User' }` appeared 3 times with identical surrounding code.

- **Parallel subagents for TS error fixing cause file conflicts.** Dispatching
  multiple subagents to fix different files simultaneously leads to silent reverts
  when agents touch overlapping files. Fix sequentially or ensure DISJOINT file
  sets per agent. Verify error count decreases monotonically after all agents
  complete — if it increased, agents conflicted. See bead-execution skill
  for the full pitfall description.

- **`npx tsc --noEmit` times out on large codebases.** Projects with
  200+ TS files (FlowInCash, Crispi) can take 3-5 minutes for a full
  typecheck. The default terminal timeout (120s) will kill it. Three
  workarounds, in order of preference:
  1. **Background run:** `terminal(command="npx tsc --noEmit",
     background=true, notify_on_complete=true, timeout=300)` then
     `process(action='poll')` to get results when done.
  2. **Targeted scope:** `npx tsc --noEmit src/api/` to check only the
     directory you're working on. Cuts time proportionally.
  3. **Error-only output:** `npx tsc --noEmit 2>&1 | grep "error TS" |
     head -50` to extract just the error lines (still needs the full
     compile time, but output is manageable).
  Do NOT keep retrying the same command — the timeout is a real
  compile time issue, not a transient failure.