---
name: error-fix
description: Production-error remediation handler for the LivingApp-Sidecar runtime. Reads an error event from the kanban task body, classifies it (transient API / code bug / infra / user-triggered), looks up a matching skill in the library, applies the remediation. Stub for Slice 4+ wiring per LivingApp-Platform PRD §FR-P3.
version: 0.1.0
metadata:
  hermes:
    tags: [sidecar, runtime, self-healing, kanban-worker]
    related_skills: [dev-team/support-concierge, dev-team/deep-research-bridge]
---

# Error Fix — Sidecar Runtime

> **Stub skill (sidecar runtime).** Real implementation lands in Slice
> 4 alongside Railway log-drain wiring. The sidecar-runtime fixture
> exercises this skill via the bin/hermes shim to prove the
> kanban-level routing works.

## Trigger

Kanban task created by the sidecar's log-drain monitor when an error
crosses the threshold defined in the per-app skill set. Task body:

```
app_name=<crispi|fic|...>
error_class=<TransientAPI|CodeBug|Infra|UserError>
error_signature=<grouped log fingerprint>
recent_count=<occurrences in last 24h>
sample_log=<one representative log line>
trace=<stack trace if any>
```

## Process (when implemented)

1. Classify the error class (FR-P3.2)
2. Look up matching skill (FR-P3.3): infrastructure skills are
   transferable across apps; domain skills scope to the app
3. If match + permission mode allows auto-fix (per Phase 3):
   - Execute the remediation
   - Verify the fix didn't introduce new errors (NFR-P3 invariant)
   - Audit row to Gateway
4. If no skill match or permission requires approval:
   - kanban_block with concrete diagnosis + suggested action
   - Operator approves via Telegram, then unblock to retry
5. If repeated same-error blocks (3+ in 24h): escalate to
   `dev-team/deep-research-bridge` for root-cause analysis

## Output

```python
kanban_complete(
    summary="Error fixed: <error_class>, skill=<name>, verified=<bool>",
    metadata={
        "error_class": error_class,
        "error_signature": signature,
        "skill_matched": skill_name,
        "outcome": "AUTO_FIXED" | "APPROVED_FIX" | "ESCALATED" | "NO_MATCH",
        "remediation_diff": diff_summary,
        "regression_check": "PASSED" | "REVERTED",
    },
)
```

## Role boundaries — DO NOT

- ❌ **Touch app database directly.** Use scoped, short-lived API
  tokens per LivingApp-Platform §Security Architecture.
- ❌ **Apply fixes that introduce new errors.** NFR-P3 explicitly:
  "Skill remediation never introduces new errors — failed fixes
  revert to pre-remediation state."
- ❌ **Auto-execute on novel error patterns.** Per Phase 1 / 2 of
  graduated autonomy: novel = escalate, not auto-fix.
- ❌ **Skip the audit row.** Every action emits to Gateway
  `/api/v1/apps/:appName/audit` (FR-P3.4).
