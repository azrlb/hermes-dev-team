# Drain Log Reader

Script location: `~/.hermes/scripts/drain-log-reader.py`

Usage:
```bash
# Read yesterday's logs (default)
python3 ~/.hermes/scripts/drain-log-reader.py

# Read specific date
python3 ~/.hermes/scripts/drain-log-reader.py 2026-06-25
```

Output: Summary of all drain logs for the given date, including:
- Which drains ran
- Beads closed/failed/skipped per drain
- Quality gate status (self_review, quinn_review, murat_review, traceability)
- Test pass/fail counts
- Exit reason per drain

## Cron Job for Morning Audit

A one-shot cron job runs at 7:15 AM to audit Level 2 quality review.
See cron job `d9a9c68cd957` for the template.

The morning audit checks:
1. Drain logs exist for the date
2. Quality gates were actually executed (not just logged as true)
3. Quinn findings (if any)
4. Murat scores (if any)
5. Any issues or gaps

## Log Directory Structure

```
~/.hermes/drain-logs/
  YYYY-MM-DD/
    <project>-<slot>.json
```

Example:
```
~/.hermes/drain-logs/2026-06-25/
  FlowInCash-Core-8pm.json
  Crispi-app-9pm.json
  crispi-app-overnight.json
```
