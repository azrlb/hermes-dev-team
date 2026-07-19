# Orchestrated Bead Execution Flow

## Complete Flow

```
1. TRAIGE (skip non-implementable beads)
   ↓
2. ROUTE (classify task type, select specialist)
   ↓
3. DELEGATE (spawn specialist via delegate_task)
   ↓
4. VERIFY (check if task completed successfully)
   ↓
5. COMMIT (git add, commit, close bead)
   ↓
6. NEXT BEAD (repeat from step 1)
```

## Triage Checklist

Skip beads that are:
- Empty/placeholder (description is "(none)" or title contains "wprl" — will populate later)
- Tracking markers (implementation belongs in other repo)
- Epics (issue_type: epic → work through child stories)
- Stories under an unstarted epic ([story] type with parent: field — epic needs decomposition first)
- Large features ([feature] type spanning multiple files/services — needs decomposition)
- Planning beads (beads-planning-* prefix — PRD/design/documentation, no code)
- Design/deferred ("probably defer", "out of scope")
- Data-gated ("wait for real data first")
- Blocked (DEPENDS ON lists an open blocker)
- Cross-repo blocked (depends on bead in different repo)
- Stale planning beads (artifact already exists)
- Release-cycle-gated ("DO NOT execute until Bob confirms" or "post-beta")
- Owner: TEA/human (assigned to non-drain agent)
- Human action (requires Bob to do something)
- Infrastructure missing (references code that doesn't exist)
- Large feature needs decomposition (epic with no child stories)

## Routing Decision Tree

```
Read bead description
    ↓
Does it mention code/language?
    YES → code profile (DeepSeek V3.2)
    NO ↓
Does it mention images/screenshots/visual?
    YES → vision profile (Gemini 3.1 Pro)
    NO ↓
Does it mention video/compositing/rendering?
    YES → video profile (Gemini 3.5 Flash)
    NO ↓
Does it mention browser/UI/automate/scrape?
    YES → automation profile (GPT 5.6 Luna)
    NO ↓
Does it mention review/research/analyze/report?
    YES → analysis profile (Sonnet 4.6)
    NO ↓
Is it complex/architecture/planning?
    YES → orchestrator (Opus 4.8) — handle yourself
    NO → default profile (Gemini 3.5 Flash)
```

## Batch Execution Pattern

When processing multiple beads:

1. **Triage all beads first** — build a list of implementable beads
2. **Sort by priority** — P1 → P2 → P3
3. **Route each bead** — classify and select specialist
4. **Execute in order** — don't skip beads
5. **Commit after each bead** — one commit per bead
6. **Don't stop between beads** — batch execution
7. **Summarize once at the end** — not after each bead

## Quality Gates

Before closing a bead, verify:
1. Code compiles (`tsc --noEmit` for TypeScript)
2. Tests pass (`npx vitest run` or equivalent)
3. No lint errors
4. Changes match the bead description
5. Commit message references bead ID

## Common Failure Patterns

### Specialist returns error
- Read the error message
- Check if it's a routing error (wrong specialist)
- Check if it's an environment error (missing deps)
- Retry with different approach if needed

### Specialist says "I can't do this"
- May need different tools (check toolsets parameter)
- May need more context (add file paths, error messages)
- May need escalation to orchestrator

### Bead has hidden complexity
- Acceptance criteria span multiple files
- Requires infrastructure that doesn't exist
- Has cross-cutting concerns
→ Escalate to orchestrator for architecture decision

## Commit Format

```
fix(scope): description

Implements bead {id}
```

Example:
```
fix(payments): add parseFloat conversion for amount field

Implements bead Core-142
```
