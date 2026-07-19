#!/bin/bash
# overflow-quick-triage.sh — Fast implementability check for overflow projects
# Usage: bash overflow-quick-triage.sh <project-dir> [project-dir2 ...]
#
# Returns: per-project summary with open bead count and blocking breakdown.
# Designed for drain early-exit flow: lightweight, no bd show calls unless
# project has potentially implementable beads.
#
# Exit codes: 0 = at least one implementable bead found, 1 = all exhausted

COMPREHENSIVE_BLOCKING_PATTERN="Owner:|blocked by|blocked on|post-beta|DO NOT|@azrlb|@hermes-dev-team|human-action|needs-visual|release-cycle|deferred|\\[epic\\]|\\[feature\\]|\\[story\\]"

any_implementable=0

for dir in "$@"; do
  if [ ! -d "$dir/.beads" ]; then
    continue
  fi
  
  project=$(basename "$dir")
  total=$(cd "$dir" && bd list --state open --flat 2>/dev/null | wc -l)
  
  if [ "$total" -eq 0 ]; then
    echo "=== $project: EMPTY POOL ==="
    continue
  fi
  
  blocked=$(cd "$dir" && bd list --state open --flat 2>/dev/null | grep -ciE "$COMPREHENSIVE_BLOCKING_PATTERN")
  remaining=$((total - blocked))

  # Type breakdown
  task_count=$(cd "$dir" && bd list --state open --flat 2>/dev/null | grep -c "\[task\]" || echo 0)
  feature_count=$(cd "$dir" && bd list --state open --flat 2>/dev/null | grep -c "\[feature\]" || echo 0)
  story_count=$(cd "$dir" && bd list --state open --flat 2>/dev/null | grep -c "\[story\]" || echo 0)
  bug_count=$(cd "$dir" && bd list --state open --flat 2>/dev/null | grep -c "\[bug\]" || echo 0)
  epic_count=$(cd "$dir" && bd list --state open --flat 2>/dev/null | grep -c "\[epic\]" || echo 0)

  echo "=== $project: $total open, $blocked blocked/gated, $remaining potentially free ==="
  echo "    Types: $task_count task, $feature_count feature, $story_count story, $bug_count bug, $epic_count epic"

  if [ "$remaining" -gt 0 ]; then
    # Show potentially free beads (may still be false positives — need bd show to confirm)
    cd "$dir" && bd list --state open --flat 2>/dev/null | grep -viE "$COMPREHENSIVE_BLOCKING_PATTERN" | head -10
    any_implementable=1
  fi
done

exit $any_implementable
