---
name: express-error-handler
description: Diagnose and fix Express.js error handling issues across all apps (FlowInCash, Crispi, MicroApps)
version: 1.0.0
tags: [express, error-handling, node, typescript]
---

# Express Error Handler

Use this skill when an Express app returns 500 errors, crashes on unhandled rejections,
or logs error stack traces.

## Applies To

- FlowInCash (`/media/bob/I/AI_Projects/FlowInCash`)
- Crispi-app (`/media/bob/I/AI_Projects/Crispi-app`)
- FliC-MicroApps (`/media/bob/I/AI_Projects/FliC-MicroApps`)
- Crispi-MicroApps (`/media/bob/I/AI_Projects/Crispi-MicroApps`)

## Diagnosis Steps

1. **Read the error log** — extract the stack trace and HTTP status code
2. **Classify the error:**
   - `TypeError` / `ReferenceError` → code bug, likely missing null check
   - `ECONNREFUSED` / `ETIMEDOUT` → downstream service (DB, Plaid, AWS) is down
   - `ValidationError` / `ZodError` → bad input from client
   - `ENOMEM` / `EMFILE` → resource exhaustion
3. **Locate the handler** — search `src/routes/` for the failing endpoint
4. **Check the middleware chain** — errors may be swallowed before reaching the error handler

## Fix Patterns

### Missing async error propagation
```typescript
// BAD — unhandled promise rejection
router.get('/accounts', async (req, res) => {
  const data = await fetchAccounts(); // throws, not caught
  res.json(data);
});

// GOOD — wrap or use express-async-errors
router.get('/accounts', async (req, res, next) => {
  try {
    const data = await fetchAccounts();
    res.json(data);
  } catch (err) {
    next(err);
  }
});
```

### Error handler not last in middleware chain
```typescript
app.use('/api', routes);
app.use(errorHandler); // Must be LAST
```

### Leaking internal errors to clients
```typescript
// BAD
res.status(500).json({ error: err.message, stack: err.stack });

// GOOD
res.status(500).json({ error: 'Internal server error', requestId: req.id });
logger.error({ err, requestId: req.id, path: req.path });
```

## Validation

1. Run `npm test` in the affected project
2. Trigger the failing request to confirm the fix
3. Check that error logs show structured output, no raw stack traces to client
