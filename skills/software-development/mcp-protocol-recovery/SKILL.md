---
name: mcp-protocol-recovery
description: Recover MCP servers when they fail to respond, lose connection, or return protocol errors
version: 1.0.0
tags: [mcp, chatgpt, microapps, protocol, recovery]
---

# MCP Protocol Recovery

Use this skill when any MicroApp MCP server fails to start, loses connection to
ChatGPT, returns protocol errors, or stops responding to tool calls.

## Applies To

- FliC-MicroApps (`/media/bob/I/AI_Projects/FliC-MicroApps`) — budget-builder, goal-tracker, traffic-light
- Crispi-MicroApps (`/media/bob/I/AI_Projects/Crispi-MicroApps`) — all 5 apps

All use: `createMcpServer().addTool().build()` from `@flowincash/mcp-tools`
Protocol: stdio JSON-RPC over stdin/stdout

## Diagnosis Steps

1. **Check if server starts:** `cd <app-dir> && node dist/index.js`
2. **Check build is current:** `npm run build` — stale dist/ is the #1 cause
3. **Check mcp-tools symlink:**
   ```bash
   ls -la node_modules/@flowincash/mcp-tools
   # Must point to /media/bob/I/AI_Projects/FlowInCash/packages/mcp-tools
   ```
4. **Check mcp-tools is built:** `ls .../FlowInCash/packages/mcp-tools/dist/`
5. **Protocol errors** — check for stdout pollution (breaks JSON-RPC framing)

## Common Fixes

### stdout pollution (most common)
```typescript
// BAD — breaks MCP protocol
console.log('Starting server...');
// GOOD — use stderr
console.error('Starting server...');
```

### Broken symlink after npm install
```bash
mkdir -p node_modules/@flowincash
ln -sf /media/bob/I/AI_Projects/FlowInCash/packages/mcp-tools node_modules/@flowincash/mcp-tools
```

### goal-tracker "goals disappeared"
In-memory Map — state lost on restart. Expected behavior, not a bug.

## Validation

1. `npm run prepare:chatgpt` (build + full test suite)
2. `npm run mcp:inspect` — interactive MCP inspector UI
3. Verify all tools appear and respond before deploying
