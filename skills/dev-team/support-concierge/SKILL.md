---
name: support-concierge
description: In-app chat-widget customer support handler for the LivingApp-Sidecar runtime. Reads a chat message from the kanban task body, accesses the requesting user's context via app HTTP API, resolves via skill library or escalates with full conversation history. Stub for Slice 4+ wiring per LivingApp Sidecar PRD §FR-P4.
version: 0.1.0
metadata:
  hermes:
    tags: [sidecar, runtime, support, chat, kanban-worker]
    related_skills: [dev-team/email-handler, dev-team/error-fix]
---

# Support Concierge — Sidecar Runtime

> **Stub skill (sidecar runtime).** Real implementation lands in Slice 4
> alongside the chat widget WebSocket endpoint. The sidecar-runtime
> fixture exercises this skill via the bin/hermes shim to prove the
> kanban-level routing works.

## Trigger

Kanban task created by the sidecar's chat-widget WebSocket handler
when a user message arrives. Task body contains:

```
session_id=<chat session>
user_id=<authenticated user id>
app_name=<crispi|fic|...>
message_text=<user's message>
prior_messages=<recent thread, JSON array>
```

## Process (when implemented)

1. Pull user context from app via authenticated REST API (per
   FR-P4.2). NEVER touch app database directly.
2. Classify intent: bug-report / how-to / feature-request /
   billing / other
3. Match against domain skill library for the app
4. If match + high confidence: auto-resolve, post reply to chat
   session, complete with `metadata.outcome=AUTO_RESOLVED`
5. If low confidence or novel: refer to KB articles + create
   escalation ticket with full convo history (per FR-P4.5),
   `kanban_block(reason="needs operator review")`. Operator sees
   the ticket in the Web UI batch processor.

## Output

```python
kanban_complete(
    summary="Support: <intent>, <auto|kb|escalated>",
    metadata={
        "session_id": session_id,
        "user_id": user_id,
        "intent": intent,
        "outcome": "AUTO_RESOLVED" | "KB_REFERRED" | "ESCALATED",
        "reply_text": reply,
        "satisfaction_pending": True,  # surveyed later per FR-P4.12
    },
)
```

## Role boundaries — DO NOT

- ❌ **Touch the app database directly.** Always go through the app's
  authenticated REST API. The Sidecar PRD §6 requires this.
- ❌ **Reveal "Hermes" branding.** Per Sidecar PRD §3 E-A: "users
  never see Hermes" — replies must use the per-app persona (Crispi
  voice, FIC voice, etc.).
- ❌ **Take destructive actions on user data without operator
  approval.** Per LivingApp-Platform PRD §FR-P5: graduated autonomy.
  At Phase 1 / 2, all writes route through human approval.
