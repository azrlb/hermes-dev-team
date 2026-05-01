#!/bin/bash
# vibe-plan-then-build.sh — chained launcher for the hybrid Hermes-plans /
# Pi-builds workflow.
#
# What it does:
#   1. Prompts for the project directory (or accepts one as $1)
#   2. Runs hermes chat -s dev-team/vibe-plan --yolo IN that directory
#      → Hermes plans phases 0-9 (analyst → architect → bd create), exits at 9
#   3. If vibe-plan exited cleanly AND the queue has work, runs pi-build-loop.sh
#      → Pi drains bd ready, implements each story, commits + closes honestly
#   4. Final status: bd search EVAL --status all + commits since baseline
#
# Why split: brain-orchestrated runtime dispatch (vibe-loop's Phase 10) hits a
# capability ceiling on local Ollama (eval rounds 1-7, 2026-04-30). Hybrid
# moves dispatch to Pi-side bash that reads story_file metadata from disk —
# no path hallucination. See project_eval_findings.md Round 6.
#
# Usage:
#   vibe-plan-then-build.sh                       # prompt for project dir
#   vibe-plan-then-build.sh /path/to/repo         # explicit dir
#   vibe-plan-then-build.sh /path/to/repo --skip-plan  # build-only (queue exists)

set -u

PROJECT_DIR="${1:-}"
SKIP_PLAN=0

# Parse remaining args
shift_count=0
for arg in "$@"; do
  case "$arg" in
    --skip-plan|--build-only) SKIP_PLAN=1 ;;
  esac
done

# Prompt for project dir if not provided
if [[ -z "$PROJECT_DIR" ]]; then
  echo "════════════════════════════════════════════════════════════════"
  echo "  Hermes Plan + Pi Build (hybrid pipeline)"
  echo "════════════════════════════════════════════════════════════════"
  echo
  read -r -p "Project directory (full path): " PROJECT_DIR
  echo
fi

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo "ERROR: project directory does not exist: $PROJECT_DIR"
  read -r -p "Press Enter to close..."
  exit 1
fi

cd "$PROJECT_DIR" || {
  echo "ERROR: cannot cd to $PROJECT_DIR"
  read -r -p "Press Enter to close..."
  exit 1
}

# ─── Phase 1: Hermes Plan (vibe-plan) ──────────────────────────────────────
if [[ $SKIP_PLAN -eq 0 ]]; then
  echo "════════════════════════════════════════════════════════════════"
  echo "  Phase 1: Hermes Plan (analyst → architect → stories → bd)"
  echo "  Project: $PROJECT_DIR"
  echo "  Skill:   dev-team/vibe-plan"
  echo "════════════════════════════════════════════════════════════════"
  echo

  hermes chat --yolo -s dev-team/vibe-plan
  plan_exit=$?

  echo
  echo "════════════════════════════════════════════════════════════════"
  if [[ $plan_exit -ne 0 ]]; then
    echo "  ✗ vibe-plan exited with code $plan_exit"
    echo "  Not proceeding to build phase."
    echo "════════════════════════════════════════════════════════════════"
    read -r -p "Press Enter to close..."
    exit $plan_exit
  fi
  echo "  ✓ Phase 1 complete (vibe-plan exited cleanly)"
  echo "════════════════════════════════════════════════════════════════"
  echo
fi

# ─── Pre-build sanity: anything to do? ─────────────────────────────────────
ready_count=$(bd ready --json 2>/dev/null | python3 -c "
import json, sys
try:
    print(len(json.load(sys.stdin)))
except Exception:
    print(0)
")

if [[ "$ready_count" -eq 0 ]]; then
  echo "  No issues are ready. Either planning didn't create any, or all are"
  echo "  blocked by dependencies. Use \`bd search\` to inspect."
  echo "════════════════════════════════════════════════════════════════"
  read -r -p "Press Enter to close..."
  exit 0
fi

# ─── Phase 2: Pi Build Loop ────────────────────────────────────────────────
echo "════════════════════════════════════════════════════════════════"
echo "  Phase 2: Pi Build Loop (drain bd ready)"
echo "  Project:    $PROJECT_DIR"
echo "  Ready:      $ready_count issue(s)"
echo "  Per-issue:  60min cap, 1 attempt"
echo "════════════════════════════════════════════════════════════════"
echo

pi-build-loop.sh "$PROJECT_DIR"
build_exit=$?

echo
echo "════════════════════════════════════════════════════════════════"
echo "  Pipeline complete (build exit $build_exit)"
echo "  Final state:"
bd search --status all 2>&1 | head -20
echo
echo "  Commits since most recent merge:"
git log --oneline @{u}..HEAD 2>/dev/null | head -10 || git log --oneline -10
echo "════════════════════════════════════════════════════════════════"
read -r -p "Press Enter to close..."
exit $build_exit
