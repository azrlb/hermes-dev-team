# Orchestrator Routing Reference

## Complete Routing Table

| Task Type | Specialist | Model | Why |
|-----------|------------|-------|-----|
| Simple file edit | default | Gemini 3.5 Flash | Fast, routine |
| Fix a bug (simple) | default | Gemini 3.5 Flash | Fast, routine |
| Fix a bug (complex) | orchestrator | Opus 4.8 | Needs deep reasoning |
| Build new feature (code) | code | DeepSeek V3.2 | Coding specialist |
| TypeScript error | code | DeepSeek V3.2 | Coding specialist |
| Python script | code | DeepSeek V3.2 | Coding specialist |
| Write tests | code | DeepSeek V3.2 | Coding specialist |
| Refactor code | code | DeepSeek V3.2 | Coding specialist |
| Design architecture | orchestrator | Opus 4.8 | Architecture decision |
| Plan a feature | orchestrator | Opus 4.8 | Planning requires reasoning |
| Review a PR | analysis | Sonnet 4.6 | Code review specialist |
| Research a topic | analysis | Sonnet 4.6 | Research specialist |
| Write a report | analysis | Sonnet 4.6 | Report specialist |
| Verify video frame | vision | Gemini 3.1 Pro | Vision specialist |
| Read a screenshot | vision | Gemini 3.1 Pro | Vision specialist |
| Analyze an image | vision | Gemini 3.1 Pro | Vision specialist |
| Composite video | video | Gemini 3.5 Flash | Video production |
| Green plate verification | vision | Gemini 3.1 Pro | Vision specialist |
| HeyGen integration | video | Gemini 3.5 Flash | Video production |
| Browser automation | automation | GPT 5.6 Luna | Browser control specialist |
| UI testing | automation | GPT 5.6 Luna | UI interaction specialist |
| Web scraping | automation | GPT 5.6 Luna | Web data extraction |
| Form filling | automation | GPT 5.6 Luna | Form automation specialist |
| Desktop automation | automation | GPT 5.6 Luna | Desktop task automation |
| Emergency / critical bug | orchestrator | Opus 4.8 | Highest quality needed |
| Party mode analysis | orchestrator | Opus 4.8 | Multi-perspective host |
| Bead triage (hard cases) | orchestrator | Opus 4.8 | Complex routing decision |

## Classification Keywords

Look for these keywords in task descriptions:

**Code profile:**
- TypeScript, Python, JavaScript, code, implement, build, write, create
- Bug fix, error, exception, fix, debug
- Test, spec, unit test, integration test
- Refactor, clean up, optimize code

**Vision profile:**
- Screenshot, image, picture, photo, frame
- Document, PDF, scan
- Verify, check, analyze visual

**Video profile:**
- Video, composite, render, frame QA
- Green screen, chroma key
- HeyGen, avatar, lip sync

**Analysis profile:**
- Review, PR, pull request
- Research, investigate, analyze
- Report, summary, documentation

**Automation profile:**
- Browser, web, scrape, crawl
- UI, interface, button, form
- Automate, workflow, pipeline
- Desktop, application, window

**Orchestrator (handle yourself):**
- Architecture, design, system
- Complex, difficult, challenging
- Plan, strategy, roadmap
- Emergency, critical, urgent

## Delegation Examples

### Code Task
```
delegate_task(
    goal="Fix the TypeScript error in payment.ts on line 42. The error is 'Type 'string' is not assignable to type 'number'.",
    context="File: /media/bob/C/AI_Projects/FlowInCash/src/routes/payment.ts. The variable 'amount' is typed as string but should be number. Add parseFloat() conversion.",
    toolsets=["terminal", "file"]
)
```

### Vision Task
```
delegate_task(
    goal="Analyze this video frame and verify: 1) The text overlay is readable, 2) The green screen key is clean, 3) The composition looks professional.",
    context="Frame is at /tmp/frame_001.png. This is a FlowInCash promotional video frame.",
    toolsets=["terminal", "file"]
)
```

### Automation Task
```
delegate_task(
    goal="Navigate to the competitor pricing page, extract all plan names and prices, and save them to a JSON file.",
    context="URL: https://competitor.com/pricing. Output format: [{plan: 'Basic', price: '$9/mo'}, ...]. Save to /tmp/competitor-pricing.json.",
    toolsets=["terminal", "file"]
)
```

### Analysis Task
```
delegate_task(
    goal="Review this pull request and provide feedback on code quality, potential issues, and suggestions for improvement.",
    context="PR #123: Adds user preferences API endpoint. Changes in src/routes/user-preferences.ts and src/db/schema.ts.",
    toolsets=["terminal", "file"]
)
```

## Escalation Path

1. Specialist fails → try different specialist
2. Different specialist fails → handle yourself (orchestrator)
3. Still stuck → use MoA for multi-model reasoning
4. MoA fails → report blocker to Bob

## MoA Configuration

When escalating to MoA:
- Reference 1: GLM 5.2 (agent-first, strong reasoning)
- Reference 2: Gemini 3.5 Flash (fast, tool-aware)
- Aggregator: Opus 4.8 (best reasoning)

Use `/moa [question]` to trigger MoA.
