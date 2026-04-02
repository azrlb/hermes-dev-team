# Daily Summary

Operator briefing via Telegram. Summarizes the last 24 hours: errors detected, auto-fixes applied, stories completed, costs, health status, and action items.

## Trigger

- **Cron:** Daily at 8 AM (configurable via DAILY_SUMMARY_CRON)
- **Telegram:** Bob sends `daily summary` or `daily report`
- **On-demand:** After significant events (multiple escalations, budget threshold)

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `DAILY_SUMMARY_CRON` | `0 8 * * *` | When to send daily summary |
| `DAILY_SUMMARY_LOOKBACK_HOURS` | `24` | How far back to look |

## Steps

### 1. Gather 24-Hour Data

**From Beads:**
```
bd list --status=closed --json    → stories completed today
bd list --status=in_progress --json → currently running
bd list --status=open --json      → backlog
bd ready --json                   → ready for next
```

**From platform.db audit trail:**
- Errors detected (action: error_detected)
- Fixes applied (action: auto_fix_applied)
- Escalations (action: escalation_*)
- QA gate runs (action: qa_gate)
- Story checkpoints (action: story_checkpoint)
- Cost records (action: cost_record or from cost_records table)

**From health check:**
- Run health_check tool for current status

### 2. Format Summary

**Telegram message:**

```
☀️ Daily Summary — {date}

📊 Stories
  Completed: {n} (${total_cost})
  In Progress: {n}
  Ready: {n}
  Blocked: {n}

🔧 Operations
  Errors detected: {n}
  Auto-fixed: {n}
  Escalated to Bob: {n}
  Failed fixes: {n}

💰 Costs
  Today: ${today_total}
  Avg per story: ${avg}
  Budget remaining: ${remaining}

🏥 Health: {overall_status}
  Gateway: {status}
  Database: {status}
  Disk: {usage}%

{if action_items}
⚡ Action Items:
  - {blocked_story}: needs {what}
  - {escalation}: {summary}
{endif}

{if all_clear}
✅ All clear — nothing needs your attention.
{endif}
```

### 3. Deliver

- Send via Telegram to Bob
- Log to audit trail (action: daily_summary)

## Dependencies

- Beads CLI (`bd`)
- platform.db for audit trail queries
- health_check Pi tool (or run health checks directly)
- Telegram for delivery
