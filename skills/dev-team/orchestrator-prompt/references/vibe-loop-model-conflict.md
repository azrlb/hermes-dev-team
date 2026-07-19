# Vibe Loop vs Orchestrator Hierarchy — Model Conflict

## Problem Statement

The `dev-team/vibe-loop` skill (the "dev loop" for all Hermes dev work) hardcodes local Ollama models. The new orchestrator hierarchy uses cloud models. These two systems conflict when running Phases 10 (dev) and 10c (quinn-review).

## The Two Model Stacks

### Vibe Loop (Local Models)
| Role | Model | Location |
|------|-------|----------|
| Pi (coding) | devstral-small-2:24b | Local Ollama, GPU 2 (P4000), port 11434 |
| Quinn (review/escalation) | deepseek-r1:32b | Local Ollama, GPU 1 (P40), port 8082 |
| Tier 1-3 tasks | qwen3:8b | Local Ollama, GPU 2 |
| Tier 4 tasks | deepseek-r1:32b | Local Ollama, GPU 1 |
| Tier 5 | Human (Bob) | N/A |

Escalation chain: parent model → deepseek-r1:32b → run inline → HALT

### Orchestrator Hierarchy (Cloud Models)
| Profile | Model | Role |
|---------|-------|------|
| Orchestrator (brain) | Claude Opus 4.8 | Routing + complex decisions |
| Default | Gemini 3.5 Flash | Routine tasks, simple fixes |
| Code | DeepSeek V3.2 | Code generation, TypeScript, Python |
| Analysis | Claude Sonnet 4.6 | Code review, research, reports |
| Vision | Gemini 3.1 Pro | Screenshots, documents, images |
| Automation | GPT 5.6 Luna | Browser, UI, desktop automation |
| Video | Gemini 3.5 Flash | Video compositing, frame QA |

Escalation chain: try different specialist → handle yourself (Opus) → MoA multi-model reasoning

## Specific Conflicts

### 1. Phase 10 (Dev) Model Mismatch
Vibe-loop invokes Pi with:
```bash
pi --provider ollama --model devstral-small-2:24b ...
```
Orchestrator would route code tasks to DeepSeek V3.2 (cloud), not local devstral.

### 2. Phase 10c (Quinn Review) Role Conflict
Vibe-loop hardcodes Quinn (deepseek-r1:32b) as the adversarial reviewer.
Orchestrator routes "Review a PR" to Analysis specialist (Claude Sonnet 4.6).
Different models, different capabilities, different escalation paths.

### 3. Escalation Chain Divergence
Vibe-loop: local reasoning model (deepseek-r1:32b) → inline → HALT
Orchestrator: Opus → MoA multi-model consensus

### 4. Model Tier Classifier Isolation
The `model-tier-classifier` skill uses a 5-tier system with qwen3:8b and deepseek-r1:32b.
It has no awareness of the orchestrator's 6-specialist routing table.
Returns local model names, not orchestrator profile names.

### 5. Orchestrated-Drain Incomplete Bridge
The `orchestrated-drain` skill routes beads to orchestrator specialists but:
- Doesn't reference vibe-loop's escalation chain
- Doesn't call model-tier-classifier
- Doesn't address Quinn review gate (Phase 10c)
- Surface-level routing without deep integration

## Resolution Options

### Option A: Update Vibe-Loop to Use Orchestrator
Replace hardcoded local model references in vibe-loop Phase 10 and 10c with orchestrator routing:
- Phase 10: Use `delegate_task` to Code specialist (DeepSeek V3.2) instead of Pi with local devstral
- Phase 10c: Use Analysis specialist (Sonnet 4.6) instead of Quinn (deepseek-r1:32b)
- Escalation: Use Opus → MoA instead of deepseek-r1:32b → HALT
- Update model-tier-classifier to return orchestrator profile names

### Option B: Keep Vibe-Loop Local, Orchestrator for New Work
- Vibe-loop continues using local models for existing brownfield work
- Orchestrator hierarchy only applies to new greenfield projects
- orchestrated-drain becomes the bridge for new work only

### Option C: Hybrid — Local Coding, Cloud Review
- Keep Pi with local devstral for coding (fast, zero-cost)
- Replace Quinn with Analysis specialist (Sonnet 4.6) for review
- Use orchestrator escalation chain for hard problems
- Update model-tier-classifier to return both local and cloud recommendations

## Impact Assessment

If not resolved:
- Vibe-loop will try to use devstral locally while orchestrator routes to DeepSeek V3.2 cloud
- Escalation chains will point in different directions
- Quinn review gate may run on wrong model
- orchestrated-drain routing will be overridden by vibe-loop's hardcoded paths

## Files Affected

- `skills/dev-team/vibe-loop/SKILL.md` — Phase 10, Phase 10c, escalation chain
- `skills/dev-team/model-tier-classifier/SKILL.md` — tier definitions
- `skills/dev-team/orchestrated-drain/SKILL.md` — routing table
- `skills/dev-team/work-loop/SKILL.md` — deprecated but still referenced

## Related Skills

- `orchestrator-prompt` — defines the cloud model hierarchy
- `loop-engineering-curator` — audits drain quality, should know about this conflict
- `shared-execution` — referenced by both vibe-loop and bead-execution
