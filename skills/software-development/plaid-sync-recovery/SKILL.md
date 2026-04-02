---
name: plaid-sync-recovery
description: Diagnose and recover Plaid banking sync failures in FlowInCash
version: 1.0.0
tags: [plaid, banking, sync, flowincash, finance]
---

# Plaid Sync Recovery

Use this skill when FlowInCash bank account syncing fails, returns stale data,
or Plaid API calls return errors.

## Applies To

FlowInCash (`/media/bob/I/AI_Projects/FlowInCash`) — Banking service in src/services/

## Error Reference

| Plaid Error | Meaning | Action |
|-------------|---------|--------|
| `ITEM_LOGIN_REQUIRED` | Bank credentials expired | User must re-link via Plaid Link |
| `INSTITUTION_NOT_RESPONDING` | Bank API is down | Wait and retry (not our bug) |
| `RATE_LIMIT_EXCEEDED` | Too many API calls | Back off, check for polling loops |
| `TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION` | Data changed mid-sync | Retry full sync |
| `INVALID_ACCESS_TOKEN` | Token corrupted/revoked | Re-authenticate the item |

## Recovery Procedures

### Stale data (sync stopped)
1. Check if sync scheduler/cron is active
2. Trigger manual sync for affected user's items
3. Verify new transactions in DB
4. Check purchase evaluation queue — stale balances affect decisions

### Token expired (ITEM_LOGIN_REQUIRED)
1. Requires user action — must re-authenticate through Plaid Link
2. Notify Bob to reach out to user
3. Verify "Re-link account" UI prompt works

### Rate limiting
1. Check for accidental polling loops
2. Implement exponential backoff if missing
3. Dev environment has lower limits than production

## Downstream Impact

Failed sync affects: cash flow forecasting (stale balances), purchase evaluation (wrong signals), goal tracking (wrong progress), balance-based alerts (won't fire). Always check these after recovery.

## Validation

1. `npm test -- --grep plaid`
2. Verify last sync timestamp updated in DB
3. Confirm downstream services reflect new data
