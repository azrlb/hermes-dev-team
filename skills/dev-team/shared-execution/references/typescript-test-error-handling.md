# TypeScript Error Handling in Test Files

This guide provides systematic approaches to resolving TypeScript errors in test files, particularly when handling large numbers of pre-existing type issues.

## Common Test File TypeScript Errors

### TS2349: vi.fn() callable issues
**Problem**: `vi.fn()` requires explicit typing in certain contexts
**Solution**: Add explicit typing: `vi.fn<any, any>()`

### TS2353: Object literal property violations
**Problem**: Object literals specify properties that don't exist in the target type
**Solution**: 
- Add proper type annotations to mock objects
- Use explicit casting when necessary: `as MockObjectType`

### TS2339: Property access errors
**Problem**: Accessing a property that doesn't exist on an object
**Solution**:
- Ensure property names match the type definition
- Add optional chaining: `obj?.property`
- Use type assertions carefully

### TS2322: Type assignment mismatches
**Problem**: Assigning incompatible types
**Solution**:
- Match types exactly or use casting
- Check that all expected properties exist
- Ensure return types match expectations

## Systematic Fix Approach

1. **Identify patterns** in existing errors across multiple files
2. **Fix groups** of related errors rather than individual ones
3. **Apply consistent solutions** across similar test files
4. **Verify with type checking** before committing: `npx tsc --noEmit`
5. **Document changes** for future reference

## Best Practices

- When adding `vi.fn()` mocks, always specify return types
- For complex object literals, define proper interfaces
- When mocking external APIs, ensure all necessary properties are included
- Maintain test functionality while fixing type issues
- Run all tests after making changes to ensure no regressions

## Common Fix Examples

```typescript
// Before (causes TS2349):
const mockFn = vi.fn();

// After (fixed):
const mockFn = vi.fn<any, any>();

// Before (causes TS2353):
const mockUser = {
  email: 'test@example.com',
  name: 'Test User',
  unknownProp: 'should not exist'  // Causes TS2353
};

// After (fixed):
const mockUser: User = {
  email: 'test@example.com',
  name: 'Test User'
};
```

## TS2532: Object possibly undefined on mock.calls array access

**Problem**: When accessing `mockQuery.mock.calls[0][1]` in tests, TypeScript infers
the second element as `T | undefined` because the function signature has optional
parameters (e.g., `query(text: string, values?: any[])` makes `calls[n][1]` → `any[] | undefined`).

**Symptom**: `TS2532: Object is possibly 'undefined'.` on lines like:
```typescript
expect(mockQuery.mock.calls[0][1][0]).toBe('expected');  // TS2532
expect(args[1][0]).toBe('expected');                      // TS2532
```

**Fix**: Add non-null assertion (`!`) after the optional index:
```typescript
expect(mockQuery.mock.calls[0][1]![0]).toBe('expected');  // ✓
expect(args[1]![0]).toBe('expected');                      // ✓
```

**Why this happens**: Even without `noUncheckedIndexedAccess`, vitest's `MockedFunction`
types preserve the optionality of parameters. `query(text, values?)` → `calls` typed as
`[string, any[]?][]` → `calls[0][1]` is `any[] | undefined`.

**Note**: This is distinct from the pg `QueryResultRow` leakage (TS2322). That affects
DB result fields; this affects mock call argument access in tests.

## pg QueryResultRow Type Leakage (TS2322 on DB result fields)

**Problem**: Even with generic type params, `pg`'s `query<T>()` can leak `string | null`
through `QueryResultRow`'s index signature. Fields from `result.rows[0]` appear as
`string | null` even after null guards.

**Symptoms**:
- `TS2322: Type 'string | null' is not assignable to type 'string'` on DB result fields
- Error persists after adding `if (!row.field) return null` guards

**Fix**: Cast the row: `const row = result.rows[0] as any;` then use `String(row.field)`
or `row.field as string`. Do NOT try to fix by changing the generic type parameter —
the leakage is in pg's type definitions.

## Mock Call Count Mismatch (Conditional DB calls)

**Problem**: When a service skips DB calls based on input (e.g., `if (externalId) { query() }`),
the test mock must match the ACTUAL call count for that specific input, not the "all branches" count.

**Symptom**: `Cannot read properties of undefined (reading 'id')` on `result.rows[0].id`
because the mock returns `undefined` for an unconsumed call.

**Example**: Service with conditional SELECT:
```typescript
// If externalId is set: 3 queries (qbo SELECT + name SELECT + INSERT)
// If externalId is NOT set: 2 queries (name SELECT + INSERT only)
if (material.source.externalId) {
  existing = await query('SELECT ... WHERE qbo_item_id = $1', [...]);
}
if (!existing) {
  existing = await query('SELECT ... WHERE name = $1', [...]);
}
```

**Fix**: Trace the code path for the specific test input and set up exactly the right
number of `mockResolvedValueOnce()` calls. Comment each mock with which branch it satisfies.