# Skill Creator

Analyzes completed stories and suggests reusable Hermes skills when novel patterns are detected. Writes draft skills to `~/.hermes/skills/`.

## Trigger

- **Automatic:** After a story lands successfully via work-loop (optional, controlled by SKILL_CREATION_ENABLED)
- **Telegram:** Bob sends `create skill from {story_id}`
- **On-demand:** Hermes recognizes a repeatable pattern

## When to Create a Skill

A new skill is warranted when:
- The same type of fix/build has been done 2+ times
- A novel workflow was discovered that isn't captured in existing skills
- A recovery pattern was found after an escalation was resolved
- Bob explicitly requests it

A new skill is NOT warranted when:
- The work was routine (standard story implementation)
- An existing skill already covers the pattern
- The pattern is too specific to one story to be reusable

## Steps

### 1. Analyze the Completed Story

Read from Beads issue metadata:
- What was built/fixed (from story description + commit diff)
- What approach worked (from checkpoints)
- What approaches failed (from failed_approaches)
- How long it took and how much it cost

### 2. Check for Existing Skills

Search `~/.hermes/skills/` for similar skills:
```
hermes skills list
```
If a matching skill exists, consider updating it (via `skill_manage patch`) rather than creating a new one.

### 3. Draft the Skill

Write a SKILL.md following Hermes format:

```markdown
---
name: {skill-name}
description: {one-line description}
version: 1.0.0
metadata:
  hermes:
    tags: [{relevant, tags}]
    category: infrastructure
---

# {Skill Title}

## When to Use
{trigger conditions derived from the story pattern}

## Procedure
1. {step derived from successful approach}
2. {step}
3. {step}

## Pitfalls
- {what failed in prior attempts}

## Verification
{how to confirm the skill worked — derived from test results}
```

### 4. Save Draft

Write to `~/.hermes/skills/infrastructure/{skill-name}/SKILL.md`

Log to audit trail:
```
action: skill_created
target: {skill-name}
detail: { source_story, pattern_type, category }
```

### 5. Notify

Telegram to Bob: "🛠️ New skill drafted: {skill-name} — from {story_id}. Review at ~/.hermes/skills/infrastructure/{skill-name}/SKILL.md"

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `SKILL_CREATION_ENABLED` | `false` | Auto-create after story landing (Phase 2+) |

## Guard Rails

- Never overwrite an existing skill without confirmation
- Draft skills are suggestions — Bob reviews before they're trusted
- Skills created by this process start at `community` trust level
- Include the source story ID in skill metadata for traceability

## Dependencies

- Hermes skill_manage tool (built-in)
- Beads CLI for story context
- Telegram for notification
- platform.db for audit logging
