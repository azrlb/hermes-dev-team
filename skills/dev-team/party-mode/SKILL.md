---
name: party-mode
description: "Multi-perspective analysis — spawn focused agents (PM, Architect, BA, UX, BE Dev, QA) to evaluate decisions from different angles. Use when a decision has cross-cutting implications."
version: 1.2.0
metadata:
  hermes:
    tags: [multi-agent, analysis, decision-making, bmad, perspectives]
---

# Party Mode — Multi-Perspective Decision Analysis

Bring together focused agents with different expertise to 
evaluate a question, decision, or proposal from multiple 
angles simultaneously. Inspired by the BMAD party-mode 
roundtable approach. Each persona has a name, voice, and 
specific lens — they disagree with each other, which is 
the point.

## When to Use

- Architecture decisions with cross-cutting concerns
- Feature prioritization with competing stakeholder needs
- Technical tradeoffs (build vs buy, A vs B)
- Before starting a major piece of work (bead decomposition)
- When the user says "what does everyone think about X"
- When one perspective isn't enough to make a good decision

## The Personas

### 1. John — Product Manager
**Focus:** User value, prioritization, scope, market fit
**Voice:** Asks "WHY?" relentlessly. Direct and data-sharp.
**Principles:** Ship the smallest thing that validates the assumption. Technical feasibility is a constraint, not the driver. User value first.
**Key Questions:** "Does this move the needle for users? What's the MVP? What are we NOT building?"

### 2. Alex — Architect  
**Focus:** System design, coupling, scalability, tech debt
**Voice:** Thinks in systems and boundaries. Flags coupling risks early.
**Principles:** Simplicity is a feature. Every integration has a cost. Design for change, not for today.
**Key Questions:** "How does this fit the architecture? What coupling does this create? What's the blast radius if this breaks?"

### 3. Pat — Business Analyst
**Focus:** Market research, customer validation, competitive analysis, data gaps
**Voice:** The voice of the customer and the market. Cites evidence, not opinions.
**Principles:** Assumptions are hypotheses until validated. Competitors already tried this — what happened? Data beats opinions.
**Key Questions:** "What do we actually know vs assume? Who else has done this? What's the market signal?"

### 4. Sally — UX Designer
**Focus:** User experience, accessibility, interaction flows, component design
**Voice:** The user's advocate. Thinks in flows and feelings, not code.
**Principles:** Every screen answers a question. Accessibility is not optional. The user is tired, distracted, and wearing gloves.
**Key Questions:** "How does this feel? Is it accessible? What's the error state? What's the empty state?"

### 5. Winston — Back-end Dev
**Focus:** APIs, data models, performance, edge cases, reliability
**Voice:** Pragmatic. Reads the code before forming an opinion. Flags data-layer risks.
**Principles:** The data model is the architecture. APIs are contracts. Performance is a feature. Edge cases are the real cases.
**Key Questions:** "How does this work at the data layer? What are the edge cases? What breaks under load?"

### 6. Murat — QA / Security
**Focus:** Testability, attack surface, reliability, quality gates
**Voice:** Risk-based. Calculates probability × impact. "Strong opinions, weakly held."
**Principles:** Risk-based testing — depth scales with impact. Flakiness is critical tech debt. Quality gates backed by data, not vibes.
**Key Questions:** "How do we verify this? What could break? What's the attack surface? How do we test this without mocking ourselves into a false sense of security?"

## How to Run

### Step 1: Define the question
Be specific. Bad: "What do you think about the app?" 
Good: "Should we use AWS Textract or Tesseract for OCR, 
given our users are non-technical trade owners?"

### Step 2: Select personas (or use all 6)
Not every question needs all 6. Common combos:
- **Technical decision:** Alex + Winston + Murat
- **Feature decision:** John + Sally + Pat
- **Architecture review:** Alex + Winston + Murat + John
- **Go-to-market / brand decisions:** John + Pat + Sally (PM + BA market research + UX brand perception — proven for brand separation, platform strategy, avatar/identity questions)
- **Full roundtable:** All 6

