# Session Handoff — 2026-05-08

**Read first.** Then check `git log` since `ea85def` for what landed
2026-05-07 evening.

## Status at end of 2026-05-07

**The kanban-native dev-team is production-ready on the laptop side.**
4 slices committed and proven against real cloud LLMs (MiMo via Nous
Portal):

```
4bd8508  feat(kanban-slice-5): vibe-plan dual-writes bd + kanban
fec52d3  feat(kanban-slice-3): role-boundary discipline — 8/8 PASS
a32f082  test(kanban-real-story): cloud round-trip via MiMo
db1921f  feat(kanban-slice-2.5): all 5 blocker-type branches
81b1c21  feat(kanban-slice-2): reactive escalation loop
33fc14d  feat(kanban-slice-1): all 8 acceptance assertions
```

Real-story acceptance: 8/8 in ~7 min wall-time. No shims on workers.
fix(<id>): convention enforced. Working tree clean. Lander idempotent.

`HOW-TO-USE.md` (next to this file) covers the day-to-day workflow.

---

## 1. What's still ahead

In priority order for the 24/7 unattended LivingApp ecosystem goal:

### Slice 4 — Railway deploy + Telegram report
**Why required:** the LivingApp ecosystem deploys app + sidecar paired
containers to Railway. Slice 4 is the dev-team's "ship to production"
step. Without it, the kanban dev-team builds artifacts that never go
anywhere.

**What it needs:**
- New skill: `dev-team/railway-deploy` — wraps `railway up` with
  paired-container provisioning, postgres-LVV row scoping, JWT
  `appName` claim wiring.
- New skill: `dev-team/completion-report` — Telegram message
  summarizing the deploy + audit-row trail.
- New profiles: `hermes-deployer`, `hermes-reporter`.
- New fixture: `tests/kanban-slice-4/` with a real branch + Railway
  test target (or a railway-shim for local fixture runs).

**Estimated effort:** 3–4 hours for the SKILL.md + fixture + first
green test. Real Railway deploy adds time depending on auth setup.

### PRD additions (LivingApp-Platform + LivingApp-Sidecar)
**Why required:** both PRDs were written before kanban was added to
Hermes. Several FR sections describe custom orchestration that kanban
now does for free. Updates needed:

| PRD | Section | Change |
|---|---|---|
| Platform | New §"Operations Substrate: Hermes Kanban" | Calls out kanban as the queue + scheduler + retry engine + audit + dashboard for all sidecar autonomous operations |
| Platform | FR-P3 (self-healing) | Each detected error = kanban task. Escalator branches handle blockers (Slice 2.5 pattern). |
| Platform | FR-P4 (support concierge) | Each support query = kanban task. Multi-turn conversation = task comments. Escalation = kanban_block → Telegram. |
| Platform | FR-P7 (growth experiments) | Each experiment = kanban task. "Max 3 concurrent per surface" = dispatcher concurrency limit. Auto-revert = blocked-event watcher. |
| Sidecar | Epic E-D (briefings) | Briefing = recurring kanban task on cron-create. Anomaly alerts = same monitoring worker creating remediation tasks. |
| Sidecar | Epic E-E (autoresearch) | Loop 1 = parent task fans out 50 children. Cross-pollination = new tasks created from completed ones. |
| Sidecar | Epic E-I (skill library) | Auto-generated skills = kanban tasks awaiting curator approval (kanban_block-pattern). |
| Sidecar | New Epic E-K | "Sidecar Kanban Operations" — provisioning the dispatcher in each Railway sidecar deploy, dashboard at sidecar's `/ops`, etc. |
| Sidecar | §2.1 inherited stack | Add `kanban-orchestrator` and `kanban-worker` skills to the inherited Nous Hermes capabilities |

**Estimated effort:** 1–2 hours for thoughtful PRD edits. Best done
in a focused session, not interleaved with code work.

### Fragility fix — assertion race in real-story fixture
**The issue:** the `assert-real-story.sh` script's assertion 7 (lander
idempotency) sometimes fires while the lander is still completing
in the background, then false-FAILs. Re-running 30 seconds later
passes. Slice 1's `assert-happy-path.sh` has the same flicker.

