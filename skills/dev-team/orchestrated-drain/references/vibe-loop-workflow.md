# The Vibe Loop — Bob's Development Workflow

The Vibe Loop is Bob's iterative development process model. It is the
**workflow** the orchestrator follows to complete a task (a "bead").
It is NOT a model assignment — it is the process itself.

Many cron jobs and skills reference `dev-team/vibe-loop` as a skill,
but it does not exist as a standalone SKILL.md. The workflow is
implemented across multiple skills: `orchestrated-drain` (routing),
`shared-execution` (execution lifecycle), and `bead-execution` (bead
processing).

## Status: ✅ Cloud Migration Complete (2026-07-10)

All core pipeline files now use cloud specialist profiles. The13-phase
profile mapping is documented in `dev-team/orchestrator-prompt/references/13-phase-profile-mapping.md`.

## The 6 Phases

```
┌─────────────┐
│  1. ANALYST │  Understand the problem, break it down, clarify requirements
├─────────────┤
│ 2. DISCOVERY│  Explore the codebase, identify relevant files, locate areas
├─────────────┤
│  3. PLANNING│  Create implementation plan, design solution, architecture
├─────────────┤
│  4. BUILDING│  Implement code changes, write functions, modify logic
├─────────────┤
│  5. TESTING │  Write/execute tests, validate changes, no regressions
├─────────────┤
│  6. REVIEW  │  Quality check, identify issues, validate solution
└─────────────┘
```

## Original Agent Roles (Before Profile System)

| Phase    | Original Agent | What They Did |
|----------|----------------|---------------|
| Orchestrator | Hermes    | Routed tasks, managed flow |
| Building/Coding | Pi Agent | Wrote code, implemented features |
| Testing | Quinn          | Ran tests, validated changes |
| Review/TEA | TEA Agent  | Quality check, code review |
| End-to-End | (added later) | Integration testing |

## Current Profile Mapping (After Profile System)

| Phase    | Profile        | Model              | Why |
|----------|----------------|--------------------|-----|
| Orchestrator | architect  | Claude Opus 4.8    | Deep reasoning, skill adherence |
| Analyst  | default        | Gemini 2.5 Flash   | Fast analysis |
| Discovery| default        | Gemini 2.5 Flash   | File reading, navigation |
| Planning | architect      | Claude Opus 4.8    | Architecture decisions |
| Building | code           | DeepSeek V3.2      | Code generation, TypeScript/Python |
| Testing  | default        | Gemini 2.5 Flash   | Test execution |
| Review   | analysis       | Claude Sonnet 4.6  | Code review, analysis |

## How It Connects to Orchestrated Drain

The `orchestrated-drain` skill implements the routing logic for the
Vibe Loop. When a drain job runs under the `architect` profile:

1. The orchestrator (Opus 4.8) receives a bead
2. It follows the Vibe Loop phases: Analyst → Discovery → Planning
3. At the Building phase, it delegates to the `code` profile (DeepSeek)
4. At the Testing phase, it delegates to `default` profile (Gemini Flash)
5. At the Review phase, it delegates to `analysis` profile (Sonnet 4.6)

The routing table in `orchestrated-drain` maps task types to profiles,
which is the implementation of the Vibe Loop's model assignments.

## Key Distinction: Workflow vs Models

**The Vibe Loop is the workflow.** The profiles/models are the
specialists that execute each phase. Changing models doesn't change
the workflow — it changes who does the work in each phase.

When Bob asks "what is the Vibe Loop?" — answer with the 6 phases
and the process, not with model names. When Bob asks "which model
does each phase use?" — answer with the profile mapping above.

## Cron Job References

Many drain cron jobs list `dev-team/vibe-loop` in their `skills` array.
This is a conceptual reference to this workflow pattern. The actual
implementation happens through:
- `dev-team/orchestrated-drain` — routing logic
- `dev-team/shared-execution` — execution lifecycle
- `dev-team/bead-execution` — bead processing

The `vibe-loop` skill reference in cron jobs should be understood as
"follow the Vibe Loop workflow" — the phases defined above.
