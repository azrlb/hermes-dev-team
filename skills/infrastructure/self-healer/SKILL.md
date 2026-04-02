# Self-Healer

Executes known fix actions autonomously per graduated autonomy. When error-monitor detects and classifies an issue, self-healer determines the appropriate response tier and either fixes it, plans a fix for Bob, or routes it to the dev pipeline.

## Trigger

- Called by `error-monitor` skill when an error is classified
- Called by `health_check` when a service fails its health probe
- Manual: Bob sends `heal {service}` or `fix {error_id}` via Telegram

## Input

Read from the error-monitor classification (passed as context or from Beads issue):
```json
{
  "error_id": "err_20260330_001",
  "service": "gateway-openrouter",
  "error_class": "INFRA | DEPENDENCY | RATE_LIMIT | OOM | AUTH | CODE_BUG",
  "severity": "critical | warning | info",
  "detail": "specific error message or symptom",
  "first_seen": "ISO timestamp",
  "occurrences": 3
}
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SELF_HEALER_ENABLED` | `true` | Master switch for self-healing |
| `APPROVALS_MODE` | `manual` | Graduated autonomy phase: `manual`, `smart`, or `off` |
| `MAX_AUTO_FIX_COST_USD` | `5.00` | Max monthly cost increase Hermes can approve autonomously (Phase 3 only) |
| `RAILWAY_TOKEN` | — | Railway API token for infrastructure ops |

## Response Tiers

### Tier 1: Auto-Fixable

Known fixes Hermes can apply without asking Bob. These are safe, idempotent, and have no cost implications.

| Issue | Fix Action | Verify |
|-------|------------|--------|
| Service down | `hermes gateway restart {service}`, `pm2 restart {process}`, Railway CLI `railway service restart` | health_check passes |
| Stale cache | Invalidate cache keys, restart cache service | Cached endpoint returns fresh data |
| Disk full | `docker system prune -f`, clear `/tmp`, rotate logs older than 7d | `df -h` shows >20% free |
| Missing npm module | `npm install` in service directory | `npm ls {module}` exits 0 |
| Stuck git repo | Remove stale lockfiles (`rm .git/index.lock`), `git pull` | `git status` clean |
| Railway service unhealthy | `railway service restart` via RAILWAY_TOKEN, volume resize if near capacity | Railway health check passes |
| Transient DNS/network failure | Wait 30s, retry up to 3 times with exponential backoff | Request succeeds |
| Rate limit (429) | Exponential backoff: 1s, 4s, 16s, 60s max. If persistent, rotate to backup endpoint if available | Request returns 200 |

**Tier 1 procedure:**
1. Log intent to audit trail
2. Check `APPROVALS_MODE` (see Graduated Autonomy below)
3. Apply the fix
4. Verify with health_check or targeted probe
5. If verified OK -> log success, notify via Telegram, invoke skill-creator to learn pattern
6. If verified FAIL -> bump to Tier 2

### Tier 2: Plannable

Issues Hermes understands but cannot fix alone. Hermes drafts a plain-English plan with options and presents it to Bob via Telegram.

**Key principle:** Write plans for a CREATOR, not an engineer. Step-by-step, plain English, with links and specific UI paths. Include cost implications. Present multiple options with tradeoffs.

#### OOM / Resource Exhaustion
```
Your Railway service {service} is running out of memory ({current_mb}MB used / {limit_mb}MB limit).

Option 1: Upgrade to Pro plan ($20/mo) — gives you 1GB+ per service
   -> Go to railway.com/project/{id}/settings -> Plan -> Upgrade

Option 2: I optimize the service (estimated ~2hrs of dev time, ${cost} budget)
   -> I'll profile memory usage and reduce allocations

Option 3: Split into two smaller services
   -> More complex but stays on current plan. I'll draft the architecture.

Reply with 1, 2, or 3 (or tell me something else).
```

#### API Key Expired
```
Your {provider} API key expired (last worked: {date}).

Steps:
1. Go to {provider_url}/keys
2. Click "Create new key"
3. Paste the key here and I'll update the config

(I cannot create API keys for you — only you have account access.)
```

#### SSL Certificate Expired
```
SSL cert for {domain} expired on {expiry_date}.

If Railway-managed domain:
  -> Check railway.com/project/{id}/settings -> Domains. Railway auto-renews — may just need a redeploy.

If custom domain:
  -> Renew at your registrar, then upload new cert or re-verify DNS.

Want me to trigger a Railway redeploy to see if that fixes it?
```