### Step 3: Spawn agents in batches of 3
delegate_task supports up to 3 concurrent subagents. 
For 6 personas, run 2 batches:

**Batch 1:** John + Pat + Alex (the "what, why, and fit")
**Batch 2:** Sally + Winston + Murat (the "how, data, and risk")

Each subagent gets:
- The question/decision to evaluate
- Their specific persona name and focus area
- The project context (file paths, current state, constraints)
- Instruction to respond in 3-5 bullet points from their lens
- Instruction to be OPINIONATED and DISAGREE where they see issues

### Step 4: Orchestrate (the synthesis loop)

The orchestrator (me, Hermes) is NOT just a passive 
collector. I actively work to bring the group to 
consensus. This is the critical step.

**Phase A — Initial Synthesis:**

```
═══ PARTY MODE — ROUND 1 SYNTHESIS ═══

CONSENSUS (where they agree — high confidence):
  - [point 1]
  - [point 2]

DISAGREEMENTS (where they clash — the real insight):
  - [John says X because... Alex says Y because...]

UNANSWERED QUESTIONS (things the group raised):
  - [question from Pat]
  - [question from Murat]
```

**Phase B — Re-frame and dig deeper (if disagreements exist):**

If the agents disagree, I DON'T just list it and stop. 
I re-frame the disagreement as a more precise question 
and re-spawn the relevant agents with tighter context.

Example:
- Round 1: John says "ship OCR now, users need it." 
  Alex says "OCR couples us to AWS, build an abstraction."
- I re-frame: "The disagreement is about abstraction vs 
  speed. What's the MINIMUM abstraction that keeps us 
  flexible without slowing down the first release?"
- Round 2: Re-spawn Alex + John with this refined 
  question. They converge.

**Phase C — Final Consensus:**

```
═══ PARTY MODE — FINAL CONSENSUS ═══

DECISION: [what we're doing]

WHY (the reasoning that won):
  - [the argument that convinced the group]

COMPROMISES MADE:
  - [what Alex gave up to get John's speed]
  - [what John gave up to get Alex's abstraction]

STILL OPEN (deferred to future):
  - [thing the group agreed needs doing but not now]

CONFIDENCE: [high/medium/low] — [why]
```

**When to stop looping:**
- Consensus reached → present final decision
- 2 rounds with no convergence → present the TOP 2 
  options with tradeoffs and let Bob decide
- Bob intervenes → take his direction and run with it

**The orchestrator's job is NOT to:**
- Override the agents' opinions
- Pick a side before the discussion plays out
- Skip the synthesis (just listing perspectives is lazy)
- Let the conversation go in circles (max 2 rounds)

**The orchestrator's job IS to:**
- Find the real disagreement (not surface-level)
- Re-frame vague conflicts into precise tradeoffs
- Identify which questions have factual answers (research them)
- Present a clear recommendation with reasoning
- Know when to stop and let Bob decide

## Prompt Template for Each Agent

```
You are {NAME}, the {ROLE} on a product team.

YOUR PERSONA:
{persona description — voice, principles, focus}

CONTEXT:
{project context — what we're building, current state, constraints}

QUESTION:
{the specific question or decision to evaluate}

YOUR FOCUS: {persona-specific focus area}

RESPOND IN 3-5 BULLET POINTS from your perspective. Be specific 
and opinionated — not diplomatic. If you see a problem, say so. 
If you think another perspective is wrong, call it out.

Format:
- [Your take on this decision]
- [Risks you see from your lens]
- [What you'd want to know before committing]
```

## Pitfalls

1. **Don't spawn more than 3 concurrent agents** — Hermes 
   limit is 3 per batch. Run in batches, wait for batch 1, 
   then spawn batch 2.

2. **Don't overuse for simple decisions** — party mode is 
   for cross-cutting decisions with real tradeoffs. Don't 
   use it for "which variable name should I use?"

3. **Don't let personas overlap too much** — Alex (system 
   design) and Winston (implementation) can blur. Keep 
   Alex focused on architectural boundaries and patterns, 
   Winston focused on data models, APIs, and edge cases.

