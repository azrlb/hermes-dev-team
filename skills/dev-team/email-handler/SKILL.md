---
name: email-handler
description: Inbound email handler for the LivingApp-Sidecar runtime. Reads a Postmark-delivered inbound email payload from the kanban task body, classifies the request, drafts a response, and emits it via Resend (or queues for operator review per LivingApp Sidecar PRD §FR-P4.8). Stub for Slice 4+ wiring.
version: 0.1.0
metadata:
  hermes:
    tags: [sidecar, runtime, support, email, kanban-worker]
    related_skills: [dev-team/support-concierge, dev-team/error-fix]
---

# Email Handler — Sidecar Runtime

> **Stub skill (sidecar runtime).** Real implementation lands in Slice 4
> alongside Postmark inbound webhook + Resend outbound wiring. The
> sidecar-runtime fixture exercises this skill via the bin/hermes shim
> to prove the kanban-level routing works.

## Trigger

Kanban task created by the sidecar's Postmark inbound webhook handler.
Task body contains:

```
from=<sender>
subject=<subject>
body_text=<full email body>
app_name=<crispi|fic|...>
user_id=<resolved user id, if known>
```

## Process (when implemented)

1. Classify the email: support / billing / feature-request / other
2. Look up matching skill in the LivingApp skill library
3. If skill match: auto-resolve, draft reply via tier-2 model, emit
   via Resend, complete with `metadata.outcome=AUTO_RESOLVED`
4. If no skill match or low confidence: draft reply, queue for
   operator review (kanban_block waiting for `/approve <id>` from
   Telegram), then emit on approval
5. Audit row emitted to postgres-LVV via Gateway HTTP per FR-P4.7

## Output

```python
kanban_complete(
    summary="Email handled: <classification>, <auto|operator>-resolved",
    metadata={
        "from": from_addr,
        "classification": classification,
        "outcome": "AUTO_RESOLVED" | "OPERATOR_REVIEW" | "ESCALATED",
        "draft_text": draft_response,  # what was sent (or queued)
        "resend_message_id": "<id>",   # if sent
    },
)
```
