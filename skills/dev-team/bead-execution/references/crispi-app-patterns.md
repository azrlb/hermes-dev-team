# Crispi-App Codebase Patterns

Conventions specific to the Crispi-app project (AI-powered meal planning PWA).

## Route Addition Pattern

Adding a new Express route to Crispi follows a 3-step pattern:

1. **Create route file** at `src/server/routes/<name>Routes.ts`:
   ```typescript
   import { Router, Request, Response } from 'express';
   import { authenticateToken } from '../middleware/auth';
   import { chatRateLimit } from '../middleware/aiRateLimitMiddleware'; // for AI routes
   // or: import { standardRateLimiter } from '../middleware/rateLimiting'; // for standard routes

   const router = Router();
   router.use(standardRateLimiter); // or chatRateLimit for AI endpoints

   // Routes here...

   export default router;
   ```

2. **Register in `src/server/index.ts`**:
   - Add import after similar routes (e.g., after `mealPlanningRoutes`)
   - Add `app.use('/api/<path>', <name>Routes);` — mount path must not collide with existing routes
   - **Route registration order matters:** Stripe webhooks BEFORE `express.json()`, CSRF AFTER rate limiting

3. **Create test file** at `src/server/__tests__/<name>Routes.test.ts`:
   - Mock auth: `jest.mock('../middleware/auth', () => ({ authenticateToken: (req, _res, next) => { req.user = { id: 'user-123' }; next(); } }))`
   - Mock rate limiter: `jest.mock('../middleware/rateLimiting', () => ({ standardRateLimiter: (_req, _res, next) => next() }))`
   - Mock database: `jest.mock('../config/database', () => ({ db: (table) => ({ where: jest.fn().mockReturnThis(), first: jest.fn().mockResolvedValue(...) }) }))`
   - Use supertest: `import request from 'supertest'; import express from 'express';`
   - Create test app: `const app = express(); app.use(express.json()); app.use('/api/<path>', router);`

## Sidecar Proxy Pattern

Routes that proxy AI requests to the LivingApp Sidecar follow `agentChatRoutes.ts`:
- JWT signing with `SIDECAR_JWT_SECRET` env var
- 15-second timeout via `AbortController`
- POST to `${SIDECAR_URL}/chat` with userId, message, agentType, conversationId
- Response: `{ success, message, metadata }`
- **Testing requirement:** Must set `process.env.SIDECAR_JWT_SECRET` and `process.env.SIDECAR_URL` in test file or proxy throws before fetch is called (see test-failure-patterns.md #16)

## Database Patterns

- **ORM:** Knex.js exclusively — no TypeORM, Prisma, or Sequelize
- **Dev DB:** SQLite3 (`database/smart_meal_planner.db`)
- **Prod DB:** PostgreSQL (via `DB_CLIENT` env var)
- **Column naming:** snake_case in DB, camelCase in TypeScript
- **Query pattern:** `db('table').where({ col: val }).first()` — never `pg.Pool` directly
- **Migrations:** in `database/migrations/`, sequential prefix (001_) for older, timestamp for newer

## Middleware Stack Order (from `src/server/index.ts`)

1. Helmet (security headers)
2. CORS
3. Stripe webhooks (BEFORE express.json — needs raw body)
4. Express.json + urlencoded + cookieParser
5. Response time + request logger
6. Global rate limiter
7. AI usage tracker
8. CSRF protection
9. Route-specific middleware (auth, rate limiters)

## Response Format

Standard success: `{ success: true, data: T }`
Standard error: `{ success: false, error: string }` or `{ error: string }`
AI proxy: `{ success: boolean, message: string, metadata?: Record<string, unknown>, provider: 'sidecar' }`

## Testing Conventions

- **Framework:** Jest v29 with ts-jest
- **Test location:** `src/server/__tests__/` or colocated `__tests__/` dirs
- **Run single file:** `CI=true npx jest --testPathPattern=<filename>`
- **NEVER** `npm test` without `CI=true` (CRA/CRACO hangs in watch mode)
- **Global mocks:** DB and Redis auto-mocked via `src/server/__tests__/setup.ts`
- **AI APIs:** Never call real AI APIs in tests — use mocks at `src/server/__mocks__/`

## Feature Flag Pattern

Crispi uses feature flags for gradual rollouts (e.g., `SHOP_REDESIGN_ENABLED`, `PLANS_PAGE_CRISPI_SHIELD`, `ONBOARDING_CRISPI_SHIELD`).
- Flags are checked in route handlers and component render paths
- Deprecation beads remove the flag and legacy code after bake period
- **Never delete redirect routes** — users may have bookmarked legacy paths
