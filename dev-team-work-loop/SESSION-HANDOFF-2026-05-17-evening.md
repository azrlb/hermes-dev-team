# Session Handoff — 2026-05-17 (evening)

> Companion to the morning handoff (`SESSION-HANDOFF-2026-05-17.md`) which covered the Sessions 6+8 Pact infra ship. This file covers the evening's coordination-layer work: introducing the Session-Start Orientation Protocol so BMAD agents and hermes overnight runs can sync via beads notes + focus labels instead of Bob copy-pasting prompts.

## TL;DR

**Bob's pain point:** he's been the manual switchboard — opening three terminals each day, one per project, and copy-pasting prompts into each BMAD agent and hermes. The point of contact was the bead but there was no orientation protocol, so each session started cold.

**This session's fix:** introduced a per-project "Session-Start Orientation Protocol" in each project's CLAUDE.md, plus a `focus` label convention (one bead per project carries it at a time), a `set-focus` helper, and an addition to hermes overnight cron prompts so they write structured bead notes per processed bead. The bead becomes the conversation thread; copy-paste prompts go away.

**Independent of this session:** TEA closed the loop on `beads_FlowInCash_Core-nty` by landing the cross-repo bd-gate enforcement work in `hermes-dev-team` (commit `5dca98c`). All four pieces of vibe-loop discipline (pre-close hook with file-scope test runner, attestation v2 default with HEAD SHA, test-modification split 5a/5b/5c) are live. Autonomous overnight drains can no longer close beads while affected-scope tests are red.

## What landed in code

### `LivingApp-Sidecar` — commit `d2066fb` (main, NOT pushed)
- `CLAUDE.md` — Session-Start Orientation block added near the top (43 lines).

