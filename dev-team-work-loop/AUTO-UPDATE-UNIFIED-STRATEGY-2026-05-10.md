# Auto-Update Unified Strategy — Four Surfaces, One Discipline (2026-05-10)

Status: design proposal (2026-05-10). Author: dev-team session post-D8. Audience: Bob (decision), future implementers (action).

## TL;DR

Auto-update concerns now span **four surfaces** with **two distinct trust levels** (Bob's dev box vs. production Railway). Today, two surfaces are auto-bumped weekly by `auto-update-pi-hermes` cron `770cfee9f064`; the other two (added in the last 72 hours by the Sidecar v2 migration) have **no monitoring at all**.

Recommended unified mechanism: **detection-uniform / action-split.** Extend the existing weekly cron to *detect* drift across all four surfaces, but split the action: dev-box surfaces continue to auto-bump (status quo), production surfaces *alert-only* with the ADR 002 gate criteria status pre-computed. When Hermes Upstream Pulse ships (Story 3.9), the cron retires entirely — the per-tier action policies it encodes survive as Pulse's `act_now` / `plan_bump` / `monitor` mappings.

Estimated effort: ~1 dev session for the cron rewrite (D9, in the same shape as D1's prompt rewrite). No production code touched.

---

## 1. Problem statement

The migration completed on 2026-05-10 (sessions D0–D8) successfully unified the dev-team's auto-update mechanism around canonical `@earendil-works/pi-coding-agent`. That work covered the two surfaces Bob's local machine cares about. But the parallel architectural pivot (ADR 005, Sidecar v2 Option B) introduced **two more surfaces of the same dependency** in the production deploy:

| # | Surface | Where it lives | Pin form today | Update mechanism today |
|---|---|---|---|---|
| 1 | Local Hermes | `/local-AI-Stack/home-hermes/hermes-agent` (NousResearch upstream) | git HEAD | Cron weekly: `git fetch` + `hermes update` |
| 2 | Global Pi binary | `/usr/local/bin/pi` → `@earendil-works/pi-coding-agent` (npm global) | `@latest` | Cron weekly: `npm install -g …@latest` |
| 3 | Sidecar runtime Pi dep | `LivingApp-Sidecar/package.json` line 27 | `"@earendil-works/pi-coding-agent": "^0.74.0"` | **Nothing.** No detection, no alert. |
| 4 | Hermes container pin | `LivingApp-Hermes/Dockerfile` line 14 | `ARG HERMES_TAG=v2026.5.7` | **Nothing.** No detection, no alert. |

**Why uniform handling matters.** All four surfaces consume the same two upstreams (Pi from earendil-works, Hermes from NousResearch). When CVE-2026-XXXXX gets filed against `@earendil-works/pi-coding-agent@<0.75`, surfaces 1+2 get patched by the cron at 03:00 Sunday; surfaces 3+4 silently expose Bob's *production* deploy until someone (Bob, an LLM, a calendar reminder) notices. That's the opposite of what we want — production blast radius should fail *louder*, not quieter, than dev.

The fix is not "add three more crons." The fix is one mechanism that knows about all four surfaces and applies the right policy per surface.

---

## 2. Current state per surface

### Surface 1 — Local Hermes (covered)

- **What:** Bob's local Hermes install at `/local-AI-Stack/home-hermes/hermes-agent`, used by `dev-team/vibe-loop`, the auto-updater SKILL, and Bob's day-to-day `hermes chat` invocations.
- **Pinning discipline:** none. Tracks NousResearch `main` HEAD. As of D3 (2026-05-10), at SHA `d62808c37`.
- **Update mechanism:** cron `770cfee9f064` weekly, runs `git fetch` + `hermes update` if behind.
- **Self-protection:** D1 added a guard that aborts and Telegrams an alert if `git remote -v` doesn't point at `github.com/NousResearch/hermes-agent.git`.
- **Status:** working as designed. Re-enabled in D6 after migration verification.

### Surface 2 — Global Pi binary (covered)

- **What:** `/usr/local/bin/pi` symlink to `/usr/local/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js`. Used by every direct `pi …` invocation Bob or an agent makes from a terminal.
- **Pinning discipline:** none. Tracks `@latest` from npm.
- **Update mechanism:** cron `770cfee9f064` weekly, runs `npm install -g @earendil-works/pi-coding-agent@latest` if behind.
- **Self-protection:** D1 added a guard that aborts if the symlink target path still includes `@mariozechner` (deprecated fork) and refuses to install any package whose npm `deprecated` field is set.
- **Status:** working as designed. D8 swap from `@mariozechner@v0.67.68` → `@earendil-works@0.74.0` complete; cron's guard would PASS on next run.

### Surface 3 — Sidecar's runtime Pi dep (NOT covered)

- **What:** `LivingApp-Sidecar/package.json` declares `"@earendil-works/pi-coding-agent": "^0.74.0"` as a runtime dependency. Loaded in-process via `import { createAgentSession } from '@earendil-works/pi-coding-agent'` per ADR 005's Option B.
- **Pinning discipline:** caret-pin (`^0.74.0`) — *floats* across patch and minor of the 0.74.x line on every fresh `npm install` or `npm ci` (until 0.75.0 ships, after which it's pinned to 0.74.x). Worth flagging — see Open Question #2.
- **Update mechanism:** none. No cron, no Dependabot, no alert. A bump happens only when a human edits `package.json`.
- **Status:** brand-new (added 2026-05-10 as part of session D2's Sidecar v2 prep). **Zero monitoring.**

### Surface 4 — Hermes container `HERMES_TAG` (NOT covered)

- **What:** `LivingApp-Hermes/Dockerfile` line 14 declares `ARG HERMES_TAG=v2026.5.7`. The Dockerfile clones `github.com/NousResearch/hermes-agent.git` at that tag during image build. The deployed Railway container runs whatever Hermes version that tag pinned.
- **Pinning discipline:** exact tag pin. This is a real pin in ADR 002's sense — bumps require a Dockerfile edit + image rebuild + Railway redeploy.
- **Update mechanism:** none. No cron, no alert when a newer NousResearch tag ships, no automated CVE check against the pinned tag.
- **Status:** brand-new. **Zero monitoring.**

---

## 3. Design constraints

Anything proposed here must respect:

### From ADR 002 (`LivingApp-Sidecar/docs/adr/002-upstream-keep-current-strategy.md`)

- **Three "current" dimensions:** security-current, capability-current, direction-current. The mechanism must cover at least security + capability for surfaces 3+4 (production); direction-current is Pulse's responsibility, not this cron's.
- **Bump triggers (line 68–76):** any of {CVE, >90 days old, upstream feature obviates a backlog story, fixes a locally-reproduced bug, cost-regression PR green 3 weeks running}. The mechanism does not need to *evaluate* all five — but for production surfaces it must surface enough information for a human to evaluate them quickly.
- **Cost-regression gate:** every production bump must run a synthetic workload and fail if token spend rises >5%. The cron does NOT bump production surfaces, so it does not run the gate — but it should *report* whether the gate would currently pass (e.g., link to the most recent CI run on the candidate version, if available).
- **Pinning is the default for production.** Production surfaces stay pinned; the cron alerts, it does not auto-bump.

### From the existing cron rewrite (`CRON-AUTO-UPDATE-REWRITE.md`)

- **Self-protection guards are non-negotiable.** Any new check added to the cron must abort + alert rather than guess if it sees a state it doesn't understand (e.g., a Dockerfile that no longer has `HERMES_TAG`, a `package.json` missing the dep, a non-canonical npm package).
- **Telegram is the delivery channel.** All findings end in one Telegram message to Bob. No email, no Slack, no PagerDuty — Bob's existing channel.
- **The cron is v1, Pulse is v2.** Per the existing spec's "Long-term" section, when Story 3.9 ships, this cron retires entirely. The unified strategy must remain compatible with that retirement.

### What's NOT acceptable

- **Auto-bumping production pins** (surfaces 3+4). Violates ADR 002's gate discipline. Cost-regression gate is a CI concern; the cron has no business mutating Sidecar `package.json` or the Hermes Dockerfile.
- **"Track latest" semantics on production.** Both surfaces 3 and 4 are pinned for a reason; relaxing that pin to chase HEAD weekly is exactly what ADR 002 was written to prevent.
- **Three new crons, one per surface.** Multiplies the operational surface, fragments the Telegram digest, and forces three independent prompt-maintenance loops. Worth one line of mention only — see §4 alternatives.
- **Doing nothing for surfaces 3+4 "until Pulse ships."** Pulse is sequenced after Story 3.1 + Story 2.5 (per ADR 002 §"Integration with existing planning"); not in the current sprint. Bridging the gap is the whole point of this doc.

---

## 4. Recommended unified mechanism

### The lens: detection uniform, action split by tier

Two axes, one mechanism:

- **Detection** (does something newer exist than what we have?) — **uniform across all four surfaces.** Same prompt, same Sunday-03:00 cadence, same Telegram digest. The cron already does this for surfaces 1+2; the rewrite extends the *check list* to include surfaces 3+4.
- **Action** (what do we do about it?) — **split by trust tier:**
  - **Dev tier (surfaces 1+2):** auto-bump if behind, with the existing self-protection guards. *Status quo.*
  - **Prod tier (surfaces 3+4):** alert-only, with ADR 002 gate criteria pre-computed in the alert (current pin age in days vs. 90-day clock, latest available version, any open CVE against the pinned version per GitHub Security Advisories API). The cron NEVER edits `package.json` or `Dockerfile`.

This collapses to one cron job, one prompt, one weekly digest. The split is in the prompt's branching logic, not in scheduling or job count.

### Concrete cron prompt extension

The existing prompt (in `cron/jobs.json` job `770cfee9f064`) ends after the Hermes section. Append two new sections before the REPORT block. Pseudocode shape:

```
SIDECAR_PI_DEP (ALERT-ONLY, NEVER MODIFY):
  1. cd /media/bob/C/AI_Projects/LivingApp-Sidecar
     If the directory doesn't exist: ABORT this section, Telegram "Sidecar repo not found at expected path".
  2. Read package.json. Locate dependencies."@earendil-works/pi-coding-agent".
     If missing: ABORT this section, Telegram "Sidecar pi-coding-agent dep missing — investigate".
  3. Parse the version range (e.g., "^0.74.0" → constraint baseline 0.74.0).
  4. Query: npm view @earendil-works/pi-coding-agent version  → latest.
  5. Query: npm view @earendil-works/pi-coding-agent time  → ISO timestamp of when the pinned baseline was published.
  6. Compute: days_since_pin = (now - pin_publish_date).days
  7. Query GitHub Security Advisories API for @earendil-works/pi-coding-agent at the pinned version.
  8. DO NOT EDIT package.json. Even if outdated, even if CVE present.
  9. Capture for report: { current_pin, latest, days_since_pin, cve_present, gate_status }
     where gate_status is one of:
       "PIN_OK"           — within 90 days, no CVE, no action needed
       "STALE_BUMP_DUE"   — >= 90 days, no CVE — bump per ADR 002 schedule
       "CVE_FAST_TRACK"   — CVE filed against pinned version — bump immediately per NFR16
       "DEPRECATED_PIN"   — npm `deprecated` field set on pinned version — investigate

HERMES_CONTAINER_TAG (ALERT-ONLY, NEVER MODIFY):
  1. cd /media/bob/C/AI_Projects/LivingApp-Hermes
     If the directory doesn't exist: ABORT this section, Telegram "LivingApp-Hermes repo not found".
  2. Read Dockerfile. grep for "ARG HERMES_TAG=".
     If missing: ABORT this section, Telegram "HERMES_TAG missing from Dockerfile — investigate".
  3. Extract pinned tag (e.g., "v2026.5.7").
  4. Query GitHub: gh api repos/NousResearch/hermes-agent/releases/latest  → latest tag + publish date.
     If `gh` is unavailable: fall back to `git ls-remote --tags https://github.com/NousResearch/hermes-agent.git | sort | tail`.
  5. Query: GitHub publish date of the PINNED tag (gh api repos/NousResearch/hermes-agent/releases/tags/{TAG}).
  6. Compute: days_since_pin.
  7. Query GitHub Security Advisories API for github.com/NousResearch/hermes-agent at the pinned tag.
  8. DO NOT EDIT Dockerfile. Even if outdated.
  9. Capture for report: { current_pin, latest_tag, days_since_pin, cve_present, gate_status } per the same enum as above.

REPORT (Telegram, single message):
  Pi (global, dev):       …  (existing line)
  Hermes (local, dev):    …  (existing line)
  Sidecar Pi dep (PROD):  v0.74.0 (pinned), latest 0.75.x, 12 days old, no CVE → PIN_OK
  Hermes container (PROD): v2026.5.7 (pinned), latest v2026.5.10, 4 days old, no CVE → PIN_OK
  If any STALE_BUMP_DUE / CVE_FAST_TRACK / DEPRECATED_PIN fires:
    Prefix the entire message with: "⚠ ACTION DUE — see PROD lines below"
  If any ABORT fired in any section: prefix with "MANUAL INTERVENTION NEEDED".
```

Only Sunday-03:00 noise change Bob sees is two extra lines in the weekly digest, plus an upgraded prefix when a real action is due.

### Why this is the right shape

- **One cron, one prompt, one digest.** Three new crons would each repeat the self-protection scaffolding and fragment the report.
- **Prod stays pinned.** The cron can only *report*. To bump, Bob (or a future agent acting on the alert) opens a PR on the relevant repo. That PR runs the cost-regression gate (ADR 002) and Pact tests (ADR 005 Condition 1) as required.
- **Compatible with Pulse retirement.** When Story 3.9 lands, its rating engine subsumes the gate-status mapping (Pulse's `act_now` ≈ this cron's `CVE_FAST_TRACK`; `plan_bump` ≈ `STALE_BUMP_DUE`; `monitor` ≈ `PIN_OK`). The cron's prompt becomes a Pulse fixture, then retires per the existing spec.
- **Self-protection generalizes.** Same abort-on-unexpected-state pattern that D1 added for surfaces 1+2 carries forward: missing repo, missing dep entry, missing build arg → abort + alert, never guess.

### Alternatives considered

**Alt 1 — Three separate crons (one per uncovered surface).** Rejected. Triples the prompt-maintenance burden, fragments the Telegram digest, and forces three independent self-protection scaffolds. No upside vs. extending the one cron.

**Alt 2 — Dependabot/Renovate on the Sidecar + Hermes repos.** Rejected for now (matches ADR 002 §Alternatives #2). Dependabot opens PRs against the repos, which is *closer to the right action* than the cron's Telegram alert — but it covers only the security dimension, doesn't compute the 90-day staleness clock, doesn't surface deprecation, and lives outside the cron's existing self-protection model. Worth re-evaluating *as a complement* to the cron once Pulse ships and the cron retires; not worth adopting alongside the cron in the bridge period.

**Alt 3 — Wait for Pulse (Story 3.9), do nothing in the bridge.** Rejected. Pulse is sequenced after Story 3.1 + Story 2.5; that's at least one sprint away, possibly more. Bridge period needs *some* monitoring on production surfaces 3+4 — even if it's just "every Sunday, tell Bob whether the pin is stale." Better imperfect signal than zero.

**Alt 4 — Make the cron mutate `package.json` and the Dockerfile (auto-PR mode).** Rejected. Would require the cron to have GitHub credentials with write access to Sidecar and LivingApp-Hermes, plus understand each repo's contribution conventions, plus run the cost-regression gate. That's Pulse's job. Out of scope for a 1-session prompt rewrite.

---

## 5. Migration plan

Ordered, smallest changes first. Names a session id (D9) consistent with the existing dev-team migration nomenclature.

### D9 — Cron prompt extension (~1 session, prompt-only)

1. Backup `cron/jobs.json` (in-tree git history is sufficient).
2. Open job `770cfee9f064` in `cron/jobs.json`.
3. Append SIDECAR_PI_DEP and HERMES_CONTAINER_TAG sections to the `prompt` field per §4 above.
4. Update the REPORT block to include the two new lines + the action-due prefix logic.
5. Manually trigger the cron once (don't wait for Sunday) — verify all four sections produce a coherent Telegram digest. Acceptance: digest shows two `PIN_OK` lines for surfaces 3+4 with current pin ages.
6. Commit on `dev` branch, FF-merge style consistent with D0–D8.

**Acceptance criteria:**
- Digest contains four surface lines (1+2 unchanged, 3+4 newly added).
- Self-protection abort fires correctly if `LivingApp-Sidecar/package.json` is renamed temporarily during a test (then restored).
- No production code touched. No `package.json` edit. No `Dockerfile` edit. (Verifiable via `git status` on Sidecar and LivingApp-Hermes after the cron run — clean.)

### D10 (deferred until Pulse ships) — Cron retirement

Per the existing rewrite spec's §"Long-term" — when Story 3.9's Pulse goes live, set the cron's `enabled: false` permanently and add a `paused_reason: "Superseded by Hermes Upstream Pulse — Story 3.9 / ADR 002"`. Leave the prompt intact as historical context. The four-surface knowledge survives in Pulse's signal-gatherer config (where surface 3 = an npm dependency scan, surface 4 = a GitHub releases scan).

### What does NOT change

- Surfaces 1+2: zero change. Cron continues to auto-bump local Hermes + global Pi binary weekly.
- ADR 002: no edit. The cron extension is one mechanical implementation of the policy ADR 002 already prescribes; doesn't change the policy.
- ADR 005: no edit. Sidecar v2 architecture is unaffected; the cron observes pins, doesn't influence Sidecar runtime.
- `learned-fixes/SKILL.md`: no edit. Auto-update concern is operationally separate from the debugging-pattern knowledge base.
- `auto-updater` SKILL (per D7): no edit. SKILL is for human-driven update flows; cron is for automated detection. They share self-protection guards but don't share triggers.

---

## 6. Open questions for Bob

These are honest decisions, not rhetorical questions. Each blocks or shapes the D9 implementation.

1. **Surface 1+2's "track-latest" semantics — intentional dev-env relaxation, or accidental drift from ADR 002?**
   ADR 002 prescribes pinning + 90-day clock for *production*. Bob's local Hermes (surface 1) and global Pi (surface 2) are NOT production — they're the dev box. Tracking HEAD/latest there is arguably correct (eat your own dog food, surface upstream breakage early on the dev box not in prod). If accepted, the doc should explicitly carve "dev tier" out of ADR 002 with a one-line note in this design doc and/or a future ADR addendum. If rejected (dev tier should also pin), then the cron's existing auto-bump behavior for 1+2 is the bigger problem and this doc is mis-scoped.
   **Recommendation:** intentional. Codify by adding a short note to ADR 002 (or a new mini-ADR) that the dev tier opts out of the 90-day clock in exchange for early-warning on upstream breakage.

2. **Sidecar `^0.74.0` caret pin — keep, or move to exact `0.74.0`?**
   Caret means a fresh `npm ci` will install the highest 0.74.x patch, even though the lockfile pins one specific version. ADR 002's "pinning discipline" is more naturally expressed as exact pinning. Two options:
   - **Keep `^0.74.0`:** lockfile (`package-lock.json`) is the real pin; caret only matters when the lockfile is regenerated. Lighter-touch.
   - **Move to `0.74.0` exact:** any version change requires explicit `package.json` edit + PR. Heavier-touch but more visible.
   **Recommendation:** move to exact pin. Aligns with ADR 002's explicit-bump principle and makes Sidecar PR diffs self-documenting on dep changes.

3. **Bridge-period staleness ownership — who acts on the cron's `STALE_BUMP_DUE` alert?**
   The cron will alert, but it can't (and won't) bump. Options for who acts:
   - Bob, manually, when the alert fires (lowest infra, highest reliance on Bob's attention).
   - A second cron that opens a PR on Sidecar / LivingApp-Hermes (effectively "Dependabot built in our cron").
   - The next dev-team session that picks up the alert — surfaced via session-handoff (handoff doc already mentions known follow-ups).
   **Recommendation:** Bob manually for the bridge period. Pulse takes this over post-3.9. Document the alert's expected reaction in the cron's prompt itself ("If gate_status is STALE_BUMP_DUE: this is a TODO for Bob — open a bump PR on the relevant repo at next session").

4. **CVE detection source — GitHub Security Advisories API, or dual-source with `npm audit`?**
   GitHub's Security Advisories cover both repos. `npm audit` only covers npm-published deps (surface 3, not surface 4). Single-source via GitHub is simpler; dual-source might catch npm-only advisories that GitHub hasn't ingested yet (rare but possible).
   **Recommendation:** start single-source via GitHub (simpler prompt, no npm-audit-on-the-Sidecar-repo plumbing). Add `npm audit` for surface 3 only if a real miss occurs.

5. **Cron retirement trigger — auto, or manual confirmation?**
   When Pulse ships (Story 3.9), the existing rewrite spec says "set `enabled: false` permanently." Should that be an action item in Story 3.9 itself (the Pulse implementation explicitly disables the cron), or a separate manual step Bob takes after Pulse runs successfully for a month?
   **Recommendation:** manual, after Pulse's first full month of operation. Belt-and-suspenders during the handover.

---

## 7. Summary table — what each surface gets

| Surface | Pin form | Detection (pre-D9) | Detection (post-D9) | Action (post-D9) |
|---|---|---|---|---|
| 1. Local Hermes | none (HEAD) | weekly cron | weekly cron | auto-bump (status quo) |
| 2. Global Pi binary | `@latest` | weekly cron | weekly cron | auto-bump (status quo) |
| 3. Sidecar Pi dep | `^0.74.0` (or `0.74.0` per OQ #2) | **none** | weekly cron, ADR-002-aware | **alert only** — Bob opens PR on Sidecar |
| 4. Hermes container `HERMES_TAG` | `v2026.5.7` (exact) | **none** | weekly cron, ADR-002-aware | **alert only** — Bob opens PR on LivingApp-Hermes |

Post-Pulse (Story 3.9 / future): all four surfaces become Pulse signal-gatherer inputs; cron retires.

---

## 8. References

- **Existing cron spec:** `dev-team-work-loop/CRON-AUTO-UPDATE-REWRITE.md` (the v1 rewrite this doc extends)
- **Migration plan that produced surfaces 1+2's current state:** `dev-team-work-loop/DEV-TEAM-MIGRATION-2026-05-10.md`
- **Session handoff with surface 3+4 context:** `dev-team-work-loop/SESSION-HANDOFF-2026-05-14.md`
- **Pinning policy of record:** `LivingApp-Sidecar/docs/adr/002-upstream-keep-current-strategy.md`
- **Architecture that introduced surfaces 3+4:** `LivingApp-Sidecar/docs/adr/005-sidecar-v2-option-b.md`
- **Cron job source:** `cron/jobs.json` (job id `770cfee9f064`)
- **Surface 3 source:** `LivingApp-Sidecar/package.json` line 27
- **Surface 4 source:** `LivingApp-Hermes/Dockerfile` line 14
- **Self-protection pattern shared with auto-updater SKILL:** `skills/dev-team/learned-fixes/SKILL.md` (related but separate concern — debugging patterns, not update policy)
