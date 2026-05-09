#!/usr/bin/env bash
# setup-kanban-profiles.sh
#
# Slice 1 of the kanban migration plan (~/.claude/plans/okay-lets-plan-theintergration-rustling-hedgehog.md).
#
# Provisions the four Hermes profiles used by the kanban-native dev-team build
# half: dev-orchestrator, pi-coder, hermes-verifier, hermes-lander.
#
# Each profile is cloned from `default` (which already runs qwen3:30b at
# localhost:8080 and has the `quinn` provider pre-configured for deepseek-r1:32b
# at localhost:8082) so we inherit model + skill state without divergence.
#
# IDEMPOTENT: re-running this script on a machine where the profiles already
# exist is a no-op. Safe to run multiple times.
#
# After running, verify with:
#   hermes profile list
#   hermes profile show dev-orchestrator
#   hermes profile show pi-coder
#
# Slice 1 acceptance reference: see plan §Migration slices §Slice 1.

set -euo pipefail

PROFILES=(dev-orchestrator pi-coder hermes-verifier hermes-lander hermes-detector hermes-health-check)

# Map each profile to its dev-team-specific pinned skill. The canonical
# kanban-orchestrator and kanban-worker skills are auto-loaded by the dispatcher
# into every profile — DO NOT pin them explicitly.
declare -A PROFILE_SKILLS
PROFILE_SKILLS[dev-orchestrator]="dev-team/kanban-decomposition"
PROFILE_SKILLS[pi-coder]="dev-team/pi-dispatcher"
PROFILE_SKILLS[hermes-verifier]="dev-team/cross-check"
PROFILE_SKILLS[hermes-lander]="dev-team/land-the-plane"
PROFILE_SKILLS[hermes-detector]="dev-team/stack-detect"
PROFILE_SKILLS[hermes-health-check]="dev-team/health-fix"

# ─── Pre-flight ────────────────────────────────────────────────────────────────

if ! command -v hermes >/dev/null 2>&1; then
  echo "ERROR: hermes CLI not found on PATH. Install or set up first." >&2
  exit 1
fi

REQUIRED_VERSION="0.13.0"
HERMES_VERSION=$(hermes version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")
echo "[setup] hermes version: $HERMES_VERSION (required: ≥$REQUIRED_VERSION for durable kanban: heartbeat, zombie detection, diagnostics, multi-board)"

# Sanity-check the default profile is the one we want to clone from.
if ! hermes profile show default >/dev/null 2>&1; then
  echo "ERROR: 'default' profile not found. Run 'hermes setup' first." >&2
  exit 1
fi

DEFAULT_MODEL=$(hermes profile show default 2>/dev/null | awk '/^Model:/ {print $2}')
echo "[setup] default profile model: $DEFAULT_MODEL"
if [[ "$DEFAULT_MODEL" != qwen3* ]]; then
  echo "WARN: default profile model is '$DEFAULT_MODEL', not qwen3:* — kanban workers will inherit it." >&2
  echo "      If this is intentional, ignore. Otherwise update default first." >&2
fi

# ─── Provision each profile ────────────────────────────────────────────────────

list_existing() {
  hermes profile list 2>/dev/null | awk 'NR>2 {print $1}' | sed 's/^◆//' | grep -v '^$'
}

EXISTING=$(list_existing || true)

for profile in "${PROFILES[@]}"; do
  if echo "$EXISTING" | grep -qx "$profile"; then
    echo "[setup] profile '$profile' already exists — skipping create"
  else
    echo "[setup] creating profile '$profile' (cloning from default)"
    hermes profile create "$profile" --clone --no-alias
  fi

  skill="${PROFILE_SKILLS[$profile]}"
  echo "[setup] profile '$profile' will pin skill: $skill"
  # Skill pinning per-profile is done at task-creation time via
  # kanban_create(skills=[...]) — there is no separate `hermes profile skill add`
  # command for default-loaded skills. The kanban-decomposition skill's
  # documentation enumerates the skills each profile loads.
done

# ─── Verification ──────────────────────────────────────────────────────────────

echo
echo "[setup] verification:"
hermes profile list | sed 's/^/  /'

echo
echo "[setup] done. Each kanban worker spawned with one of these profiles will"
echo "        also auto-load ~/.hermes/skills/devops/kanban-{orchestrator,worker}/SKILL.md"
echo "        via the dispatcher's KANBAN_GUIDANCE injection. Skills shown above are"
echo "        loaded via 'kanban_create --skill <name>' or task metadata, NOT pinned"
echo "        to the profile globally."
echo
echo "        Next: run dev-team-work-loop/tests/kanban-slice-1/run-happy-path.sh"
echo "        to exercise the four profiles end-to-end with a Pi shim that succeeds"
echo "        on first call."
