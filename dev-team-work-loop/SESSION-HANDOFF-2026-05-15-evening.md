# Session Handoff — 2026-05-15 (evening)

> Companion to the morning handoff (`SESSION-HANDOFF-2026-05-15.md`) which covered Sidecar v2 Sessions 2+3. This file is **forward-looking** — the roadmap for finishing the Sidecar build, written after triaging the bd ready queue and confirming where the build actually stands.

## TL;DR

**Sidecar is ~16% complete by story count (10 of 64 planned stories).** Wave 0 foundation is done; Epic 1 is partially done (3/13); Epics 2 through 7 are entirely backlog (0/~40+). Tonight's session cleaned up tech-debt follow-ups, deferred 4 META design issues to a party-mode session, routed 12 non-work-loop beads with labels, and launched `87y` (Pi RPC lag harness) on the only TDD-ready bead in the queue.

**The biggest gap blocking velocity isn't code — it's story specs.** 30+ planned stories in Epics 2-7 have no spec files written, no TDD test scaffolds, and no beads filed with `story_file=` / `test_file=` metadata. Hermes' work-loop can't execute what doesn't exist in that shape. The next session's highest leverage move is a vibe-loop Phase 7a sprint that writes specs for one epic's worth of stories so Hermes has a real overnight runway.

---

## This evening's work — recap

### Closed (3 beads)
- **vt1** (P3): created `.github/dependabot.yml` with github-actions ecosystem, weekly Monday schedule. Closes the SHA-pin maintenance gap left by `8qu`.
- **o06** (P4): added inline comment to `.github/workflows/ci.yml` documenting the `/app` allowlist trap (Option A — minimum-effort, comment-only).
- **y9c** (P4): added "Verify required check names match runbook" step to `lint-and-typecheck`. Greps ci.yml for the 3 expected check-name strings; fails the job on rename.

### Deferred
- **nt1** (P4) → 2026-05-26: PAN regex refinement waits for 30-day observation period to complete.
- **sgp, il0, 7t8, 7qj** (4 P2 META structural issues) → +30d, labeled `needs-design-session`: each requires party-mode (Winston + Quinn + Mary) before autonomous work-loop dispatch. They're "redesign the seam," not "implement X."

### Routed (12 beads labeled, not closed)
| Label | bds | What it means |
|-------|-----|---------------|
| `needs-bob-action` | 4r7, h48 | GitHub or Railway UI clicks — Hermes work-loop has no UI hands |
| `needs-model-eval-framework` | d39, zji, 3af | Need `hermes-model-eval`, NOT dev-team work-loop |
| `needs-cross-repo-platform` | 6vl | Lives in LivingApp-Platform repo; can't execute from Sidecar |
| `needs-story-spec` | xn2, 6df, 7qa, y77, cmm, vc1 | Need vibe-loop Phase 7a (story-spec generation) before any work-loop dispatch |

