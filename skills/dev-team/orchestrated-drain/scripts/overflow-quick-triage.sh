#!/usr/bin/env bash
# overflow-quick-triage.sh — Fast overflow project triage for drains
# Usage: bash overflow-quick-triage.sh /path/to/project1 /path/to/project2 ...
#
# Reports open/blocked/free counts per project in one invocation.
# Replaces manual 3-command grep pattern per project.

set -euo pipefail

BLOCKING_PATTERN="Owner:|blocked by|blocked on|post-beta|DO NOT|@azrlb|@hermes-dev-team|human-action|needs-visual|release-cycle|deferred|\[feature\]|\[story\]"

for project_dir in "$@"; do
  if [ ! -d "$project_dir/.beads" ]; then
    echo "=== $(basename "$project_dir") === (no .beads directory — skipping)"
    continue
  fi

  cd "$project_dir"
  project_name=$(basename "$project_dir")

  total=$(bd list --state open --flat 2>/dev/null | wc -l)
  blocked=$(bd list --state open --flat 2>/dev/null | grep -ciE "$BLOCKING_PATTERN" || true)
  tasks=$(bd list --state open --flat 2>/dev/null | grep -c "\[task\]" || true)
  bugs=$(bd list --state open --flat 2>/dev/null | grep -c "\[bug\]" || true)
  features=$(bd list --state open --flat 2>/dev/null | grep -c "\[feature\]" || true)
  free=$((total - blocked))

  echo "=== $project_name ==="
  echo "  Open: $total | Blocked: $blocked | Free: $free"
  echo "  Tasks: $tasks | Bugs: $bugs | Features: $features"

  if [ "$free" -gt 0 ]; then
    echo "  ⚠ $free potentially implementable beads — run bd show on each to verify"
  else
    echo "  ✓ All beads blocked or non-implementable"
  fi
  echo ""
done
