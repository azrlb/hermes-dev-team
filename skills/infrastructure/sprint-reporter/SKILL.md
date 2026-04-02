# Sprint Reporter

Generates sprint status summaries from Beads data. Reports via Telegram or console.

## Trigger

- **Telegram:** Bob sends `sprint status` or `sprint report`
- **Cron:** End of day summary (configurable)
- **On-demand:** After completing a batch of stories

## Steps

### 1. Gather Data

Run these bd commands to collect sprint state:

```
bd list --status=closed --json    → completed stories
bd list --status=in_progress --json → in-progress stories
bd list --status=open --json      → remaining stories
bd ready --json                   → unblocked and ready
```

### 2. Aggregate Metrics

From the collected data, calculate:

| Metric | Source |
|--------|--------|
| Stories completed | closed issues count |
| Stories in progress | in_progress issues count |
| Stories remaining | open issues count |
| Stories ready (unblocked) | bd ready count |
| Total cost | Sum metadata.cost_usd from closed issues |
| Average cost per story | total cost / completed count |
| Pass rate | Stories closed with "PASS" in reason / total attempted |
| Blocked stories | Issues with unresolved dependencies |
| Escalations | Issues with blocker metadata |

### 3. Format Report

**Telegram format:**

```
📊 Sprint Status Report

✅ Completed: {n} stories (${total_cost})
🔄 In Progress: {n}
📋 Ready: {n} (unblocked)
⏳ Remaining: {n}
🚫 Blocked: {n}

Avg cost: ${avg}/story | Pass rate: {pct}%

Recent completions:
- {id}: {title} ✅ ${cost}
- {id}: {title} ✅ ${cost}

Blocked:
- {id}: blocked by {dep_ids}

Next ready:
- {id}: {title} (P{priority})
```

### 4. Deliver

- If triggered via Telegram: reply in the Telegram conversation
- If triggered via cron: send to Bob's Telegram
- Always log the report to platform.db audit trail (action: sprint_report)

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SPRINT_REPORT_CRON` | `0 18 * * *` | Daily report time (6 PM) |

## Dependencies

- Beads CLI (`bd`) for issue queries
- Telegram for delivery
- platform.db for audit logging
