#!/bin/bash
# pi-build-loop.sh — Pi-only implementation phase. The "build" half of the
# hybrid Hermes-plans / Pi-builds architecture.
#
# Usage:
#   pi-build-loop.sh                           # use default repo (env REPO or CWD)
#   pi-build-loop.sh /path/to/repo             # explicit repo
#   pi-build-loop.sh --label epic-1            # only drain issues with this label
#
# Architecture:
#   Hermes (via dev-team/vibe-loop or dev-team/plan) does Phases 0-9:
#     analyst → architect → epics → story-specs → TDD test files → bd create
#     Each bd issue's notes contain: story_file=<path> | test_file=<path>
#     Each story file has explicit "Key files to modify" + "Test file" sections.
#   Hermes exits cleanly at Phase 9 (no Phase 10 dispatch loop).
#   This script picks up from there: drains bd ready, dispatches Pi per issue
#   with the FULL story_file content as context. Pi knows the exact files to
#   touch — no path hallucination, no fake commits. Pi is responsible for
#   claim → implement → test → commit → close → push.
#
# Why this fixes the brain-orchestration bugs:
#   The hybrid moves the "what files does this issue touch" decision from
#   runtime (brain-side dispatch where prose-to-path hallucination kills us)
#   to planning time (Hermes writes story files with explicit paths). Pi
#   reads concrete file paths from the spec, doesn't guess from issue title.
#
# Per-issue cap: 60 min. One shot per issue, no retry — if Pi can't complete
# in 60 min, move on. Same Bug 4 behavior as eval-watchdog.sh.

set -u  # not -e: continue past failed iters

REPO="${1:-${REPO:-$(pwd)}}"
LABEL_FILTER=""

# Parse --label flag if present
while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL_FILTER="$2"; shift 2 ;;
    *) shift ;;
  esac
done

LOG_DIR="$HOME/.hermes/logs"
TS=$(date +%Y%m%d_%H%M%S)
LOG="$LOG_DIR/pi-build-loop-$TS.log"
ITER_CAP_SEC="${PI_BUILD_ITER_CAP_SEC:-3600}"

mkdir -p "$LOG_DIR"
cd "$REPO" || { echo "ERROR: cannot cd to $REPO" | tee -a "$LOG"; exit 1; }

echo "=== Pi build loop starting at $(date) ===" | tee -a "$LOG"
echo "Repo:         $REPO" | tee -a "$LOG"
echo "Branch:       $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'NOT-A-GIT-REPO')" | tee -a "$LOG"
echo "Iter cap:     ${ITER_CAP_SEC}s per issue" | tee -a "$LOG"
echo "Label filter: ${LABEL_FILTER:-<none>}" | tee -a "$LOG"
echo "Log:          $LOG" | tee -a "$LOG"
echo "" | tee -a "$LOG"