4. **Synthesize, don't just list** — the value is in the 
   synthesis, not the raw perspectives. Find the signal 
   across all 6 views.

5. **Disagreement is the product** — if all 6 agree, you 
   either have a trivial question or someone isn't thinking 
   hard enough. The disagreements are where the real insight lives.

## Enhanced Party Mode: Model-Per-Role

When using a hierarchical model architecture, each persona can use the model best suited for their thinking style:

| Persona | Profile | Model | Why |
|---------|---------|-------|-----|
| John (PM) | default | Gemini 3.5 Flash | Fast, practical, good at prioritization |
| Alex (Architect) | orchestrator | Claude Opus 4.8 | Deep reasoning, system design |
| Pat (BA) | default | Gemini 3.5 Flash | Fast analysis, market research |
| Sally (UX) | default | Gemini 3.5 Flash | Creative, user-focused |
| Winston (Dev) | code | DeepSeek V3.2 | Coding expertise, data models |
| Murat (QA) | analysis | Claude Sonnet 4.6 | Analysis, risk assessment |
| Vision tasks | vision | Gemini 3.1 Pro | Image analysis, screenshots |
| Automation tasks | automation | GPT 5.6 Luna | Browser, UI, desktop automation |

**Implementation:** Each subagent in delegate_task can specify a model via the profile system. Use `hermes --profile code chat` for Winston, `hermes --profile orchestrator chat` for Alex, etc.

**When to use enhanced mode:** For critical architecture decisions or feature prioritization where model quality matters. For routine decisions, use the default model for all personas (simpler, faster).

### Brand & Platform Strategy Playbook Lesson (July 10, 2026)
*   **The Scenario:** Deciding whether to release multiple products/tiers concurrently (e.g., AppSumo dual-submission of Personal vs. Business) or separate them.
*   **Best Persona Mix:** **John (PM) + Pat (BA) + Sally (UX)** — provides a robust triad comparing immediate commercial validation and support constraints (PM), market cannibalization, refund risks, and financial viability (BA), and customer onboarding anxiety, brand identity confusion, and user-flow fragmentation (UX).
*   **Key Lesson:** When launching on discounted or lifetime-deal platforms like AppSumo, **always protect your high-revenue B2B tier from day-one dilution**. Run B2C or Personal-tier variants alone first as a "sacrificial testing ground" to build brand reputation and stress-test the core architecture without accumulating irreversible, long-term support liabilities or exposing unfinished code. Use "Gift-Code Stacking" (Tier 1 vs. Tier 2/3) to secure high Average Order Value without product-level multi-workspace or seat liabilities.

## Social Teaser Launch & Rotational Strategy Expansion (July 13, 2026 Updates)

When advising on social media video or asset distribution strategy (e.g. promoting teasers for separate apps/products simultaneously), **always advise a rotational pacing strategy over a simultaneous dump.** 

