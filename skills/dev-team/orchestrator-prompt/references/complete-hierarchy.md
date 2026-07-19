# Complete 7-Profile Model Hierarchy

## Architecture

```
Bob → Hermes (Gemini 3.5 Flash) — Daily Driver
       │
       ├── 🧠 ORCHESTRATOR (Opus 4.8)
       │   Routes tasks to specialists
       │   Handles complex reasoning
       │   Party mode host
       │
       ├── 💻 CODING (DeepSeek V3.2)
       │   Code generation, TypeScript
       │
       ├── 🎬 VIDEO (Gemini 3.5 Flash)
       │   Video compositing, frame QA
       │
       ├── 📊 ANALYSIS (Sonnet 4.6)
       │   Code review, research
       │
       ├── 🔍 VISION (Gemini 3.1 Pro)
       │   Screenshots, documents, images
       │
       └── 🤖 AUTOMATION (GPT 5.6 Luna)
           Browser, UI, desktop automation
```

## Profile Configurations

| Profile       | Model                  | Provider | Context  |
|---------------|------------------------|----------|----------|
| default       | google/gemini-3.5-flash | custom   | 1M       |
| code          | deepseek/deepseek-v3.2  | custom   | 64K      |
| orchestrator  | anthropic/claude-opus-4.8 | custom | 1M       |
| video         | google/gemini-3.5-flash | custom   | 1M       |
| analysis      | anthropic/claude-sonnet-4.6 | custom | 200K    |
| vision        | google/gemini-3.1-pro-preview | custom | 1M    |
| automation    | openai/gpt-5.6-luna     | custom   | 1.05M    |

## MoA Configuration

- Reference 1: z-ai/glm-5.2 (agent-first, 1M context)
- Reference 2: google/gemini-3.5-flash (fast, tool-aware)
- Aggregator: anthropic/claude-opus-4.8 (best reasoning)

## Routing Table

| Task Type                        | Specialist   | Model                  |
|----------------------------------|--------------|------------------------|
| Simple file edit                 | default      | Gemini 3.5 Flash       |
| Fix a bug (simple)               | default      | Gemini 3.5 Flash       |
| Fix a bug (complex)              | orchestrator | Opus 4.8               |
| Build new feature (code)         | code         | DeepSeek V3.2          |
| TypeScript error                 | code         | DeepSeek V3.2          |
| Design architecture              | orchestrator | Opus 4.8               |
| Review a PR                      | analysis     | Sonnet 4.6             |
| Research a topic                 | analysis     | Sonnet 4.6             |
| Verify video frame               | vision       | Gemini 3.1 Pro         |
| Composite video                  | video        | Gemini 3.5 Flash       |
| Browser automation               | automation   | GPT 5.6 Luna           |
| UI testing                       | automation   | GPT 5.6 Luna           |
| Emergency / critical bug         | orchestrator | Opus 4.8               |

## Party Mode Model-Per-Role

| Persona      | Profile     | Model              |
|--------------|-------------|-------------------|
| John (PM)    | default     | Gemini 3.5 Flash   |
| Alex (Arch)  | orchestrator| Opus 4.8           |
| Pat (BA)     | default     | Gemini 3.5 Flash   |
| Sally (UX)   | default     | Gemini 3.5 Flash   |
| Winston (Dev)| code        | DeepSeek V3.2      |
| Murat (QA)   | analysis    | Sonnet 4.6         |

## Created: 2026-07-09

This hierarchy was designed in the LLM analysis report
(~/Desktop/llm-analysis-final-report.md) and implemented
in the session where Bob corrected the orchestrator pattern.