**The fix:** before assertion 7, add a "wait for terminal state" loop
that polls the kanban task list until ALL non-archived tasks are in
a terminal status (`done`, `blocked`, `crashed`, `timed_out`,
`gave_up`). Bound the wait to ~60 seconds; fail loudly if any task
is still `running` or `claimed` after that window.

**Pseudocode for the fix (apply to both `assert-happy-path.sh` and
`assert-real-story.sh`):**

```bash
# At the top of the script, before any assertions:
echo "Waiting for all kanban tasks to reach terminal state..."
deadline=$(( $(date +%s) + 60 ))
while [[ $(date +%s) -lt $deadline ]]; do
  non_terminal=$(hermes kanban list --tenant <T> --json 2>/dev/null \
    | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
non_term = [t['id'] for t in d if t.get('status') in ('running','ready','todo','claimed')]
print(len(non_term))
")
  [[ "$non_terminal" == "0" ]] && break
  sleep 5
done
```

**Estimated effort:** 15 minutes (include in next session's first
maintenance pass).

---

## 2. The PRD additions, in order

If you have ~2 hours for PRD work tomorrow:

1. **Open both PRDs side by side.** The Sidecar PRD inherits from the
   Platform PRD; updates flow Platform → Sidecar.
2. **Add the new "Operations Substrate" section to Platform PRD §3.**
   This is the conceptual frame that the FR-P3/P4/P7 updates reference.
3. **Update FR-P3, FR-P4, FR-P7** with kanban-native paragraphs. Each
   change is ~3–5 lines.
4. **Add Epic E-K to Sidecar PRD** (Sidecar Kanban Operations). Mirror
   the structure of existing epics (Maps to, Acceptance, Stories est).
5. **Add `kanban-orchestrator` and `kanban-worker` to Sidecar PRD §2.1**
   (inherited stack) — they're already auto-loaded by the dispatcher,
   so this is just recording the dependency.
6. **Update Sidecar PRD Epic E-D, E-E, E-I** with kanban-native
   implementation notes. Each is ~2–3 lines.
7. **Run `bmad-validate-prd` if available** (or have the architect agent
   review). Final pass before commit.

**One important nuance:** the kanban substrate the sidecar uses is
the SAME one we built on the laptop. The sidecar provisions its own
`hermes kanban` dispatcher inside its Railway container, with its own
`HERMES_KANBAN_DB`. The sidecar's tenant scoping (`appName`) maps to
kanban tenant strings. This isolation is automatic — different DBs
mean different dispatchers don't see each other's tasks.

---

## 3. The fragility fix

Apply the wait-for-terminal-state loop to both assertion scripts:
- `dev-team-work-loop/tests/kanban-slice-1/assert-happy-path.sh`
- `dev-team-work-loop/tests/kanban-real-story/assert-real-story.sh`

After the fix, re-run both fixtures cleanly. They should each pass
8/8 on the first assertion run, no re-runs needed.

---

## 4. The sidecar test (if you want to validate runtime patterns)

`dev-team-work-loop/tests/sidecar-runtime/` (committed tonight)
exercises the kanban substrate against three Sidecar runtime
patterns:

- **Email handling** (FR-P4.7) — inbound email becomes a kanban
  task; worker drafts reply; emits to outbound.
- **Customer support** (FR-P4.1) — chat widget message becomes a
  kanban task; worker resolves via skill OR escalates via
  kanban_block → operator.
- **Bug fix loop** (FR-P3.4) — detected error becomes a kanban
  task; worker matches skill + applies fix; if no skill match,
  escalates to deep-research-bridge.

Run all three:
```bash
cd /media/bob/C/AI_Projects/hermes-dev-team/dev-team-work-loop/tests/sidecar-runtime
bash run-all-scenarios.sh
```

The fixture proves: kanban + reactive escalation + role boundaries
work for runtime ops the same way they work for build-time. Same
substrate, different scope. This validates the "Operations Substrate"
PRD section above.

---

## Quick start tomorrow

```bash
cd /media/bob/C/AI_Projects/hermes-dev-team
cat dev-team-work-loop/HOW-TO-USE.md       # how to use the dev-team
cat dev-team-work-loop/SESSION-HANDOFF-2026-05-08.md   # this file

# If you want to validate the sidecar pattern first:
cd dev-team-work-loop/tests/sidecar-runtime
bash run-all-scenarios.sh

# Otherwise: pick one of Slice 4 / PRD updates / fragility fix and start.
```