### Launched
- **87y** (P2, Pi RPC event-loop lag harness for Story 1.1 AC #6) — dispatched via `hermes chat -s dev-team/vibe-loop --yolo`. Single-story Pattern A. Should land overnight if successful.

### Filed (beads-CLI upstream bug)
- Saved to `dev-team-work-loop/BEADS-BUG-REPORT-2026-05-15.md`. Documents the silent write-loss in `bd update --append-notes` when called in rapid succession (16 writes → 3 stuck, 13 writes → 2 stuck). Includes a project-agnostic probe script for cross-repo audit. Backfill verified the workaround: insert a 2.5s settle delay between writes and writes persist reliably.

### Two pending commits in `LivingApp-Sidecar/main` (not pushed)
- `7ea2cc3 chore(beads): re-close o06, defer nt1, label 12 non-work-loop beads`
- `64a43be chore(beads): backfill 11 audit notes lost to beads-CLI write wobble`

Bob to push when ready: `git -C /media/bob/C/AI_Projects/LivingApp-Sidecar push origin main`

---

## Where the Sidecar build actually stands

Sprint-status snapshot (post-ADR-005/006 reality):

```
Epic 0 — Wave 0 Bedrock                  7/7  ✅ DONE
Epic 1 — Reliable Agent Foundation       3/13 🟡 IN PROGRESS
Epic 2 — Bob's Ops Command Center        0/11 ❌ BACKLOG
Epic 3 — Self-Healing Intelligence       0/7  ❌ BACKLOG
Epic 4 — Growth Autoresearch             0/5  ❌ BACKLOG
Epic 5a — Stripe / Payments              0/4  ❌ BACKLOG
Epic 5b — Financial Intelligence         0/5  ❌ BACKLOG
Epic 6 — UX Services                     0/6  ❌ BACKLOG
Epic 7 — Onboarding / Lifecycle          0/6  ❌ BACKLOG
                                        ───────
                                        10/64  ~16% complete
```

Two architectural pivots reshaped scope mid-build and need accounting:
- **ADR-005 (Sidecar v2 Option B, 2026-05-10):** moved Hermes into its own Railway container. Deleted the subprocess machinery Story 1-18 shipped. Wave 0 partly undid itself.
- **ADR-006 (Division of Labor, 2026-05-12):** retired the kanban Epic E-K. Sidecar = brains/ops; hermes-dev-team = build/coding hands; beads = bridge.

---

## Next steps — the actual roadmap

### Step 1 — Verify 87y morning landing (Bob)

When you wake up, check:
- `git -C /media/bob/C/AI_Projects/LivingApp-Sidecar log --oneline -5` → expect `feat(87y): ...` + `chore(beads): close 87y`
- `bd show LivingApp-Sidecar-87y` → expect `CLOSED`
- `.hermes/sessions/LivingApp-Sidecar-87y.test-result` → expect `PASS <sha>`

If anything's missing, read the morning's pipeline log + this evening's handoff to understand state.

### Step 2 — Bob-only actions (no AI can do these)

These three need Bob's hands; until they're done they stay in the queue forever:
1. **File the beads bug report** — paste `dev-team-work-loop/BEADS-BUG-REPORT-2026-05-15.md` content into a new issue at `https://github.com/gastownhall/beads/issues`. Takes ~5 minutes.
2. **Configure GitHub branch protection** (`bd 4r7`) — Sidecar's `main` needs the 3 required checks per `docs/runbooks/ci-guardrails.md §3`. Without this, the y9c drift detector landed today is half-armed.
3. **Repair Railway auto-deploy hook** (`bd h48`) — fix the GitHub→Railway auto-deploy on `livingapp-sidecar`.

### Step 3 — Launch the cross-project beads-wobble audit (Hermes-driven)

Hermes already filed an internal bd for this. The probe script lives inside the bug report doc. When Hermes runs it across the 5 sibling repos, the result becomes the cross-project paper trail for the upstream issue.

### Step 4 — Run model evals (hermes-model-eval framework, not work-loop)

`d39`, `zji`, `3af` need GPU work, not story execution. Different runner. P1 priority. Outcome feeds the 5-tier router config in `hermes/config.yaml`.

### Step 5 — Finish Epic 1 backlog (10 stories remaining)

**THIS IS THE BIGGEST UNBLOCK FOR VELOCITY.** Currently no Hermes overnight run can touch these stories because they have no story spec files. The plan:

For each of the 10 stories (`1-3`, `1-5a`, `1-5b`, `1-6`, `1-7`, `1-9`, `1-12`, `1-13`, `1-14`, `1-15`):

1. Run **vibe-loop Phase 7a (story-specs)** to generate a story spec in `_bmad-output/implementation-artifacts/`. Each spec needs: AC, dev notes, current repo state table, Locked Architectural Decisions.
2. Run **vibe-loop Phase 7b (tdd)** to generate failing TDD tests in `tests/new/` or `tests/integration/`.
3. **File beads** with `--notes "story_file=... | test_file=..."` so work-loop's VALIDATE step finds the metadata.
4. Then Hermes can dispatch them.

Note: stories `1-3` (skill-router) and the `1-5a/1-5b/1-6/1-13` cluster (hermes-route.ts + session lifecycle) are **single-owner serialized** per sprint-status.yaml — they share files and can't run in parallel. The other 5 Epic 1 stories (`1-7`, `1-9`, `1-12`, `1-14`, `1-15`) are parallel-safe.

**Estimated effort to do all 10 story-specs in one party-mode session:** 1 full day (4-step BMAD discipline: primary-source repo scan → template draft → party-mode adversarial → revise with Locked Decisions). Or 2-3 days at lighter rigor.

### Step 6 — META design session

Before any of `1-3` cluster work begins, resolve the 4 deferred META P2s (`sgp`, `il0`, `7t8`, `7qj`) in a party-mode design session. These are structural questions about the Pi-call lifecycle predicate, audit-event naming, and lint conventions — they shape Stories 1-3+. Resolving after is 10x more expensive.

### Step 7 — Epic 2 onwards: phase the rest of the PRD

Per PRD §10, the rollout is:

| Phase | Epics | Why now |
|-------|-------|---------|
| Phase B | E-D (briefings) + E-J (slash commands) | Once Epic 1 ships, Bob needs operational visibility |
| Phase C | E-E (autoresearch) + E-I (skill library) | Highest learning compound — feeds router tier weights |
| Phase D | E-F (financial) + E-G (UX services) | Revenue and user-facing value |
| Phase E | E-H (dashboard) | After data exists to display |

**Sequencing call to make at the next party-mode:** does Epic 5a (Stripe billing) jump ahead of Epic 2 (Ops Center) because it's revenue-touching? PRD §10 says "Phase B operational first," but business reality might favor "money in the door first." John (PM) owns the call.

---

## Process — how to actually move

Tonight reinforced one pattern:

**The bottleneck is story-spec generation, not coding.** Hermes can chew through implementation overnight; what it can't do alone is the BMAD Phase 7a story-spec writing that needs party-mode review. Bob's time is best spent triggering party-mode sessions for spec generation, then handing off the resulting specs to Hermes for overnight execution.

A workable cadence:
- **Morning:** review what landed overnight. Push any pending commits. Bob-action queue if anything needs UI clicks.
- **Mid-day:** if specs are needed, run a party-mode session for one epic's worth (5-10 stories). Generate specs + TDD tests + file beads.
- **Evening:** launch Hermes overnight on the newly-spec'd backlog. Template 2 (backlog-drain) once we trust the beads wobble doesn't bite — until then, Template 1 (single-story) loops via cron.

---

## Open architectural items

1. **PRD §10 rollout addendum** — owner John (PM). Phase A is done; rollout plan needs revision to reflect ADR-005 / ADR-006 realities (Hermes-in-own-container, no kanban substrate in Sidecar).
2. **Sprint-status.yaml is partly stale** — stories 1-10 and 1-11 landed (see commit `83dab67`) but yaml still shows them as backlog. Refresh during next sprint planning.
3. **ADR-004 superseded but research preserved** — appendix appended this session captures the kanban evaluation reasoning for any future substrate question.
4. **ADR-002 Hermes Upstream Pulse** — should be running on cron per `hermes-dev-team/cron/jobs.json`. Verify it's actually firing weekly.

---

## Known issues / risks

| Issue | Severity | Workaround |
|-------|----------|------------|
| beads-CLI `--append-notes` write wobble | Medium — audit trail integrity | Pace writes at 2.5s, verify+retry. Upstream bug filed. |
| Stale vibe-kanban worktree at `/var/tmp/vibe-kanban/worktrees/a2d5-...` | Low | Cleanup whenever convenient; unrelated to current work |
| Sprint-status.yaml drift | Low | Refresh next sprint planning |
| 60% of bd ready queue is non-executable for work-loop | High — blocks velocity | Step 5 above (write story specs) |
| Stories 1-3 + 1-5/6/13 single-owner cluster | Medium — can't parallelize until META design lands | Step 6 above |

---

## Three non-negotiable reminders

1. **Push the 2 local commits before any other Sidecar work.** They contain audit-trail repairs Hermes will reference.
2. **Don't use Template 2 (backlog-drain) until the beads wobble is fixed upstream OR a verify+retry wrapper lands in dev-team SKILLs.** Template 1 with cron is the safe substitute.
3. **Story-spec generation is the velocity unlock, not code generation.** Bob's time investment goes there.

---

*Author: Claude Opus 4.7 (1M context), in conversation with Bob.*
*Companion to: SESSION-HANDOFF-2026-05-15.md (morning developmental session).*
*Next handoff: tomorrow morning after 87y verification.*
