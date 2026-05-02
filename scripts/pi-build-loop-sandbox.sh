#!/bin/bash
# pi-build-loop-sandbox.sh — sandboxed runner for pi-build-loop.sh.
#
# Creates a temporary git worktree of <source-repo> at /tmp/<name>-sandbox-<id>,
# disables the origin remote inside it (so Pi can't push to your real GitHub),
# optionally runs a "test fixture" script to set up an issue + stub state,
# runs pi-build-loop.sh against the sandbox, then tears down the worktree
# on exit (success or failure).
#
# Usage:
#   pi-build-loop-sandbox.sh <source-repo> <branch> [-- pi-build-loop args...]
#
# Env (all optional):
#   SANDBOX_BASE        Where to put the sandbox dir (default: /tmp)
#   SANDBOX_SETUP_HOOK  Path to a bash script to run inside the sandbox after
#                       creation, before pi-build-loop. Receives sandbox path
#                       as $1. Use this to stub source files, create bd issues,
#                       etc. — anything Pi-test-specific.
#   KEEP_SANDBOX        If set to "1", skip cleanup so the sandbox can be
#                       inspected after the run. Default: cleanup on exit.
#
# Example:
#   SANDBOX_SETUP_HOOK=/tmp/fixture-push-1.4.sh \
#     pi-build-loop-sandbox.sh /media/bob/C/AI_Projects/Crispi-app \
#       eval/hybrid-test-push-1.4 -- --label sandbox-r4

set -u

SOURCE_REPO="${1:?usage: $0 <source-repo> <branch> [-- pi-build-loop args...]}"
BRANCH="${2:?usage: $0 <source-repo> <branch> [-- pi-build-loop args...]}"
shift 2
# Drop the optional `--` separator if present
if [[ "${1:-}" == "--" ]]; then shift; fi
LOOP_ARGS=("$@")

SANDBOX_BASE="${SANDBOX_BASE:-/tmp}"
SANDBOX="$SANDBOX_BASE/$(basename "$SOURCE_REPO")-sandbox-$(date +%s)-$$"
SETUP_HOOK="${SANDBOX_SETUP_HOOK:-}"
KEEP_SANDBOX="${KEEP_SANDBOX:-0}"

cleanup() {
  if [[ "$KEEP_SANDBOX" == "1" ]]; then
    echo "[sandbox] KEEP_SANDBOX=1 — leaving $SANDBOX in place for inspection"
    return
  fi
  echo "[sandbox] cleaning up $SANDBOX"
  cd "$SOURCE_REPO" 2>/dev/null || cd /
  git -C "$SOURCE_REPO" worktree remove --force "$SANDBOX" 2>&1 || rm -rf "$SANDBOX"
}
trap cleanup EXIT

echo "============================================================"
echo "[sandbox] source repo : $SOURCE_REPO"
echo "[sandbox] branch      : $BRANCH"
echo "[sandbox] sandbox path: $SANDBOX"
echo "[sandbox] setup hook  : ${SETUP_HOOK:-<none>}"
echo "[sandbox] loop args   : ${LOOP_ARGS[*]:-<none>}"
echo "============================================================"

# 1. Create the worktree from the branch's HEAD in detached mode. "Detached"
#    means the worktree gets the same code as the branch but isn't attached
#    to the branch's name — git allows this even when your main worktree
#    already has the branch checked out. Any commits Pi makes in the sandbox
#    are orphan commits that die when the worktree is removed.
git -C "$SOURCE_REPO" worktree add --detach "$SANDBOX" "$BRANCH" || {
  echo "[sandbox] FATAL: worktree add failed"; exit 1; }

# 2. Disconnect from GitHub WITHOUT touching the main repo's git config.
#    Important: `git worktree` shares .git/config between the main repo and
#    its worktrees. Running `git remote remove origin` in the worktree
#    actually removes origin from the main repo too — discovered the hard
#    way 2026-05-01 when this wrapper bricked the user's Crispi-app remote.
#    Instead, route HTTPS through a non-routable proxy via env vars
#    inherited by all child processes. NO_PROXY exempts localhost so Quinn
#    (and any other local services) remain reachable.
cd "$SANDBOX"
export HTTPS_PROXY="http://127.0.0.1:1"
export HTTP_PROXY="http://127.0.0.1:1"
export NO_PROXY="localhost,127.0.0.1,::1"
echo "[sandbox] HTTPS proxy set to dead address — sandbox cannot push or pull from GitHub (localhost still reachable)"

# 2b. Symlink dependency directories from the source repo. node_modules,
#     vendor/, etc. are gitignored so the worktree starts without them.
#     Both source and sandbox are at the same commit, so dependency versions
#     match exactly. Symlink is read-mostly; tests don't mutate these.
for dep in node_modules vendor .venv; do
  if [[ -d "$SOURCE_REPO/$dep" && ! -e "$SANDBOX/$dep" ]]; then
    ln -s "$SOURCE_REPO/$dep" "$SANDBOX/$dep"
    echo "[sandbox] symlinked $dep from source repo"
  fi
done

# 2c. WARN about bd state leakage. We CANNOT cleanly isolate bd state
#     in a worktree-based sandbox: bd auto-discovers its database via
#     the git root, and `git worktree` shares the git root (and thus
#     the running Dolt server reference) with the source repo. Even if
#     we rm -rf .beads/ in the sandbox, `bd init` detects the source
#     repo's Dolt server and refuses to init (or, with --reinit-local,
#     would destroy the source's data). Discovered 2026-05-01 during
#     three-tier-quinn work — prior sandbox runs leaked their issues
#     into the main Crispi-app beads DB.
#
#     Pragmatic mitigation: fixtures must use a unique label per run
#     so issues are easy to find + clean up afterwards. The wrapper
#     surfaces the leakage so it isn't silent.
if [[ -f "$SOURCE_REPO/.beads/metadata.json" ]] && \
   grep -q '"dolt_mode": "server"' "$SOURCE_REPO/.beads/metadata.json" 2>/dev/null; then
  echo "[sandbox] WARN: source repo uses bd in dolt-server mode; sandbox bd writes will land"
  echo "[sandbox]       in the source project's database. Fixtures should use a unique"
  echo "[sandbox]       label and clean up afterwards. Cannot isolate via worktree."
fi

# 3. Run the test-fixture script, if provided, inside the sandbox
if [[ -n "$SETUP_HOOK" ]]; then
  if [[ ! -f "$SETUP_HOOK" ]]; then
    echo "[sandbox] FATAL: SANDBOX_SETUP_HOOK=$SETUP_HOOK does not exist"; exit 1
  fi
  echo "[sandbox] --- running setup hook ---"
  bash "$SETUP_HOOK" "$SANDBOX" || {
    echo "[sandbox] FATAL: setup hook failed"; exit 1; }
  echo "[sandbox] --- setup hook done ---"
fi

# 4. Hand off to pi-build-loop.sh against the sandbox path
echo "[sandbox] launching pi-build-loop.sh"
pi-build-loop.sh "$SANDBOX" "${LOOP_ARGS[@]}"
LOOP_RC=$?

echo "[sandbox] pi-build-loop.sh exited with code $LOOP_RC"
exit "$LOOP_RC"
