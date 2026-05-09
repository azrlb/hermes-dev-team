#!/usr/bin/env bash
# Lander HEAD-moved fixture — exercises the protocol added to
# skills/dev-team/land-the-plane/SKILL.md in commit a05df90 (2026-05-09).
#
# Strategy:
#   For each variant (PASS at HEAD, FAIL at HEAD):
#     1. Build a tiny project with one failing test (state at sha_A).
#     2. Plant a second commit at sha_B — variant-specific:
#          - PASS variant: sha_B contains the correct fix → test passes
#          - FAIL variant: sha_B contains an unrelated change → test still fails
#     3. Create a [story-verify] kanban task, complete it with metadata.head_sha=sha_A.
#     4. Create a [story-land] kanban task linked to the verify task.
#     5. Invoke the lander shim directly with HERMES_KANBAN_TASK / WORKSPACE set.
#     6. Capture: did the shim block? With what reason?
#
# Acceptance (asserted by assert-head-moved.sh):
#   - PASS variant blocks with reason matching:
#       "HEAD moved <old>→<new>; target test passes at HEAD;
#        orchestrator must reconcile attribution"
#   - FAIL variant blocks with reason matching:
#       "HEAD moved <old>→<new>; target test still failing at HEAD;
#        substrate race or work lost"

set -uo pipefail

ROOT=/tmp/hermes-kanban-lander-head-moved
TENANT=KanbanLanderHeadMoved
SHIM=/media/bob/C/AI_Projects/hermes-dev-team/dev-team-work-loop/tests/kanban-lander-head-moved/shims/hermes-kanban-shim.sh

# Persist the task ids for the assertion script.
STATE="$ROOT/.fixture-state.txt"

setup_variant() {
  local variant="$1"   # "pass" or "fail"
  local subdir="$ROOT/$variant"

  rm -rf "$subdir"
  mkdir -p "$subdir/src/__tests__"
  cd "$subdir"

  cat > package.json <<'JSON'
{
  "name": "kanban-lander-head-moved",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "vitest run"
  },
  "devDependencies": {
    "vitest": "^1.6.0",
    "typescript": "^5.4.0"
  }
}
JSON

  cat > tsconfig.json <<'JSON'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*"]
}
JSON

  cat > src/__tests__/add.test.ts <<'TS'
import { describe, it, expect } from "vitest";
import { add } from "../add";

describe("add", () => {
  it("adds two positive integers", () => {
    expect(add(2, 3)).toBe(5);
  });
});
TS

  cat > src/add.ts <<'TS'
export function add(_a: number, _b: number): number {
  return -1;
}
TS

  cat > .gitignore <<'GIT'
node_modules/
.hermes/
GIT

  echo "[setup-$variant] npm install..."
  npm install --silent --no-audit --no-fund

  git init -q
  git -c user.email=test@test -c user.name=test add -A
  git -c user.email=test@test -c user.name=test commit -q -m "initial: failing test"

  # sha_A = the state the [story-verify] supposedly verified at.
  # In real production this would never be a failing-test sha; for the
  # fixture we just need *some* sha to be the recorded verify_head_sha.
  SHA_A=$(git rev-parse HEAD)

  if [[ "$variant" == "pass" ]]; then
    # Plant the correct fix at sha_B → test passes at HEAD.
    cat > src/add.ts <<'TS'
export function add(a: number, b: number): number {
  return a + b;
}
TS
    git -c user.email=test@test -c user.name=test commit -q -am "fix: correct add() implementation"
  else
    # Plant an unrelated change at sha_B → test still fails at HEAD.
    echo "// unrelated cosmetic change" >> src/add.ts
    git -c user.email=test@test -c user.name=test commit -q -am "chore: unrelated comment"
  fi

  SHA_B=$(git rev-parse HEAD)
  echo "[setup-$variant] sha_A=$SHA_A sha_B=$SHA_B"

  # Record for assertion phase.
  printf "%s sha_a %s\n%s sha_b %s\n" "$variant" "$SHA_A" "$variant" "$SHA_B" >> "$STATE"

  # ─── Create kanban tasks ────────────────────────────────────────────────────

  local verify_id land_id
  verify_id=$(hermes kanban create "[story-verify] cross-check ${variant}" \
    --tenant "$TENANT" \
    --workspace "dir:${subdir}" \
    --assignee hermes-verifier \
    --skill dev-team/cross-check \
    --body "bd_id=fake-${variant}
worktree=${subdir}
test_file=${subdir}/src/__tests__/add.test.ts" \
    --json | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

  hermes kanban complete "$verify_id" \
    --summary "verify (fixture): pretend-VERIFIED at sha_a" \
    --metadata "{\"outcome\":\"VERIFIED\",\"head_sha\":\"$SHA_A\",\"bd_id\":\"fake-${variant}\"}" >/dev/null

  land_id=$(hermes kanban create "[story-land] land ${variant}" \
    --tenant "$TENANT" \
    --workspace "dir:${subdir}" \
    --assignee hermes-lander \
    --skill dev-team/land-the-plane \
    --body "bd_id=fake-${variant}
worktree=${subdir}
test_file=${subdir}/src/__tests__/add.test.ts" \
    --json | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")

  hermes kanban link "$verify_id" "$land_id" >/dev/null

  printf "%s verify_id %s\n%s land_id %s\n" "$variant" "$verify_id" "$variant" "$land_id" >> "$STATE"
  echo "[setup-$variant] verify=$verify_id land=$land_id"

  # ─── Invoke the lander shim directly ────────────────────────────────────────

  echo "[run-$variant] invoking lander shim..."
  HERMES_KANBAN_TASK="$land_id" \
  HERMES_KANBAN_WORKSPACE="$subdir" \
    bash "$SHIM" -p hermes-lander \
      --skills kanban-worker \
      --skills dev-team/land-the-plane \
      chat -q "work kanban task $land_id" 2>&1 | tee "$subdir/.shim.log" | head -20

  echo "[run-$variant] done."
}

# ─── Cleanup any leftover tasks from prior runs ───────────────────────────────

echo "[setup] archiving any prior $TENANT tasks..."
hermes kanban list --tenant "$TENANT" --json 2>/dev/null \
  | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    [print(t['id']) for t in (d if isinstance(d, list) else [])]
except Exception:
    pass
" 2>/dev/null \
  | xargs -I{} hermes kanban archive {} 2>/dev/null || true

mkdir -p "$ROOT"
: > "$STATE"

setup_variant pass
setup_variant fail

echo
echo "[done] both variants ran. Now invoke ./assert-head-moved.sh"
echo "[done] state file: $STATE"
