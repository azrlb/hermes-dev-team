# Cross-Repo Service Migration (Personal → Core)

When a bead says "Move X from Personal to Core", the work is NOT just copying
the file. Core packages have infrastructure constraints that Personal doesn't.

## DI QueryFn Pattern

Core services do NOT import `query` from `../database/client`. Instead, they
accept a `QueryFn` via constructor injection:

```typescript
export type QueryFn = (
  text: string,
  params?: unknown[],
) => Promise<{ rows: Record<string, unknown>[]; rowCount: number }>;

export class MyService {
  private queryFn: QueryFn;
  constructor(queryFn: QueryFn) {
    this.queryFn = queryFn;
  }
  async doWork(userId: string) {
    const result = await this.queryFn('SELECT ... WHERE user_id = $1', [userId]);
    // ...
  }
}
```

Tests pass `vi.fn()` as the query function — no `vi.mock('../../../database/client')`.

## Infrastructure Checklist (BEFORE writing code)

When adding a service to an existing Core package or creating a new package,
update ALL of these or infrastructure tests will fail:

1. **`packages/<pkg>/package.json`** — Add `@flowincash/<dep>` to `dependencies`
   if the new service imports from another Core package
2. **`packages/<pkg>/tsconfig.json`** — Add `"path": "../<dep>"` to `references`
   if the new service imports from another Core package
3. **`vitest.workspace.ts`** — Add alias `'@flowincash/<dep>': path.resolve(...)` to the
   package's `resolve.alias` block so vitest can resolve cross-package imports
4. **`tests/scripts/vertical-core-usage.test.ts`** — If the new service has
   financial calculation patterns (class names ending in Detector/Engine/
   Evaluator/Calculator, or financial keywords), add the package to
   `CORE_FINANCIAL_PACKAGES` or the test will flag it as a violation
5. **Contract snapshots** — Run `npx vitest run --project contracts --update`
   after adding new exports to any package's index.ts

## Test Pattern for Migrated Services

```typescript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { MyService, type QueryFn } from '../my-service';

describe('MyService', () => {
  let mockQuery: QueryFn;
  let service: MyService;

  beforeEach(() => {
    vi.clearAllMocks();
    mockQuery = vi.fn();
    service = new MyService(mockQuery);
  });

  it('should do the thing', async () => {
    (mockQuery as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      rows: [{ id: '1', name: 'test' }],
      rowCount: 1,
    });
    const result = await service.doWork('user-123');
    expect(result).toBeDefined();
  });
});
```

Note the `(mockQuery as ReturnType<typeof vi.fn>)` cast — needed because
`QueryFn` is a function type but `vi.fn()` returns `Mock<...>`. The cast
lets you call `.mockResolvedValueOnce()`.

## Personal Side: What to Do

After migrating to Core, the Personal service files should be LEFT AS-IS
for backward compatibility (routes still import them). The route migration
to Core API is a separate bead. Do NOT delete Personal copies.

## When Bead Descriptions Are Vague

Bead descriptions like "Move X to Core's billing package" may not mention
infrastructure changes. Always check:
- Does the target package exist? (If not, check if a similar package exists)
- Does the package already depend on other Core packages? (Check package.json)
- Is the package in vitest workspace? (Check vitest.workspace.ts)
- Are there contract snapshot tests? (Check tests/contracts/)
