# Gold-Panning Triage — 2026-06-19

## Sources scanned

- **Pi** (`@earendil-works/pi-coding-agent`): 7 versions in last 7 days (v0.79.2, v0.79.3, v0.79.4, v0.79.5, v0.79.6, v0.79.7, v0.79.8)
- **Hermes** (`NousResearch/hermes-agent`): 0 releases in last 7 days (latest remains v2026.6.5 "The Surface Release" from Jun 6)

---

## SHIP (1)

### 1. Pi v0.79.3 — GPT-5.4/5.5 Context Window Billing Hazard Fix

**What changed:** Pi v0.79.3 corrects context window metadata for OpenAI GPT-5.4/5.5 and Codex GPT-5.4/5.4 mini/GPT-5.5 models to use the observed 272k-token Codex backend limit. Before this fix, Pi would accept prompts above the actual limit, causing billing overruns (user pays for tokens that get rejected).

**Why this matters for Bob:** If either Crispi or FlowInCash uses these models (via Hermes or Pi), they could be silently exceeding the accepted context limit and paying for rejected tokens. The fix is a metadata correction — no code changes needed, just a version bump.

**Story stub:**
- **Problem:** GPT-5.4/5.5 models accept prompts up to ~272k tokens, but Pi was advertising higher limits. Users (or automated flows) could send oversized prompts and get billed for the full input even when the output is a context-length rejection.
- **Proposed approach:** Bump Pi pin from current version to ≥0.79.3. The metadata fix is internal to Pi's provider registry — no Sidecar code changes required.
- **App target:** LivingApp-Sidecar (shared dependency) — affects all apps using Pi-managed OpenAI models
- **Estimated effort:** small (pin bump + verification)
- **ADR 002 gate impact:** needs cost-regression check — bump the Pi pin and verify no behavioral change in non-interactive runs

---

## RESEARCH (1)

### 1. Pi v0.79.5–v0.79.8 — Provider Infrastructure Improvements (proxy, auth, caching, compaction)

**What changed across 4 releases:**
- **v0.79.5:** Provider-scoped API key `env` overrides (Azure, Vertex, Bedrock, cache retention, proxy settings scoped to Pi without changing the project shell) + global `httpProxy` setting + Vercel AI Gateway attribution headers.
- **v0.79.6:** HTTP dispatcher fix preserving caller's `fetch` override + DeepSeek V4 thinking-off compatibility fix.
- **v0.79.7:** Automatic theme mode + self-only `pi update` by default + extension API helpers (`CONFIG_DIR_NAME`, edit diff exports) + Warp inline image rendering.
- **v0.79.8:** Selective provider base entry points (`pi-ai/base`, `pi-agent-core/base`) for lighter bundled apps + Mistral prompt caching with session affinity + post-compaction token estimates + OpenRouter Fusion alias + compaction robustness fixes.

**Why this matters for Bob:** The provider-scoped auth (v0.79.5) could simplify how LivingApp-Sidecar manages API keys across providers — currently keys are environment-level, which means all providers share the same env. The selective entry points (v0.79.8) could reduce Sidecar's bundle size if it only imports the providers it actually uses. Post-compaction token estimates (v0.79.8) could improve the dev-team's overnight drain pipeline visibility into context usage.

**Research question:** Which of these provider infrastructure improvements have practical impact for LivingApp-Sidecar's current provider setup? Specifically: (a) Does the Sidecar use multiple providers that would benefit from scoped auth? (b) Could the selective entry points reduce Sidecar's Node.js bundle size or cold-start time? (c) Would post-compaction token estimates help the dev-team's kanban workers make better compaction decisions?

**Suggested next-session scope:**
- App: LivingApp-Sidecar (shared dependency)
- Investigate: review the Sidecar's current provider configuration (which providers, how keys are managed). Check if the Sidecar currently imports the full `pi-ai` or `pi-agent-core` packages. Assess whether scoped auth or selective entry points would reduce config complexity.
- What would unblock a SHIP decision: confirmation that the Sidecar uses ≥2 providers (making scoped auth useful) or that bundle size is a measured pain point (making selective entry points useful). Otherwise, these remain quality-of-life improvements with no customer-visible impact.
- Carry-forward: the v0.79.0/v0.79.1 project trust research from 2026-06-12 is now superseded — project trust fixes are folded into v0.79.2+ and the research question (defaultProjectTrust config) should be validated as part of the broader v0.79.3+ bump.

---

## PARK (5)

1. **Pi v0.79.2 — Bedrock Validation + Experimental First-Run Setup** — Parked: Better Bedrock error messages and experimental theme/analytics first-run flow. Bedrock not used by Bob's apps. First-run setup is user-facing QoL, not app-affecting.

2. **Pi v0.79.4 — Theme Detection + Binary Integrity Checksums** — Parked: Automatic first-run theme selection from terminal background + SHA256SUMS for standalone binaries. Both are developer/operator QoL. Bob's apps are server-side and don't use the Pi TUI.

3. **Pi v0.79.6 — HTTP Dispatcher + DeepSeek V4 Fixes** — Parked: Internal fixes preserving `fetch` overrides and DeepSeek V4 thinking compatibility. Relevant only if Sidecar uses DeepSeek V4 models or custom fetch dispatchers — currently unknown but unlikely given the Sidecar's Hermes-based architecture.

4. **Pi v0.79.7 — Theme Mode + Extension Helpers + Warp Images** — Parked: Automatic light/dark theme switching, extension API exports, Warp terminal image rendering. All TUI/operator-facing features. No impact on Bob's server-side apps.

5. **Pi v0.79.8 — Mistral Prompt Caching + OpenRouter Fusion** — Parked: Provider-specific cost optimizations (Mistral caching with session affinity) and a new OpenRouter model alias. Useful if Bob's apps use Mistral or OpenRouter — currently not confirmed. Cost optimization is a nice-to-have, not a feature unlock.

---

## Notes

**Upstream cadence:**
- Pi shipped 7 versions in 7 days — the busiest week observed. The releases are incremental (no major API breaks) but the volume signals active development. Most changes are provider infrastructure and TUI improvements. The selective provider base entry points (v0.79.8) are the most architecturally significant change this week.
- Hermes shipped 0 releases. The v2026.6.5 "Surface Release" (Jun 6) is now 13 days old. Hermes may be in a stabilization phase after the large v0.16.0 release.

**Carry-forward from 2026-06-12:**
- RESEARCH: Hermes v0.16.0 Kanban Platform Maturity (goal_mode, terminate, file attachments) — still open, no new Hermes signal. Carry forward to next triage. The question of whether native kanban replaces custom orchestration remains relevant.
- RESEARCH: Pi v0.79.0/v0.79.1 Project Trust — superseded by this week's broader v0.79.3+ bump opportunity. Fold the trust config question into the GPT context window SHIP item.
- PARK: Hermes Desktop App, Web Admin Panel, Leaner Skills + NVIDIA Tap — still parked, no change.

**Pipeline app status (from latest session handoff, 2026-05-17 evening):**
- Crispi-app: live, focus on MealsPage Yummly redesign (eq19)
- FlowInCash-Core: live, 22:00 cron draining beads with bd-gate enforcement
- LivingApp-Platform: future app, 0 open issues
- LivingApp-Sidecar: shared backend, `/hermes` WebSocket route broken (migration deferred)

**ADR 002 reminder:** All upstream pins are alert-only. This triage surfaces opportunities; it does not authorize pin bumps. Bob decides when and whether to act.

---

*Generated by Hermes gold-panning cron, 2026-06-19.*