### `Crispi-app` — commit `d6de16d` (eval/hybrid-test-push-1.4, NOT pushed)
- `CLAUDE.md` — same block (43 lines).
- Note: Crispi already had a focus-label convention in active use before this commit (Sally's hand-off note on `eq19` referenced it). The CLAUDE.md addition formalizes the convention so future Claude Code sessions auto-orient.

### `LivingApp-Platform` — commit `9e833f4` (feature/upstream-findings-ddl, NOT pushed)
- `CLAUDE.md` — same block (43 lines).

### `FlowInCash-Core` — commit `6df191b` then reverted during TEA's rebase
- The same CLAUDE.md addition was committed and then deliberately removed from working tree during a subsequent TEA pull --rebase. FIC-Core does **not** carry the Session-Start Orientation block — intentional, leave as-is. FIC-Core's discipline is AGENTS.md-centric; the orient-then-confirm pattern lives there if anywhere.

### `hermes-dev-team` — commits `7cae3d5` + (TEA's `5dca98c`)
- `7cae3d5` (dev, NOT pushed): `scripts/set-focus` bash helper. Idempotent. Pages bd writes 3s apart to avoid the beads-CLI write wobble. Usage: `set-focus <bead-id>` from inside the target project's repo.
- `5dca98c` (dev, NOT pushed — TEA's commit, not from this session): `fix(bd-gate)` — vibe-loop integrity gates for `nty`. Pre-close hook now derives test command from touched files (scope-aware), attestation writer emits v2 JSON by default with verifiable HEAD SHA, test-modification check splits into 5a (deletion/rename blocks), 5b (>20% AND ≥10-line shrink blocks), 5c (softened-assertion patterns block). Test-runner discipline is now structurally enforced.

### `/local-AI-Stack/home-hermes/cron/jobs.json` (not git-tracked)
- Sidecar 02:00 cron prompt — inserted new step `h` before `bd close`: writes a structured note via `bd update <id> --append-notes` with HEAD SHA, files touched, vitest/eslint exit codes, blockers, next-action recommendation. Pace 3s between consecutive note writes (beads-CLI write wobble). Old `h.` (close) renumbered to `i.`, old `i.` (push) to `j.`. JSON validity verified post-write.
- Crispi 04:00 cron — NOT touched (being retuned elsewhere).
- FIC-Core 22:00 cron — NOT touched (hand-tuned for tonight's 8-bead batch).

## Focus beads set this evening

| Project | Focus | Why |
|---|---|---|
| `Crispi-app` | `Crispi-app-eq19` | Preserved Sally's existing focus — MealsPage Yummly redesign "first domino," design decisions locked with Bob today. I initially overrode this with `cwu3.1` (P1 prereq) before the helper's warning prompted Bob to flag; restored. |
| `LivingApp-Sidecar` | `LivingApp-Sidecar-4r7` | GitHub branch protection setup — ~5 min UI clicks, unblocks the y9c drift detector. Clean daytime-friendly Bob-hands work. |
| `FlowInCash-Core` | (none) | Tonight's 22:00 cron drains the 8 ready beads. Tomorrow morning will see what survived. |
| `LivingApp-Platform` | (none) | 0 open issues. |

## Architectural decisions worth knowing

### Beads notes as the bidirectional channel (not a separate handoff file)

Considered: hermes proposed a per-project handoff file that BMAD agents and hermes both read/write. Rejected in favor of bead notes because:
- Notes already exist, are timestamped, append-only, tied to the work itself
- No new file to maintain; no staleness drift if one session forgets to write
- The bead IS the work — its notes are the natural conversation log

Trade-off accepted: write wobble means consecutive `bd update --append-notes` calls need pacing. The Sidecar cron prompt addition explicitly says "pace 3s apart"; the `set-focus` helper does the same internally.

### Orient-then-confirm vs auto-start

Hermes's original proposal was for sessions to auto-start work on the focus bead ("I see 3 ready beads. Starting on cmm."). Rejected — that's the opposite of Bob's "spine of the business, done right, not in a rush" principle. The CLAUDE.md preamble explicitly says: summarize state in 3-4 lines, ask Bob to confirm, do NOT begin work until confirmed.

Cost: 5-second confirmation per session.
Benefit: avoids 30-minute wasted sessions on the wrong bead. Today's incident with `eq19` (where I overrode Sally's deliberate focus) is exactly the failure mode this prevents.

### Why hermes-dev-team has no beads tracker

Considered during this session: should we `bd init` here so cross-repo infra work has a tracker? Deferred. The cron infra changes I made tonight (and TEA's bd-gate work) live in this repo but were tracked via the related FIC-Core bead (`nty`) instead. Decision: revisit if hermes-dev-team starts accumulating its own backlog independent of consumer-project work.

## Memory added

`/home/bob/.claude/projects/-media-bob-C-AI-Projects-hermes-dev-team/memory/feedback_focus_label_preserve.md` — when `set-focus` reports clearing another bead's focus, pause and surface to Bob. Logged today's `eq19` incident as the concrete trigger.

## Push commands (Bob to run when ready)

All five commits are local. Recommended push order (any order is fine — no cross-repo dependencies):

```bash
git -C /media/bob/C/AI_Projects/LivingApp-Sidecar push origin main
git -C /media/bob/C/AI_Projects/Crispi-app push origin eval/hybrid-test-push-1.4
git -C /media/bob/C/AI_Projects/LivingApp-Platform push origin feature/upstream-findings-ddl
git -C /media/bob/C/AI_Projects/hermes-dev-team push origin dev
# FIC-Core: nothing of mine to push — TEA's rebase cleaned it
```

## Tonight's overnight schedule

| Time | Project | Will it do anything? |
|---|---|---|
| 22:00 | FlowInCash-Core | YES — drains tonight's 8 hand-tuned beads, with TEA's bd-gate enforcement now live in the loop. |
| 02:00 | LivingApp-Sidecar | NO-OP — 0 ready beads. The new bead-notes step in the prompt gets first real exercise whenever Sidecar's queue refills. |
| 04:00 | Crispi-app | YES — drains the 10 ready cwu3-cluster items. (Cron prompt is being retuned elsewhere; bead-notes step not added to it this session.) |

## Outstanding / residual

1. **FIC-Core CLAUDE.md** has no Session-Start Orientation block. Confirmed intentional (system signal during this session). If you decide later you want the convention there too, the block can be re-applied from any of the other 3 project CLAUDE.md files — verbatim copy.
2. **Crispi 04:00 cron prompt** needs the bead-notes step folded in whenever its current retune lands.
3. **FIC-Core 22:00 cron prompt** is hand-tuned for tonight's batch; bead-notes step can fold in at the next re-tune (likely tomorrow when the new batch is queued).
4. **Sidecar working tree** has unrelated unstaged work (`.beads/metadata.json`, modifications to `_bmad-output/planning-artifacts/*.md`, `_bmad-output/project-context.md`). Not from this session — Bob's call when/whether to handle.
5. **`hermes-dev-team` working tree** has pre-existing unstaged work (HOW-TO-USE.md edits, skill SKILL.md edits, untracked `.agents/`, `_bmad/`, dev-team-work-loop files). Not from this session.
6. **hermes-dev-team beads tracker** not initialized. Cross-repo infra work currently tracked via consumer-project beads (e.g., `nty` for tonight's bd-gate). Decision deferred.

## Three non-negotiable reminders

1. **The orient-then-confirm protocol is live in Sidecar, Crispi, Platform CLAUDE.md** — tomorrow morning when Bob opens Claude Code in any of those, the agent will check `bd list --label=focus`, find the focus bead, summarize, and ask "proceed?" Bob's input is ~5 words.
2. **Don't override a focus bead silently.** If `set-focus` warns "cleared from N other bead(s)", read the displaced bead first. Today's incident (overriding `eq19`) is the canonical example. Memory note logged.
3. **TEA's bd-gate enforcement is now structurally protecting all overnight drains.** Tonight's FIC-Core 22:00 drain runs with the pre-close hook live for the first time. If a bead closes while affected-scope vitest is red, that's a regression in `5dca98c` itself — surface immediately.

---

*Author: Claude Opus 4.7 (1M context), in conversation with Bob.*
*Companion to: SESSION-HANDOFF-2026-05-17.md (morning Pact infra session).*
*Next handoff: tomorrow morning after the orient-then-confirm protocol gets its first real exercise.*
