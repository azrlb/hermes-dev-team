## 19. Phantom npm Package Shadows Node.js Built-in

**Symptom:** `Error: Failed to resolve entry for package "https"`. Vite/Vitest
can't resolve `import * as https from 'https'` even though it's a Node.js
built-in. Multiple test files fail with zero tests run — the error happens at
module resolution time, not test execution.

**Cause:** A transitive npm dependency has a package with the same name as a
Node.js built-in (e.g., `https@1.0.0` — a dummy package from `pptxgenjs@4.0.1`).
Vite's resolver finds the npm `package.json` first and tries to resolve its
`"main"` field. If the referenced file doesn't exist, or has browser-only
exports, resolution fails. Node.js built-ins (`https`, `fs`, `path`, `crypto`)
are normally resolved by Node's module system, but Vite intercepts before
Node.js gets a chance.

**How to diagnose:**
```bash
# Check if an npm package shadows a builtin
ls node_modules/https/package.json 2>/dev/null && echo "SHADOW EXISTS"
npm ls https 2>/dev/null | head -5  # shows which dep pulled it in
```

**Fix — add alias in vitest.config.ts:**
```typescript
resolve: {
  alias: {
    // Prevent pptxgenjs's phantom 'https' npm package from shadowing Node.js built-in
    'https': 'node:https',
    // ... other aliases
  },
},
```

**Why `node:https` works:** The `node:` protocol forces Vite to resolve through
Node.js's built-in module loader, bypassing `node_modules` entirely. The npm
package can't shadow what Vite never looks for.

**Which builtins are at risk:** Any Node.js builtin that has an npm package
with the same name. Common offenders: `https`, `http`, `dns`, `net`, `tls`,
`stream`, `util`, `events`, `assert`, `buffer`, `querystring`, `url`.
Safe (no npm collisions): `fs`, `path`, `crypto`, `os`, `child_process`.

**Why `crypto`, `fs`, `path` tests don't fail:** These builtins don't have
popular npm packages with the same name (or the npm packages have valid
`index.js` files). `https` is the most common shadow because of `pptxgenjs`.

**Pattern:** When 5+ test files suddenly fail with "Failed to resolve entry
for package X" and X is a Node.js builtin, check `node_modules/X/package.json`
before assuming it's a test code issue.