#### Database Corruption
```
{db_name} has integrity errors: {error_detail}

Option 1: I restore from last git backup (commit {sha}, {age} ago)
   -> You may lose up to {hours}h of audit data

Option 2: Check Railway for a volume snapshot
   -> Go to railway.com/project/{id}/volumes -> Snapshots

Option 3: I attempt a repair with sqlite3 .recover
   -> Non-destructive attempt, but no guarantee

Reply with 1, 2, or 3.
```

#### Billing / Account Issue
```
Railway deployment failed with billing error: {error_detail}

I can't fix billing issues — you'll need to:
1. Go to railway.com/account/billing
2. Check your payment method and plan limits
3. Let me know when it's sorted and I'll redeploy
```

**Tier 2 procedure:**
1. Log intent to audit trail
2. Draft the plan using the templates above (adapt to specific error context)
3. Send plan to Bob via Telegram
4. Wait for Bob's response (or auto-apply in Phase 3 if cost < MAX_AUTO_FIX_COST_USD)
5. Execute Bob's chosen option
6. Verify fix worked
7. If verified OK -> log success, notify, invoke skill-creator
8. If verified FAIL -> Telegram to Bob with what happened and what to try next

### Tier 3: Code Bug

When error-monitor classifies the error as `CODE_BUG`, the fix requires code changes and goes through the dev pipeline.

**Procedure:**
1. Create a Beads issue with full error context:
   ```
   bd create --title "Bug: {error_summary}" --type=bug --priority=1
   ```
2. Attach to the issue: error logs, stack trace, affected service, reproduction steps, error frequency
3. The issue enters the Beads queue as a story for the Hermes-Dev pipeline
4. Work-loop picks it up -> tdd-coder fixes it -> Quinn validates
5. The fix loop is automatic. Bob is only involved if it escalates after 3 failed attempts (via escalation-handler)

**Tier 3 graduated behavior:**

| Phase | Behavior |
|-------|----------|
| `manual` | Create issue, Telegram Bob for approval before work-loop picks it up |
| `smart` | Auto-create issue, work-loop picks it up automatically |
| `off` | Auto-create issue, auto-attempt, notify Bob only on completion or escalation |

## Post-Fix Protocol

After EVERY fix attempt (all tiers):

1. **Verify** — Re-run health_check or re-check the specific error condition
2. **On success:**
   - Invoke `skill-creator` to learn the pattern for next time (promotes future Tier 2 fixes to Tier 1)
   - Audit log: `action: "self_heal_success"`, with fix type, duration, cost
   - Telegram: "{service} healed. Issue: {detail}. Fix: {action_taken}. Verified OK."
3. **On failure:**
   - Bump to next tier (Tier 1 fail -> Tier 2 plan, Tier 2 fail -> Telegram to Bob with full context)
   - Audit log: `action: "self_heal_failed"`, with fix type, what went wrong
   - Telegram: "{service} fix failed. Tried: {action_taken}. Bumping to {next_tier}."
4. **Always:** Write to audit trail in platform.db regardless of outcome

## Graduated Autonomy

| Phase | Tier 1 (Known Fix) | Tier 2 (Plannable) | Tier 3 (Code Bug) |
|-------|--------------------|--------------------|-------------------|
| Phase 1 (`manual`) | Ask Bob before applying | Present plan, wait for choice | Create issue, wait for approval |
| Phase 2 (`smart`) | Auto-apply known fixes, notify after | Present plan, wait for choice | Auto-create issue, work-loop picks up |
| Phase 3 (`off`) | Auto-apply, notify after | Auto-apply if monthly cost impact < `MAX_AUTO_FIX_COST_USD` | Auto-create issue, auto-attempt fix |

Phase transitions are controlled by Bob via Telegram (`set approvals {phase}`) or by updating the `APPROVALS_MODE` env var.

## Audit Trail

Log every self-heal action to platform.db:
```
action: "self_heal_{tier}_{outcome}"
target: {service}
detail: {
  error_id, error_class, severity,
  fix_action, fix_duration_ms,
  verified: true/false,
  escalated_to: "tier2" | "tier3" | "bob" | null,
  cost_impact_usd: 0.00
}
```

## Dependencies

- `error-monitor` skill (triggers self-healer with classified errors)
- `health_check` Pi tool (verify fixes)
- `skill-creator` skill (learn from successful fixes)
- `escalation-handler` skill (fallback when fixes fail)
- `telegram-dispatch` skill (notifications and Tier 2 plans to Bob)
- Railway CLI + `RAILWAY_TOKEN` (infrastructure ops)
- Beads CLI `bd` (create issues for Tier 3 code bugs)
- `pm2` / `docker` (service management)