# Get the next ready issue and emit:
#   <id>\t<title>\t<priority>\t<story_file>\t<test_file>\t<description>
# Returns empty if no work. story_file/test_file extracted from issue notes
# field (vibe-loop Phase 8 writes them as `story_file=... | test_file=...`).
get_next_issue() {
  local label_arg=""
  if [[ -n "$LABEL_FILTER" ]]; then
    label_arg="--label $LABEL_FILTER"
  fi
  bd ready --json $label_arg 2>/dev/null | python3 -c "
import json, re, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not data:
    sys.exit(1)
i = data[0]
notes = i.get('notes', '') or ''
# Vibe-loop notes shape: 'story_file=<path> | test_file=<path>'
sf = ''
tf = ''
m = re.search(r'story_file=([^\s|]+)', notes)
if m: sf = m.group(1)
m = re.search(r'test_file=([^\s|]+)', notes)
if m: tf = m.group(1)
def clean(s):
    return (s or '').replace('\t', ' ').replace('\n', ' ').strip()
print(f\"{i.get('id','')}\t{clean(i.get('title',''))}\t{i.get('priority','')}\t{sf}\t{tf}\t{clean(i.get('description',''))}\")
" 2>/dev/null
}

iter=0
while true; do
  iter=$((iter + 1))

  next=$(get_next_issue)
  if [[ -z "$next" ]]; then
    echo "" | tee -a "$LOG"
    echo "=== No more ready issues. Loop done after $((iter - 1)) iterations. ===" | tee -a "$LOG"
    break
  fi

  IFS=$'\t' read -r id title priority story_file test_file description <<<"$next"

  echo "" | tee -a "$LOG"
  echo "=================================================================" | tee -a "$LOG"
  echo "=== iter $iter: $id [P$priority] — $title" | tee -a "$LOG"
  echo "    story_file: ${story_file:-<not set>}" | tee -a "$LOG"
  echo "    test_file:  ${test_file:-<not set>}" | tee -a "$LOG"
  echo "=================================================================" | tee -a "$LOG"

  # Read the story spec content (rich planning output from Hermes phases 7a/7b).
  # If story_file isn't set or doesn't exist, fall back to the bd description.
  story_content=""
  if [[ -n "$story_file" && -f "$story_file" ]]; then
    story_content=$(cat "$story_file")
    echo "    Loaded story spec from $story_file ($(wc -l < "$story_file") lines)" | tee -a "$LOG"
  elif [[ -n "$story_file" ]]; then
    echo "    WARN: story_file=$story_file does not exist on disk. Using bd description as spec." | tee -a "$LOG"
    story_content="$description"
  else
    echo "    WARN: no story_file in notes. Using bd description as spec (may lack file paths)." | tee -a "$LOG"
    story_content="$description"
  fi

  # Claim the issue
  bd update "$id" --claim 2>&1 | tee -a "$LOG"

  # Build Pi prompt. Pi gets:
  # - The full story spec (from Hermes' planning phase) — explicit file paths
  # - Concrete close protocol (claim → fix → test → commit → close → push)
  # - bd-gate awareness (Pi knows tests will be re-run on close)
  prompt="You are completing one bd issue end-to-end. The story spec below was written by the planning phase and contains the EXACT file paths to modify and the test command to verify. Use them directly — do NOT guess paths from prose.

ISSUE ID:    $id
TITLE:       $title
TEST FILE:   ${test_file:-<see story spec>}

## STORY SPEC (authoritative — use file paths from this, not from the title):
$story_content

## YOUR WORKFLOW

1. Read AGENTS.md for project conventions.
2. Read the test file at: ${test_file:-<extract from story spec 'Test file' line>}. Tests are the contract — DO NOT modify them.
3. Read the source file(s) listed in the story's 'Key files to modify' section. Implement the fix per the story's Acceptance Criteria.
4. Run the test command (typically: \`npx vitest <test_file>\` or whatever the project conventions say). Tests MUST pass before close.
5. Write \`.hermes/sessions/$id.prompt.txt\` with one line: \`Run: <the exact test command you used>\`. bd-gate v0.4 will re-run this command for independent verification on close.
6. Stage your code change(s): \`git add <source files>\`. Do NOT stage test files.
7. \`git commit -m 'fix($id): <brief description>' --no-verify\`. Do NOT use --allow-empty. Do NOT make multiple empty commits.
8. Re-run the test command against HEAD. If passing, write \`.hermes/sessions/$id.test-result\` with: \`PASS \$(git rev-parse HEAD)\`.
9. \`bd close $id\`
10. \`git push\` (or \`git push -u origin <branch>\` if no upstream).

## HARD RULES

- DO modify only the source files explicitly listed in the story spec's 'Key files to modify' section.
- NEVER modify test files.
- NEVER modify config files (vite.config.*, vitest.config.*, package.json, tsconfig.json, .eslintrc.json, jest.config.*).
- NEVER use \`git commit --allow-empty\`.
- NEVER write a PASS \`.test-result\` without actually running and passing the tests.
- NEVER write 'No tests required' as a way to skip step 4 — every coding issue requires tests.
- If you can't make tests pass after 3 different approaches, escalate by spawning the reasoning model:
    pi --print --no-tools --provider ollama-quinn --model deepseek-r1:32b 'reasoning prompt with full context'

REPO: $REPO

Begin."

  # Run Pi with timeout
  timeout "$ITER_CAP_SEC" pi --print \
    --provider ollama --model devstral-small-2:24b \
    --session ".hermes/sessions/$id.jsonl" \
    --append-system-prompt "$HOME/.pi/agents/tdd-coder.md" \
    "$prompt" >> "$LOG" 2>&1
  exit_code=$?
  echo "Pi exit: $exit_code (124=timeout)" | tee -a "$LOG"

  # Status check
  status=$(bd show "$id" --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    i = d[0] if isinstance(d, list) else d
    print(i.get('status', 'unknown'))
except Exception:
    print('unknown')
")
  echo "Post-Pi: $id status=$status" | tee -a "$LOG"

  if [[ "$status" != "closed" ]]; then
    echo "WARN: $id did not close. Moving on (no retry — baseline mode)." | tee -a "$LOG"
  fi
done

echo "" | tee -a "$LOG"
echo "=================================================================" | tee -a "$LOG"
echo "=== FINAL STATE ($(date))" | tee -a "$LOG"
echo "=================================================================" | tee -a "$LOG"
bd search --status all --json 2>/dev/null | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    for i in data:
        if i.get('status') in ('open', 'in_progress', 'closed'):
            print(f\"{i['id']} [{i.get('status')}] {i.get('title','')[:80]}\")
except Exception:
    pass
" | tee -a "$LOG"

echo "" | tee -a "$LOG"
echo "=== Pi build loop done at $(date) ===" | tee -a "$LOG"
