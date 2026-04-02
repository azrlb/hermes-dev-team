---
name: purchase-evaluation
description: Debug and fix FlowInCash purchase decision queue and traffic-light evaluation system
version: 1.0.0
tags: [flowincash, finance, purchase-queue, traffic-light]
---

# Purchase Evaluation

Use this skill when the FlowInCash purchase queue or traffic-light MicroApp produces
incorrect evaluations, stalls, or returns unexpected Red/Yellow/Green signals.

## System Architecture

- **FlowInCash** (`/media/bob/I/AI_Projects/FlowInCash`)
  - `src/services/` — purchase queue coordination, forecasting engine
  - `src/models/` — purchase queue DB models
  - Evaluates against cash flow forecast, emergency fund, and goals
- **traffic-light** (`/media/bob/I/AI_Projects/FliC-MicroApps/traffic-light/`)
  - `evaluatePurchase` — Red/Yellow/Green signal
  - `checkEmergencyFund` — adequacy check
  - Stateless per-call, uses `@flowincash/mcp-tools`

## Diagnosis Steps

1. **Identify which system** — main app purchase queue or ChatGPT traffic-light?
2. **Check input data** — purchase amount, category, urgency, current balances
3. **Check for stale financial data** — if Plaid hasn't synced, evaluations use outdated balances (see plaid-sync-recovery skill)
4. **Trace the evaluation logic** in src/services/ or traffic-light/src/conversation/

## Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Wrong signal | Threshold constants don't match user situation | Check ratio constants in traffic-light/src/ |
| Queue stuck | Coordination service failed mid-evaluation | Check DB for stale `status='pending'` items |
| Main app and MicroApp disagree | By design — main app has full context, traffic-light is simplified | Not a bug |

## Validation

1. `npm test` in traffic-light (30 tests)
2. `npm run test:unit` in FlowInCash for purchase queue tests
3. Test with known safe, risky, and edge-case purchases
