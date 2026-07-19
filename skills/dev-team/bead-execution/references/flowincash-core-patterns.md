# FlowInCash-Core Codebase Patterns

Project-specific conventions for implementing beads in FlowInCash-Core.

## Business-Day Math

`addBusinessDays(date, N)` from `@flowincash/common` returns a **`Date` object**, not a string. Always format before use:

```typescript
import { addBusinessDays } from '@flowincash/common';

const raw = addBusinessDays('2026-07-14', -10);  // returns Date
const dateStr = raw.toISOString().slice(0, 10);  // '2026-06-30'
```

`businessDaysBetween(a, b)` takes strings and returns a number. These two functions have different input/output types — don't mix them up.

## Cashflow Package Patterns

### TieredLightEvaluator
- Located: `packages/cashflow/src/tiered-light-evaluator.ts`
- Class-based, evaluate() takes `TieredLightInput`, returns `TieredLightResult`
- Signal: 'green' | 'yellow' | 'red' (score thresholds: 60 green, 30 yellow)
- Default buffer: `obligation.amountCents × 1.1` (10% safety margin)
- Two-leg evaluation: expected + conservative balances, awareness verdict

### Obligation Types
- `TieredObligation` (cashflow): obligationId, description, amountCents, dueDate, kind
- `Obligation` (common/ingestion-models.ts): extends Sourced, same kind union
- Kind values: 'payroll' | 'rent' | 'debt' | 'tax' | 'material_po' | 'ap_bill' | 'discretionary'

### Backward Scheduler
- Located: `packages/planning/src/backward-scheduler.ts`
- `backwardSchedule(input)` → `ScheduledMilestone[]` with orderByDate and actByDate
- Uses `addBusinessDays` from common — same Date-object return type

### Package Dependencies
- `cashflow` depends on `common` only (not `planning`)
- To use backward-scheduler from cashflow, either add `planning` as a dependency or reimplement the date math with `addBusinessDays` from common

## Cross-Service Fix Location

When a bead describes a problem in Service A (e.g., the Python sidecar) but the
fix can be applied at the client boundary (e.g., TypeScript SidecarClient),
the client-level normalization is often the most practical approach. Pattern:

- **Information leaks via status codes** (e.g., 400 vs 403 revealing skill existence):
  normalize at the client boundary to a single status code. The sidecar is a
  separate repo/service — client-level defense is deployable immediately.
- **Response shape mismatches**: add normalization or adapter in the client layer
  rather than waiting for the upstream service to change.
- **Error enrichment**: wrap upstream errors with structured typed events
  (e.g., `SidecarPermissionDeniedError`) at the client boundary so downstream
  audit code gets typed data without depending on upstream changes.

Key files for FlowInCash-Core client boundary:
- `packages/sidecar-client/src/sidecar-client.ts` — HTTP transport + error handling
- `packages/hermes/src/middleware/hermes-proxy.ts` — Express proxy layer
- `packages/hermes/src/client.ts` — typed RPC wrapper

When the bead says "fix in the sidecar" but you can't modify the sidecar from
this repo, look for the client-layer interception point instead.

## Story Spec Location

When `docs/stories/Story-X.Y.md` doesn't exist, the bead DESCRIPTION (via `bd show <id>`) contains the full implementation spec including:
- WHAT to build
- WHY now
- CURRENT STATE (what exists)
- PLAN (numbered steps)
- ACCEPTANCE criteria
- DEPENDENCIES

Always check `bd show` before assuming the story spec is missing.

## Business Package Patterns (New — July 2026)

### QueryFn Dependency Injection
All services in `packages/business/` use DI with `QueryFn` — never import database clients directly:

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
}
```

### Unit Consistency Rule
**All monetary values must be in CENTS.** The database may store some values as dollars (NUMERIC(12,2)) — convert at the boundary:

```typescript
const payrollAmountDollars = Number(profile?.payrollAmount ?? 0);
const payrollAmountCents = Math.round(payrollAmountDollars * 100);
```

**PITFALL (beads_FlowInCash_Core-ovh):** Original code compared cents (cashAfter) to dollars (payrollAmount), producing wrong signals.

### Vitest Workspace Registration
New packages MUST be added to `vitest.workspace.ts` BEFORE the closing `];`:

```typescript
defineConfig({
  test: {
    name: 'business',
    globals: true,
    environment: 'node',
    include: ['packages/business/src/__tests__/**/*.test.ts'],
    isolate: false,
  },
  resolve: {
    alias: {
      '@flowincash/business': path.resolve(__dirname, './packages/business/src'),
      '@flowincash/auth': path.resolve(__dirname, './packages/auth/src'),
      '@flowincash/common': path.resolve(__dirname, './packages/common/src'),
    },
  },
}),
```

Run tests with: `npx vitest run --project business`

### Export Pattern
Use explicit named exports (not `export *`) when multiple packages export the same type name (e.g., `QueryFn`):

## Charts Package Patterns

### Plotly Figure Convention
- Located: `packages/charts/src/plotly.ts` (860+ lines)
- All chart functions return `PlotlyFigure { data: PlotlyTrace[], layout: PlotlyLayout }`
- No plotly.js runtime dependency — templates emit plain JSON objects for any renderer
- Base layout via `BASE_LAYOUT` constant (white bg, Inter font, standard margins)
- Colors via `FLOWINCASH_COLORS` and `TRAFFIC_LIGHT_COLORS` constants

### Empty State Pattern
Every chart function MUST handle empty data gracefully. Use `messageFigure(message, title?)` to return a figure with a centered annotation message telling the user what data they need:

```typescript
import { messageFigure } from './plotly';

export function forecastChart(result: ForecastResult): PlotlyFigure {
  if (result.periods.length === 0) {
    return messageFigure('Connect your bank account to see your cash flow forecast.', 'Cash Flow Forecast');
  }
  // ... normal chart logic
}
```

### Dashboard Assembly
- Located: `packages/charts/src/charts.ts`
- Composes individual plotly templates into dashboard objects (e.g., `CashFlowDashboard`, `HealthDashboard`)
- Each dashboard groups related charts for a full page view

### Testing
- Test file: `packages/charts/src/__tests__/plotly.test.ts` (70+ tests)
- Test pattern: mock data fixtures at top, `describe`/`it` per chart function
- Every chart function should have: happy path test + empty data test
- Run with: `npx vitest run --project charts`

### Export Pattern
- `packages/charts/src/index.ts` uses `export * from './plotly'` — all plotly functions auto-exported
- No need to add explicit exports when adding new functions to plotly.ts
