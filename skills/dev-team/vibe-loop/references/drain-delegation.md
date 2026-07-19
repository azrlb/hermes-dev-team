---
name: drain-delegation
description: Drain-specific orchestration overlay that layers on top of vibe-loop methodology. Loaded by orchestrated-drain for autonomous bead processing. Defines the operational concerns unique to drains (exhaustion, multi-project discovery, routing, escalation) without restating the BMAD methodology itself.
version: 1.0.0
metadata:
  hermes:
    tags: [drain, orchestration, overlay, beads]
    layer: operational
    related_skills: [dev-team/vibe-loop, dev-team/bead-execution, dev-team/shared-execution]
---

# Drain Delegation Overlay

This reference defines the **operational layer** unique to autonomous bead
processing. It sits ON TOP of the full BMAD vibe-loop pipeline — the methodology
is in `vibe-loop/SKILL.md`, the execution lifecycle is in `bead-execution` and
`shared-execution`, and this document captures what orchestrators need to know
when routing work through drains specifically.

## When This Applies

Drains are recurring cron-triggered autonomous sessions that process existing
beads. They have unique operational constraints that don't exist in interactive
daytime feature work:

- **No human present** — escalation chains must be autonomous
- **Token budget limits** — exhaustion checks prevent runaway costs
- **Multi-project pools** — beads may live across multiple repos
- **Time-of-day scheduling** — overnight vs daytime drains have different contexts
- **Bead state awareness** — must detect stale claims, locked beads, gating conditions

Interactive daytime work (Bob + agent in chat) uses `vibe-loop` directly without
this overlay. Only autonomous bead processing (cron or manual drain invocation)
needs this operational knowledge.

## Layer Relationship

```
vibe-loop/SKILL.md (methodology — what phases exist)
  ↓ applies to
drain-delegation.md (operational — how drains run phases)
  ↓ delegates to
bead-execution + shared-execution (lifecycle — per-bead state machine)
```

Drains use the vibe-loop phases selectively: typically skipping Analyst/PRD/
Architecture (beads are already planned) and running primarily in Phase 10
(Dev) + Phase 10c (Quinn review). The orchestration concerns in this document
are about HOW the drain selects, routes, and executes beads — not about the
phases themselves.

---

## Section 0: Exhaustion Check (Pre-Triage)

**When:** Run IMMEDIATELY after `bd list`, before any per-bead triage.
**Why:** If the pool is exhausted (all beads blocked/human-gated), running
`bd show` on every bead wastes tokens — the classification is identical each
run.

```bash
EXHAUSTION_COUNT=$(ls ~/.hermes/drain-logs/$(date +%Y-%m-%d)/<project>-*.json 2>/dev/null \
  | xargs grep -l '"exit_reason": "pool-exhausted"' 2>/dev/null | wc -l)
if [ "$EXHAUSTION_COUNT" -ge 2 ]; then
  echo "Pool exhausted $EXHAUSTION_COUNT times today — skipping per-bead triage"
  # Reuse skip list from most recent log, increment count, write report.
  # Do NOT run bd show on any bead.
fi
```

**Trigger point in drain flow:**
```
Pre-flight bd list → IF exhaustion_count >= 2: skip to LOG
                     ELSE: full per-bead triage
```

Overflow check still runs after primary exhaustion — see `scripts/overflow-quick-triage.sh`.

---

## Section 1: Multi-Project Discovery

When cron targets a **label** (e.g., `appsumo-fast-track`) rather than a single
project, beads may live in any project with that label. Search across the
project map:

```bash
for dir in /media/bob/C/AI_Projects/*/; do
  if [ -d "$dir/.beads" ]; then
    result=$(cd "$dir" && bd list --state open --flat --label <target-label> 2>/dev/null)
    if [ -n "$result" ]; then
      echo "=== $(basename $dir) ==="
      echo "$result"
    fi
  fi
done
```

**Known project locations** (maintained in `references/project-locations.md`):
FlowInCash, FlowInCash-Core, FlowInCash-CloudComm, FlowInCash-Practice,
KidSplit, Crispi-app, FliC-MicroApps, Auto-Claude, LivingApp-Sidecar,
LivingApp-Platform, BeadsBoard, Crispi-MicroApps, QChat, hermes-dev-team.

Also check `/home/bob/.beads-planning/` for planning beads.

---

## Section 2: Drain Routing Table

When the orchestrator classifies a bead's task type, route to the appropriate
specialist profile:

| Task Type | Specialist Profile | Model |
|---|---|---|
| Simple file edit / routine fix | default | Gemini 3.5 Flash |
| Complex bug fix | architect | Opus 4.8 |
| Build feature (TypeScript/Python) | code | DeepSeek V3.2 |
| Write tests | code | DeepSeek V3.2 |
| Refactor code | code | DeepSeek V3.2 |
| Design architecture | architect | Opus 4.8 |
| Plan a feature | architect | Opus 4.8 |
| Code review / research / report | analysis | Sonnet 4.6 |
| Screenshot / document verification | vision | Gemini 3.1 Pro |
| Video production / compositing | video | Gemini 3.5 Flash |
| Browser automation / UI testing | automation | GPT 5.6 Luna |

**Self-handle rule:** Architecture and planning are not delegated to specialists —
the orchestrator (architect profile, Opus 4.8) handles directly. Only implementation
tasks get delegated.

**Model selection principle:** Match model to task complexity. Small fixes don't
need Opus 4.8. Complex reasoning doesn't need DeepSeek V3.2. Wrong routing wastes
tokens and produces worse results.

---

## Section 3: Multi-Tiered Escalation

When iterative implementation fails after max retries (typically 3-5), escalate
through tiers without human intervention:

**Tier 1 — Specialist with new approach (code/default profile):**
Re-delegate to the same specialist with explicit "try a different approach"
instruction, synthesizing all prior failed attempts, quality gate feedback, and
relevant diagnostics into the context.

**Tier 2 — Diagnosis & research (analysis profile):**
`delegate_task` to analysis profile (Sonnet 4.6). Goal: research the error, deep
dive into logs, identify patterns, survey GitHub issues / Stack Overflow /
changelogs / pitfall documentation. Returns a diagnostic report with proposed
solutions that re-informs Tier 1.

**Tier 3 — Deep reasoning & rearchitecture (architect / Opus 4.8):**
The orchestrator itself handles this tier directly. Analyzes all accumulated data
(code, tests, error logs, research results), challenges assumptions, proposes 2-3
alternative architectures, prototypes in isolation. May invoke Mixture of Agents
(`/moa` with `z-ai/glm-5.2` and `google/gemini-3.5-flash` as advisors) for
multi-model consensus on exceptionally hard reasoning problems.

**Tier 4 — Structured blocking bead (autonomous resolution only):**
If even Opus + MoA cannot resolve the bead, file a P0 blocker bead containing
ALL accumulated research, failed approaches, alternative architectures, and
diagnostic context. Tagged `needs-deep-research-round-2`. This hands the problem
to a FUTURE autonomous session (or a targeted human intervention) — NOT to Bob
for code issues. Bob does not get code-level escalations.

**Critical principle:** No human dead ends for code issues. Every failure path
resolves autonomously through Tier 1→4.

---

## Section 4: Drain-Specific Lifecycle

Drains compose other skills for the per-bead state machine:

**Execution:** `bead-execution` skill handles the full claim → implement →
test → quality review → commit → close cycle. See `dev-team/bead-execution`
for systematic workflow with robust iteration and escalation.

**Quality gates:** `shared-execution` skill enforces quality gates (self-review,
Quinn adversarial review, Murat test quality, traceability). See
`dev-team/shared-execution` for the canonical quality process.

**Logging:** `drain-logger` skill writes structured JSON output per drain session.
See `dev-team/drain-logger` for the drain log schema.

The orchestrator's role is to COORDINATE these — not to replace them. When
running a drain, load the appropriate skill at each phase rather than
re-implementing its logic.

---

## Section 5: Rollback and Recovery Patterns

**When orchestrated-drain fails:**
- Backup exists at `/local-AI-Stack/home-hermes/skills/dev-team/orchestrated-drain.bak-<timestamp>/`
- Restore: `cp -r orchestrated-drain.bak-<timestamp>/ orchestrated-drain/`
- Takes ~2 minutes

**When cron fails mid-run:**
- Drain logger may have written partial JSON
- Check `~/.hermes/drain-logs/<date>/<project>-<timestamp>.json`
- Next cron run will detect and handle

**When a specialist fails:**
- Orchestrator catches and attempts Tier 1-4 escalation
- No automated rollback — specialist work is isolated, doesn't corrupt state

---

## Section 6: Drain-Specific Pitfalls (Reference Only)

For detailed pitfall patterns (bd list flat output quirks, feature-branch issues,
cross-repo code targets, live-session deferral for daytime drains, grep pattern
gotchas, etc.), see the main `orchestrated-drain` skill in the live Hermes
directory. That file documents accumulated real-world pitfalls with concrete
scenarios, bash scripts, and verification patterns.

This reference does NOT replicate those patterns — it points to them.

---

## Cross-References

- `dev-team/vibe-loop` — canonical BMAD methodology
- `dev-team/orchestrator-prompt` — routing table source
- `dev-team/bead-execution` — per-bead execution workflow
- `dev-team/shared-execution` — quality gates
- `dev-team/drain-logger` — structured log output
