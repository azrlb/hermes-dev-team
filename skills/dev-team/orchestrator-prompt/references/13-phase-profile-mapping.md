# 13-Phase Vibe Loop — Profile Mapping

## Overview

The 13-phase Vibe Loop uses cloud specialist profiles for each phase.
This mapping ensures the right model handles each type of work.

## Complete Profile Mapping

| Phase | Profile | Model | Purpose |
|-------|---------|-------|---------|
| Phase 0 (Analyst) | default | Gemini 2.5 Flash | Fast market research |
| Phase 1 (Brief) | default | Gemini 2.5 Flash | Capture requirements |
| Phase 2 (Immersion) | architect | Opus 4.8 | Deep code pattern scan |
| Phase 3 (Product Brief) | default | Gemini 2.5 Flash | Write brief |
| Phase 4 (PRD) | default | Gemini 2.5 Flash | Write spec |
| Phase 5 (Architecture) | architect | Opus 4.8 | Design solution |
| Phase 6 (Epics) | architect | Opus 4.8 | Break into stories |
| Phase 7a (Story Specs) | analysis | Sonnet 4.6 | Write story specs |
| Phase 7b (TDD) | analysis | Sonnet 4.6 | Write test files |
| Phase 8 (Beads Filing) | analysis | Sonnet 4.6 | File bead issues |
| Phase 9 (Checkpoint) | default | Gemini 2.5 Flash | Git commit |
| Phase 10 (Dev) | **code** | **DeepSeek V3.2** | Implement code |
| Phase 10c (Review) | **analysis** | **Sonnet 4.6** | Adversarial review |
| Phase 11 (E2E) | default | Gemini 2.5 Flash | End-to-end validation |
| Phase 12 (Deploy) | default | Gemini 2.5 Flash | Deploy to Railway |
| Phase 13 (Report) | default | Gemini 2.5 Flash | Completion report |

## Profile Definitions

### default (Gemini 2.5 Flash)
- **Use for:** Routine tasks, file ops, simple fixes, test execution
- **Speed:** Fast (5-10 seconds)
- **Cost:** Low
- **Capabilities:** Good at following instructions, fast execution, reliable

### code (DeepSeek V3.2)
- **Use for:** Code generation, TypeScript, Python, implementation
- **Speed:** Medium (10-20 seconds)
- **Cost:** Medium
- **Capabilities:** Excellent coding, follows patterns, writes tests

### analysis (Claude Sonnet 4.6)
- **Use for:** Code review, research, reports, adversarial review
- **Speed:** Medium (10-20 seconds)
- **Cost:** Medium
- **Capabilities:** Deep analysis, finds bugs, security issues, spec deviations

### architect (Claude Opus 4.8)
- **Use for:** Architecture decisions, complex reasoning, planning
- **Speed:** Slow (15-30 seconds)
- **Cost:** High
- **Capabilities:** Best reasoning, skill adherence, deep analysis

## Escalation Chain

```
Code specialist (DeepSeek V3.2)
  ↓ fails
Analysis specialist (Sonnet 4.6)
  ↓ fails
Architect (Opus 4.8)
  ↓ fails
MoA (Multi-model consensus: GLM 5.2 + Gemini 3.5 Flash + Opus 4.8)
```

## Migration Pattern

When migrating from local Ollama to cloud specialists:

1. **Replace Pi CLI dispatch** with `delegate_task(profile="code")`
2. **Replace deepseek-r1:32b escalation** with `delegate_task(profile="analysis")`
3. **Update all Pi references** to "specialist subagents"
4. **Update shell scripts** to use `orchestrated-drain` instead of `pi-build-loop.sh`
5. **Update dependencies section** to list cloud specialist profiles

## Key Changes (2026-07-10)

### Before (Local Ollama)
- Phase 10: Pi CLI with `devstral-small-2:24b` (local, GPU 2)
- Phase 10c: Quinn with `deepseek-r1:32b` (local, GPU 1)
- Escalation: `deepseek-r1:32b` → HALT

### After (Cloud Specialists)
- Phase 10: `delegate_task(profile="code")` with DeepSeek V3.2
- Phase 10c: `delegate_task(profile="analysis")` with Sonnet 4.6
- Escalation: Analysis → Architect → MoA multi-model consensus

## Files Updated

- `vibe-loop/SKILL.md` — Phase 10 and 10c updated
- `work-loop/SKILL.md` — Deprecated, updated to cloud references
- `vibe-plan/SKILL.md` — Updated to cloud references
- `vibe-plan-then-build.sh` — Updated to use orchestrated-drain

## Benefits

1. **Better Quality:** Cloud models outperform local Ollama on agent benchmarks
2. **No GPU Dependency:** No need for P4000/P40/A4000 GPUs running Ollama
3. **Consistent Performance:** Cloud models don't have local resource contention
4. **Better Escalation:** MoA multi-model consensus for hard problems
5. **Simplified Setup:** No Ollama model downloads, no GPU configuration