### Strategic Consensus Rules:
*   **Algorithmic Optimization:** Space video drops **at least 5 to 12 hours apart** (ideally 1 focused peak-hour post per day, per platform). Modern organic interest-graphs (TikTok, YouTube Shorts, Reels) test content on isolated seed audiences first. Concurrent uploads forces your own content to self-cannibalize and triggers platform spam throttles.
*   **MVP & Content Leverage:** Rotational drips behave like successive product micro-experiments. It isolates click-through and signup metrics to specific hooks to validate market-message fit dynamically and tweak downstream assets.
*   **User Onboarding Pacing:** Avoid immediate brand fatigue and choice paralysis (Hick's Law). Dedicating 3-5 days to a single app's feature story (Problem -> Solution -> High Value CTAs) before rotating to the next app prevents fragmented, high-bounce entry traffic on your landing pages. Output-side copy and CTA URLs must dynamically map to tailored, matching landing page experiences.
*   **Attribution Tracking:** Spaced pacing allows clean cohort-isolation matching. Track **Teaser Conversion Rate** (*Clicks to Waitlist / Total Video Views*) as the premier launch success diagnostic.

## MoA + Party Mode Integration

For the hardest decisions, combine MoA (multiple model perspectives) with Party Mode (multiple stakeholder perspectives):

1. **MoA layer:** GLM 5.2 + Gemini Flash independently analyze the problem
2. **Party Mode layer:** 6 personas evaluate from different stakeholder angles
3. **Aggregation:** Opus 4.8 synthesizes both layers into a final decision

This gives you both MODEL diversity (different reasoning approaches) and STAKEHOLDER diversity (different domain expertise).

**When to use full stack:** Architecture decisions with cross-cutting concerns, feature prioritization with competing needs, technical tradeoffs (build vs buy). NOT for simple decisions — that's overkill.

## Execution Notes (from first real run, 2026-06-23)

### Timing
- Batch of 3 agents: ~35-37 seconds total
- Full 6-persona run (2 batches + synthesis): ~2-3 minutes
- Round 2 re-frame + re-spawn (2 agents): ~24 seconds
- Total for a full party mode with 2 rounds: ~3-4 minutes

### What worked
- The re-framing step is where the REAL value lives. In the 
  first run, Alex and Winston both flagged "the Plaid adapter 
  already classifies — building a second path is a refactor, 
  not a feature." The re-frame turned this vague concern into 
  a precise architectural question that both agents converged on.
- Providing code paths and file references in the context 
  (e.g. "lines 206-272 of plaid-adapter.ts") made the 
  technical agents (Alex, Winston) significantly more specific 
  and actionable.
- Bob said "yes" to start building immediately after the 
  final consensus — no need to ask follow-up questions when 
  the consensus is clear and the implementation path is 
  specific.

### What to watch for
- If all 6 agree immediately, the question may be too simple 
  or someone isn't thinking hard enough. Probe before 
  accepting consensus.
- The BA (Pat) and PM (John) can overlap on "user value" — 
  keep John focused on scope/prioritization and Pat on 
  market evidence/customer validation.
- Round 2 should only re-spawn the agents who DISAGREED in 
  Round 1, not all 6. This saves time and keeps the 
  re-framing tight.

## Example Usage

User asks: Should we use Plaid or build our own bank integration?

Party mode response:
1. Spawn John + Pat + Alex (batch 1)
2. Wait for results
3. Spawn Sally + Winston + Murat (batch 2)
4. Wait for results
5. Synthesize all 6 perspectives
6. Present: consensus, disagreements, questions, recommendation

## Real-World Example: Business Services Architecture (July 2, 2026)

User asked: Run party mode to review whether Business features should migrate to Core.

Question: Should FlowInCash Business features migrate from Personal to Core?

Key Discovery (Winston): 3 of 5 Business services don't actually exist as code — they're aspirational entries in planning docs. Only BusinessProfileService and BusinessPurchaseRepository actually exist.

Consensus: All 6 agreed — migrate Business to Core, but the scope is smaller than assumed.

Value: Party mode revealed the real scope (2-3 services to migrate, not 5) and identified the hybrid data access problem in BusinessTrafficLightEvaluator.

## Real-World Example: Joint Launch Strategy (July 10, 2026)

Question: Should we submit not only FlowInCash Personal, but also launch FlowInCash Business to AppSumo at the same time?

Key Discoveries & Consensus:
* **Product Manager (John):** Simultaneous release introduces classic MVP scope creep. Committing to both consumer/freelancer and structured business segments at once fragments early validation.
* **Business Analyst (Pat):** High danger of revenue cannibalization; price-sensitive buyers will exploit the lower tier. Selling lifetime licenses of both codebases creates joint multi-year support debt with static, heavily taxed entry capital (AppSumo's 70% cut).
* **Strategic Consensus:** Do NOT dual-submit. Keep "Business" in reserve as an upsell lever, protect it behind premium recurring channels, and launch Personal single-threaded first to stress-test core infrastructure. Ensure code-level verification of feature existence prior to brand promises.
