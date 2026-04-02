# Error Monitor

Detects production errors via log drain, classifies them, and routes to self-healer or creates Beads issues. Goal: every production error gets a resolution path — auto-fix, issue creation, or documented log entry.

## Trigger

- **Cron:** Every 15 minutes (configurable via ERROR_MONITOR_CRON)
- **On-demand:** Telegram command `check errors` or called by other skills

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ERROR_MONITOR_CRON` | `*/15 * * * *` | How often to scan for errors |
| `ERROR_MONITOR_LOOKBACK_MIN` | `20` | Minutes of log history to scan (overlaps with previous window to avoid gaps) |

## Steps

### 1. Read Recent Errors

Use the `parse_log_drain` Pi tool to pull errors from the configured lookback window:
```
parse_log_drain --since={lookback_min}m --level=error,fatal --format=json
```

Output: array of error entries, each with `timestamp`, `service`, `message`, `stack_trace`, `request_id`.

If no errors found, log a clean scan to audit trail and exit.

### 2. Deduplicate

Group errors by normalized message (strip variable parts: IDs, timestamps, request-specific data). Each group becomes one detection event with a `count` and list of `sample_request_ids`.

### 3. Classify Each Error Group

Use the S2.2 error-classifier pattern to assign each error group a classification:

| Classification | Description |
|----------------|-------------|
| `transient_api` | Upstream API timeout, rate limit, temporary 5xx from third-party |
| `code_bug` | Application logic error, unhandled exception, type error |
| `infrastructure` | Disk full, OOM, database connection failure, DNS resolution |
| `user_triggered` | Bad input, auth failure, expected validation error |

The classifier also returns:
- `auto_fixable`: boolean — whether the self-healer has a known fix
- `severity`: `low`, `medium`, `high`, `critical`
- `fingerprint`: stable hash for recurring error detection

### 4. Check Recurring Error History

Query platform.db audit trail for each error fingerprint in the last 24 hours:
```sql
SELECT fingerprint, COUNT(*) as occurrences
FROM error_detections
WHERE fingerprint = {fingerprint}
  AND detected_at > datetime('now', '-24 hours')
GROUP BY fingerprint
```

If an error has occurred 3+ times in 24 hours, flag it as `recurring` — this forces Beads issue creation even if the error is auto-fixable.

### 5. Route by Classification

#### transient_api
- **Non-recurring:** Route to self-healer for auto-fix (retry with backoff, circuit breaker activation)
- **Recurring (3+ in 24h):** Auto-fix AND create Beads issue:
  ```
  bd create --type=bug \
    --title "Recurring transient error: {service} — {normalized_message}" \
    --description "Error seen {count} times in 24h. Auto-fix applied but pattern indicates upstream instability. Fingerprint: {fingerprint}. Sample stack: {stack_trace}" \
    --metadata '{"error_class":"transient_api","fingerprint":"{fingerprint}","occurrences_24h":{count},"auto_fixed":true}'
  ```
- Telegram (recurring only): "Recurring transient error in {service} ({count}x/24h). Beads issue {id} created. Auto-fix active."

#### code_bug
- **Always creates a Beads issue** — code bugs are never auto-fixed:
  ```
  bd create --type=bug \
    --title "Code bug: {service} — {normalized_message}" \
    --description "Classification: code_bug. Severity: {severity}. Count in window: {count}. Stack trace:\n{stack_trace}\n\nSample request IDs: {sample_request_ids}" \
    --metadata '{"error_class":"code_bug","fingerprint":"{fingerprint}","severity":"{severity}","service":"{service}"}'
  ```
- Telegram: "Code bug detected in {service}: {normalized_message}. Severity: {severity}. Beads issue {id} created for Hermes-Dev."

#### infrastructure
- **Auto-fixable:** Route to self-healer (e.g., restart service, clear disk, reconnect DB pool)
  - If fix succeeds: log to audit trail, no Beads issue unless recurring
  - If fix fails: create Beads issue + escalate via Telegram
- **Not auto-fixable:** Create Beads issue + plan + escalate:
  ```
  bd create --type=bug \
    --title "Infra issue: {service} — {normalized_message}" \
    --description "Infrastructure error not auto-fixable. Severity: {severity}. Detail: {message}\n\nSuggested action: {suggested_action}" \
    --metadata '{"error_class":"infrastructure","fingerprint":"{fingerprint}","severity":"{severity}","auto_fixable":false}'
  ```
- Telegram (not auto-fixable or fix failed): "Infra issue in {service}: {normalized_message}. {auto_fix_status}. Beads issue {id} created."

#### user_triggered
- **Log only** — no auto-fix, no Beads issue
- Record to audit trail for daily summary aggregation
- Exception: if a single user-triggered error type exceeds 50 occurrences in the window, create a Beads issue flagged as potential UX problem

## Audit Trail

Log every detection cycle to platform.db:
```
action: "error_monitor_scan"
detail: { scan_time, errors_found, classifications, actions_taken }
```

Log each individual error detection:
```
action: "error_detected"
target: {service}
detail: {
  fingerprint,
  classification,
  severity,
  count,
  action_taken: "auto_fix" | "beads_issue" | "log_only" | "escalated",
  beads_issue_id: {id} | null,
  auto_fix_result: "success" | "failed" | null
}
```

## Dependencies

- `parse_log_drain` Pi tool — reads structured errors from the log drain
- error-classifier service (S2.2 pattern) — classifies error type and severity
- self-healer skill — applies automated fixes for known error patterns
- Beads CLI (`bd`) — creates bug issues with classification metadata
- Telegram — notifications for code bugs, recurring errors, infra escalations
- platform.db — audit trail and recurring error history
