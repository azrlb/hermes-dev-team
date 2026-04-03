# Q — AI Dev Team (Hermes/Pi)

A portable AI dev team you can drop into any project. Q orchestrates, Pi codes, Beads tracks work.

> **Q** is the alias for Hermes — named after the James Bond quartermaster who builds the tools.

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

## Phase Reference

| Phase | BMAD Name | Who | What |
|-------|-----------|-----|------|
| 0 | analyst | Analyst | Research & validate |
| 1 | brief-capture | PM | Capture idea/task |
| 2 | immersion | Enforcer | Deep project scan |
| 3 | product-brief | PM | Product/feature brief |
| 4 | prd | PM | PRD or feature spec |
| 5 | architecture | Architect | Solution design |
| 6 | epics | SM | Epic & story breakdown |
| 7a | story-specs | SM | Story specs with AC |
| 7b | tdd | QA | Failing TDD tests |
| 8 | beads-filing | SM | File beads issues |
| 9 | checkpoint | SM | Checkpoint & handoff |
| 10 | dev | Dev (Pi) | Code to pass tests |
| 10b | pattern-capture | Enforcer | Update project-context |
| 10c | quinn-review | QA | Adversarial review (hard gate) |
| 11 | e2e-validation | QA | End-to-end validation |
| 12 | deploy | DevOps | Deploy to Railway |
| 13 | report | Tech Writer | Completion report |

## How It Works

```
Q starts (vibe-loop)
  ↓
Immersion → read project patterns, existing code, tests
  ↓
Planning → brief → PRD → architecture → epics → stories
  ↓
TDD → QA writes failing tests from story specs
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

- **Pi via CLI** — each story runs as a fresh `pi -q` process. Crashes don't affect Q.
- **Cross-check** — Q independently re-runs tests after Pi claims PASS.
- **No human dead ends** — every failure path resolves autonomously (escalation → Opus → web research → deep research).
- **Quinn is a hard gate** — adversarial review is mandatory before any code ships.
- **Progress-based retries** — no arbitrary limits. Keeps going while making progress.
- **Brownfield-first** — Phase 2 scans existing patterns before writing new code.

## Components

| Component | Location | Purpose |
|-----------|----------|---------|
| Q (Hermes) | `hermes` CLI | Orchestrator |
| Pi | `pi` CLI | Coding agent (TDD) |
| Quinn | Built into vibe-loop | Adversarial reviewer |
| Beads | `bd` CLI | Git-backed issue tracking (Dolt) |
| [BeadsBoard](https://github.com/azrlb/BeadsBoard) | Standalone web app | Kanban UI for Beads |

## Full Documentation

See [dev-team-work-loop/README.md](dev-team-work-loop/README.md) for the complete setup guide, configuration, failure handling, budget controls, and parallel execution.
