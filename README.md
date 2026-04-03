# Q — AI Dev Team powered by [Hermes](https://github.com/NousResearch/hermes-agent)/[Pi](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent) + [BMAD Method](https://github.com/bmad-code-org/BMAD-METHOD)

A portable AI dev team you can drop into any project. Q orchestrates, Pi codes, [BMAD Method](https://github.com/bmad-code-org/BMAD-METHOD) provides the agent framework, [Beads](https://github.com/gastownhall/beads) tracks work.

> **Q** is the alias for [Hermes](https://github.com/NousResearch/hermes-agent) — named after the James Bond quartermaster who builds the tools.

## How It Works

Built on the **[BMAD Method](https://github.com/bmad-code-org/BMAD-METHOD)** agent hierarchy — Analyst, PM, Architect, SM, QA, Dev, Tech Writer — each phase maps to a BMAD agent role. Q ([Hermes](https://github.com/NousResearch/hermes-agent)) orchestrates the agents, [Pi](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent) executes the coding.

### Brownfield vs Greenfield (auto-detected)

**Brownfield** (existing project with `package.json` + `AGENTS.md` + `.beads/`):
- **Skips analyst phase** — no market research needed, you already have a product
- **Phase 2 (immersion)** reads `project-context.md` for patterns, conventions, and reuse rules
- If `project-context.md` doesn't exist, Q creates one by scanning the codebase
- Only writes new code when no existing pattern can be reused

**Greenfield** (new project):
- Starts at analyst — research, validate, then build from scratch
- Full pipeline: brief → PRD → architecture → stories → code

## Quick Start

```bash
# Full pipeline — auto-detects brownfield/greenfield
q chat -s dev-team/vibe-loop --yolo -q "Build feature X"

# Skip to specific phases using BMAD agent names
q chat -s dev-team/vibe-loop --yolo -q "Build X. Start at dev."           # Code only
q chat -s dev-team/vibe-loop --yolo -q "Build X. Start at tdd."           # Write tests, then code
q chat -s dev-team/vibe-loop --yolo -q "Build X. Start at story-specs."   # Specs + tests + code
q chat -s dev-team/vibe-loop --yolo -q "Build X. Start at architecture."  # Design first
q chat -s dev-team/vibe-loop --yolo -q "Run quinn-review."                # Adversarial review only
```

## BMAD Phase Reference

| Phase | BMAD Name | BMAD Agent | What |
|-------|-----------|------------|------|
| 0 | analyst | Analyst | Research & validate (greenfield only) |
| 1 | brief-capture | PM | Capture idea/task |
| 2 | immersion | Enforcer | Deep project scan, read/create project-context.md |
| 3 | product-brief | PM | Product/feature brief |
| 4 | prd | PM | PRD or feature spec |
| 5 | architecture | Architect | Solution design |
| 6 | epics | SM | Epic & story breakdown |
| 7a | story-specs | SM | Story specs with AC |
| 7b | tdd | QA | Failing TDD tests from specs |
| 8 | beads-filing | SM | File beads issues |
| 9 | checkpoint | SM | Checkpoint & handoff |
| 10 | dev | Dev (Pi) | Code to pass tests |
| 10b | pattern-capture | Enforcer | Update project-context.md |
| 10c | quinn-review | QA (Quinn) | 3-layer adversarial review (hard gate) |
| 11 | e2e-validation | QA | End-to-end validation |
| 12 | deploy | DevOps | Deploy to Railway |
| 13 | report | Tech Writer | Completion report |

## Pipeline Flow

```
Q starts (vibe-loop)
  ↓
Brownfield detected? → skip analyst, read project-context.md
  ↓  (no project-context.md? → create one by scanning codebase)
Immersion → scan existing patterns, conventions, code
  ↓
Planning → brief → PRD → architecture → epics → stories
  ↓
Story Specs → SM writes acceptance criteria
  ↓
TDD → QA writes failing tests from specs
  ↓
Dev → Pi codes to make tests pass (progress-based retries)
  ↓
Quinn Review → 3-layer adversarial review (mandatory gate)
  ↓
Land → commit, close beads issue, push, deploy
  ↓
Loop → next story until bd ready returns zero
```

## Key Design Decisions

- **[BMAD Method](https://github.com/bmad-code-org/BMAD-METHOD)** — agent roles and workflows follow the BMAD framework for structured AI-driven development.
- **[Pi](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent) via CLI** — each story runs as a fresh `pi -q` process. Crashes don't affect Q.
- **Cross-check** — Q independently re-runs tests after Pi claims PASS.
- **No human dead ends** — every failure path resolves autonomously (escalation → Opus → web research → deep research).
- **Quinn is a hard gate** — adversarial review is mandatory before any code ships.
- **Progress-based retries** — no arbitrary limits. Keeps going while making progress.
- **Brownfield-first** — Phase 2 reads project-context.md and scans existing patterns before writing new code. Creates project-context.md if missing.

## Components

| Component | Repo | Purpose |
|-----------|------|---------|
| Q (Hermes) | [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) | Orchestrator — runs BMAD agent phases |
| Pi | [badlogic/pi-mono](https://github.com/badlogic/pi-mono/tree/main/packages/coding-agent) | Coding agent (TDD) |
| Quinn | Built into vibe-loop | 3-layer adversarial reviewer |
| BMAD Method | [bmad-code-org/BMAD-METHOD](https://github.com/bmad-code-org/BMAD-METHOD) | Agent framework, workflows, templates |
| Beads | [gastownhall/beads](https://github.com/gastownhall/beads) | Git-backed issue tracking (Dolt) |
| BeadsBoard | [azrlb/BeadsBoard](https://github.com/azrlb/BeadsBoard) | Kanban UI for Beads |

## Full Documentation

See [dev-team-work-loop/README.md](dev-team-work-loop/README.md) for the complete setup guide, configuration, failure handling, budget controls, and parallel execution.
