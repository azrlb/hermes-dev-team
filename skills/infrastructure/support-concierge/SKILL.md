# Support Concierge

**Type:** Infrastructure Skill (Hermes)
**Version:** 1.0.0
**Status:** Draft

## Purpose

Customer support agent that handles incoming chat messages from consuming apps' chat widgets. Reads user context from the app API, answers questions using platform skills and documentation, and escalates to Bob when it cannot resolve.

## Trigger

Incoming chat message via consuming app's chat widget SSE endpoint.

```
Event: POST /api/chat/message (SSE stream)
Payload: { userId, appId, sessionId, message, timestamp }
```

Hermes subscribes to the SSE endpoint and dispatches to this skill when a new message arrives.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `CONCIERGE_ENABLED` | `false` | Master switch for the concierge skill |
| `CONCIERGE_MODEL_TIER` | `2` | Default model tier (2 = pattern matching, 3 = reasoning) |
| `MAX_TURNS_BEFORE_ESCALATE` | `2` | Max unanswered attempts before escalation |

## Dependencies

| Dependency | Purpose |
|-----------|---------|
| `gateway_request` tool | Read user context from consuming app's API |
| Telegram API | Notify Bob on escalation |
| Beads CLI (`bd`) | Create support ticket issues on escalation |
| App chat widget SSE endpoint | Receive and respond to chat messages |

## Workflow

### 1. Receive Message

On SSE event, extract `userId`, `appId`, `sessionId`, and `message`.

### 2. Load User Context

Use `gateway_request` to fetch user context from the consuming app's API:

```
gateway_request({
  app: appId,
  endpoint: "/api/users/{userId}/context",
  method: "GET"
})
```

Returns:
- Account data (name, email, created date)
- Subscription tier (free, pro, enterprise)
- Recent activity (last 10 actions with timestamps)
- App-specific context (varies by consuming app)

User context persists for the duration of the chat session (`sessionId`). Subsequent messages in the same session reuse cached context unless the session exceeds 30 minutes, at which point context is refreshed.

### 3. Graduated Response

**Tier 2 -- Known Patterns (default):**
- Search platform skills and app documentation for matching answers
- Pattern match against known FAQs and support templates
- Respond with direct answer + relevant doc link if available
- Fast, low-cost, handles ~80% of questions

**Tier 3 -- Reasoning with Context:**
- Escalate to Tier 3 model when Tier 2 returns low confidence
- Uses full user context (account data, activity, subscription) to reason about the answer
- Can correlate user's specific situation with platform capabilities
- Handles edge cases and nuanced questions

**Escalate to Bob:**
- Triggered when concierge cannot answer after `MAX_TURNS_BEFORE_ESCALATE` attempts
- See Escalation section below

### 4. Conversation State

Track per session:

```yaml
session:
  id: {sessionId}
  userId: {userId}
  appId: {appId}
  started: {timestamp}
  turns: []          # array of { role, content, timestamp, tier_used }
  user_context: {}   # cached from gateway_request
  escalated: false
  resolution: null   # "answered" | "escalated" | "abandoned"
```

State is held in memory during the session. On session end (user closes widget, 30-min inactivity timeout, or explicit close), state is flushed to audit log and discarded.

### 5. Escalation

Triggered when:
- Concierge fails to answer after `MAX_TURNS_BEFORE_ESCALATE` consecutive attempts
- User explicitly requests human support
- Message contains sensitive account/billing issue keywords

Escalation steps:
1. Create Beads support ticket:
   ```
   bd create --title="Support: {summary}" --type=bug --labels=support,escalated
   ```
   Ticket body includes: user context, full conversation transcript, attempted answers.

2. Notify Bob via Telegram:
   ```
   Telegram message:
   "Support escalation [{appId}]
   User: {name} ({email}) - {subscriptionTier}
   Question: {original question}
   Attempts: {count}
   Beads: {issue_id}
   Session: {sessionId}"
   ```

3. Respond to user: "I've flagged this for our team. You'll hear back shortly. Your reference is {issue_id}."

4. Mark session as escalated. No further auto-responses on this session.

## Safety Rules

1. **Never expose internal system data.** No skill internals, architecture details, API keys, database schemas, or infrastructure information.
2. **Never make changes without confirmation.** Concierge is read-only. If a user requests an action (cancel subscription, change settings), confirm intent and route to the appropriate app endpoint with user approval.
3. **Rate limit per user.** Max 30 messages per session, max 5 sessions per user per hour. Excess triggers a polite cooldown message.
4. **No PII in logs.** Audit logs store userId and sessionId references, not raw PII. User context is fetched on-demand and not persisted beyond session lifetime.
5. **Scope boundary.** Only answer questions about the consuming app the user is chatting from. Do not cross-reference other apps or expose multi-tenant information.

## Audit Logging

Every interaction is logged:

```yaml
audit_entry:
  action: "concierge_interaction"
  sessionId: {sessionId}
  userId: {userId}
  appId: {appId}
  turn_number: {n}
  tier_used: 2 | 3
  resolution: "answered" | "escalated" | "no_answer"
  timestamp: {ISO 8601}
  cost_usd: {model cost for this turn}
```

Logged via `insertAuditLog()` from `gateway/src/db.ts`.

Session summary logged on close:

```yaml
audit_entry:
  action: "concierge_session_end"
  sessionId: {sessionId}
  total_turns: {n}
  resolution: "answered" | "escalated" | "abandoned"
  total_cost_usd: {sum}
  duration_seconds: {elapsed}
```

## Response Format

Concierge responses to the chat widget:

```json
{
  "sessionId": "{sessionId}",
  "message": "{response text}",
  "confidence": 0.0-1.0,
  "sources": ["skill:name", "doc:path"],
  "escalated": false
}
```

## Example Flow

1. User sends: "How do I export my cash flow report?"
2. Concierge loads user context via `gateway_request` (FlowInCash, Pro tier)
3. Tier 2 matches skill docs for export functionality
4. Responds: "You can export from Dashboard > Reports > Export CSV. As a Pro user, you also have PDF export available."
5. Audit log entry written, session continues
