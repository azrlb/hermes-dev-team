---
name: user-troubleshoot
description: Triage and resolve issues reported by beta users across FlowInCash and Crispi apps
version: 1.0.0
tags: [support, troubleshooting, users, beta]
---

# User Troubleshoot

Use this skill when Bob forwards a user-reported issue or monitoring detects user-facing errors.

## Triage — Classify Severity

- **P0 — Data loss/corruption:** Financial data wrong, transactions missing → Fix immediately, notify Bob on Telegram
- **P1 — Feature broken:** Can't log in, sync fails, evaluations wrong → Fix within session, file beads issue
- **P2 — Degraded experience:** Slow loading, UI glitch → File beads issue
- **P3 — Enhancement request:** → File beads issue with type=feature

## Diagnosis Steps

1. **Reproduce** — check backend logs, try the failing API endpoint or MCP tool locally
2. **Check recent deploys** — did this work before the last push?
3. **Check external services** — Plaid/AWS/DB responding?
4. **Check user data** — account/profile in unexpected state?

## Common Issues

| Symptom | Likely Cause | First Check |
|---------|-------------|-------------|
| "Balance is wrong" | Plaid sync stale | Last sync timestamp |
| "App won't load" | API server down | Express logs |
| "ChatGPT tool broken" | MCP server crashed | See mcp-protocol-recovery |
| "Goals disappeared" | goal-tracker restarted | Expected (in-memory) |
| "Can't sign in" | Auth token expired | Auth service logs |

## Response Protocol

When fixing: state the cause, what you'll change, which project. Run tests, commit.

When escalating to Bob: include what user reported, what you found, 2-3 possible causes ranked by likelihood. Never contact users directly — all communication goes through Bob.
