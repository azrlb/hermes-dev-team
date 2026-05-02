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
#   <id>\t<title>\t<priority>\t<story_file>\t<test_file>\t<test_command>\t<description>
# Returns empty if no work. story_file/test_file/test_command extracted from
# issue notes (vibe-loop Phase 8 writes them as
# `story_file=<p> | test_file=<p> | test_command=<full cmd>`).
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
sf = ''
tf = ''
tc = ''
m = re.search(r'story_file=([^\s|]+)', notes)
if m: sf = m.group(1)
m = re.search(r'test_file=([^\s|]+)', notes)
if m: tf = m.group(1)
# test_command can contain spaces — match up to '|' or end of string
m = re.search(r'test_command=([^|]+?)(?:\s*\||\s*\$)', notes + '|')
if m: tc = m.group(1).strip()
def clean(s):
    return (s or '').replace('\t', ' ').replace('\n', ' ').replace('\x01', ' ').strip()
# Use \x01 as separator instead of \t. Bash IFS=\$'\t' collapses consecutive
# empty tab-separated fields because tab is whitespace; \x01 is non-whitespace
# so empty fields survive parsing. Discovered 2026-05-01 during three-tier
# auth-security run when notes had only test_command (no story_file/test_file).
print(f\"{i.get('id','')}\x01{clean(i.get('title',''))}\x01{i.get('priority','')}\x01{sf}\x01{tf}\x01{clean(tc)}\x01{clean(i.get('description',''))}\")
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

  IFS=$'\x01' read -r id title priority story_file test_file test_command description <<<"$next"

  # Fallback: derive a test_command if notes didn't carry one. Mixed-runner
  # repos (jest+vitest both present) confuse the agent; spec it explicitly.
  if [[ -z "$test_command" && -n "$test_file" ]]; then
    if [[ -f "package.json" ]] && grep -q '"vitest"' package.json; then
      test_command="npx vitest run $test_file"
    elif [[ -f "package.json" ]] && grep -q '"jest"' package.json; then
      test_command="npx jest --testPathPattern=$test_file"
    else
      test_command="npm test -- $test_file"
    fi
  fi

  echo "" | tee -a "$LOG"
  echo "=================================================================" | tee -a "$LOG"
  echo "=== iter $iter: $id [P$priority] — $title" | tee -a "$LOG"
  echo "    story_file:   ${story_file:-<not set>}" | tee -a "$LOG"
  echo "    test_file:    ${test_file:-<not set>}" | tee -a "$LOG"
  echo "    test_command: ${test_command:-<not set>}" | tee -a "$LOG"
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

  # Pre-write prompt.txt with the binding test command. This removes Pi's
  # runner-choice ambiguity in mixed-runner repos and gives the post-Pi
  # verification gate a stable contract regardless of whether Pi attests.
  mkdir -p .hermes/sessions
  if [[ -n "$test_command" ]]; then
    echo "Run: $test_command" > ".hermes/sessions/$id.prompt.txt"
    echo "    Pre-wrote .hermes/sessions/$id.prompt.txt with: Run: $test_command" | tee -a "$LOG"
  else
    echo "    WARN: no test_command derived — gate will refuse to close" | tee -a "$LOG"
  fi

  # Build Pi prompt. Pi gets:
  # - The full story spec (from Hermes' planning phase) — explicit file paths
  # - Concrete close protocol (claim → fix → test → commit → close → push)
  # - bd-gate awareness (Pi knows tests will be re-run on close)
  prompt="You are completing one bd issue end-to-end. The story spec below was written by the planning phase and contains the EXACT file paths to modify. Use them directly — do NOT guess paths from prose.

ISSUE ID:     $id
TITLE:        $title
TEST FILE:    ${test_file:-<see story spec>}
TEST COMMAND: ${test_command:-<see story spec>}

## STORY SPEC (authoritative — file paths, AC, patterns, do-NOTs all come from here):
$story_content

## YOUR WORKFLOW

The story spec above contains everything: Acceptance Criteria, Tasks, the source file path, the test file path, Coding Rules (Patterns to Follow, Reuse These, Do NOT). Do NOT read AGENTS.md or other project-context docs unless the story spec explicitly tells you to — context is finite and the spec is self-contained.

1. Read the test file at: ${test_file:-<extract from story spec 'Test file' line>}. Tests are the contract — DO NOT modify them.
2. Read the source file(s) listed in the story's 'Key files to modify' section. Implement the fix per the story's Acceptance Criteria.
3. Run **exactly this** command and no other: \`${test_command:-<extract from story spec>}\`. Do NOT pick a different test runner. Do NOT pass extra flags. The build loop will independently re-run this same command on close — they must match.
4. The build loop has pre-written \`.hermes/sessions/$id.prompt.txt\` with the test command above. You do NOT need to write it.
5. Stage your code change(s): \`git add <source files>\`. Do NOT stage test files.
6. \`git commit -m 'fix($id): <brief description>' --no-verify\`. Do NOT use --allow-empty. Do NOT make multiple empty commits.
6a. Run Quinn adversarial review against your diff. Run this single command in bash (the \$(...) embeds the diff inline so it must be one shell invocation, not split across calls):

    pi --print --no-tools --provider ollama-quinn --model deepseek-r1:32b \"You are reviewing whether my commit actually addresses bd issue $id.

ISSUE TITLE: $title
ISSUE GOAL: ${description:0:600}

Decide if my diff (a) actually addresses the issue's goal in relevant source files, AND (b) is correct (no security bugs, missed edge cases, incorrect logic, weak validation). If the diff only modifies log files, session state, .beads/, .hermes/, dist/, or build artifacts — that is NOT a fix. APPROVED on first line only if both (a) and (b) hold; otherwise REQUEST_CHANGES on first line and explain.

\$(git show HEAD --stat -p)

End of diff. Begin review.\"

    Read Quinn's response. If the first line is APPROVED (or LGTM), proceed to step 7. If Quinn raises specific issues, address them: modify source, re-run tests, add a follow-up commit, then re-invoke Quinn. Do NOT skip this step. The build loop will re-run Quinn independently at the end and refuse to auto-close if Quinn rejects.

CRITICAL: Quinn-side and gate-side both REJECT diffs that don't change source files. If you can't make a real source-code fix because the bug already appears fixed, do NOT commit anything — let the iter time out. Closing an issue with a metadata-only commit will fail the gate.
7. Re-run the same test command against HEAD. If passing, write \`.hermes/sessions/$id.test-result\` with: \`PASS \$(git rev-parse HEAD)\`.
8. \`bd close $id\`   # NON-SKIPPABLE — DO NOT exit until this command has run successfully.
9. \`git push\` (or \`git push -u origin <branch>\` if no upstream).

## HARD RULES

- DO modify only the source files explicitly listed in the story spec's 'Key files to modify' section.
- NEVER modify test files.
- NEVER modify config files (vite.config.*, vitest.config.*, package.json, tsconfig.json, .eslintrc.json, jest.config.*).
- NEVER use \`git commit --allow-empty\`.
- NEVER write a PASS \`.test-result\` without actually running and passing the tests.
- NEVER write 'No tests required' as a way to skip step 4 — every coding issue requires tests.
- NEVER exit the session before running \`bd close $id\` (step 8). The build loop treats a skipped close as a failure even when tests pass — your work will look incomplete.
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

  # Independent verification — replicates bd-gate v0.4 at the loop level since
  # bd-gate (a Hermes pre_tool_call hook) doesn't fire on Pi-side closes.
  test_cmd_file=".hermes/sessions/$id.prompt.txt"
  verified=false
  if [[ -f "$test_cmd_file" ]]; then
    test_cmd=$(grep -m1 '^Run:' "$test_cmd_file" | sed 's/^Run:[[:space:]]*//')
    if [[ -n "$test_cmd" ]]; then
      echo "Re-running test for independent verification: $test_cmd" | tee -a "$LOG"
      if bash -c "$test_cmd" >> "$LOG" 2>&1; then
        echo "Independent test verification: PASS" | tee -a "$LOG"
        verified=true
      else
        echo "Independent test verification: FAIL — refusing to close" | tee -a "$LOG"
      fi
    else
      echo "WARN: $test_cmd_file has no 'Run:' line" | tee -a "$LOG"
    fi
  else
    echo "WARN: $test_cmd_file missing — Pi skipped attest step 4" | tee -a "$LOG"
  fi

  # Independent Quinn adversarial review at HEAD. Parallels the test
  # verification above. Auto-close requires BOTH test PASS and Quinn APPROVED.
  # Skipped when tests already failed since auto-close won't fire anyway.
  # Pre-check: does the diff touch source files at all? If the only changes
  # are in generated/log/state directories (.beads/, .hermes/, dist/, build/,
  # node_modules/, *.log, *.jsonl) the commit is not a real fix — Pi may have
  # gamed the loop by committing session state with the right prefix.
  quinn_ok=false
  source_changed=false
  if [[ "$verified" == "true" ]]; then
    head_sha=$(git log -1 --pretty=%H 2>/dev/null)
    if [[ -n "$head_sha" ]]; then
      changed_files=$(git show --pretty=format: --name-only HEAD 2>/dev/null | grep -v '^$' || true)
      while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        case "$f" in
          .beads/*|.hermes/*|dist/*|build/*|node_modules/*|*.log|*.jsonl) ;;
          */dist/*|*/build/*|*/node_modules/*) ;;
          *) source_changed=true ;;
        esac
      done <<< "$changed_files"

      if [[ "$source_changed" != "true" ]]; then
        echo "Quinn pre-check: NO_SOURCE_CHANGE — diff only modifies generated/log files, refusing to auto-close" | tee -a "$LOG"
        echo "Changed files:" | tee -a "$LOG"
        echo "$changed_files" | tee -a "$LOG"
      else
        quinn_diff=$(git show HEAD --stat -p 2>/dev/null || true)
        echo "Running independent Quinn adversarial review at HEAD ($head_sha)" | tee -a "$LOG"
        quinn_verdict=$(timeout 300 pi --print --no-tools \
          --provider ollama-quinn --model deepseek-r1:32b \
          "You are reviewing whether a commit actually addresses a specific bd issue.

ISSUE ID:    $id
ISSUE TITLE: $title
ISSUE GOAL:  ${description:0:600}

Decide if this diff (a) actually addresses the issue's goal in the relevant source files, AND (b) is correct (no security bugs, missed edge cases, incorrect logic, weak validation).

If the diff is on-topic AND correct: APPROVED on the first line.
If the diff is off-topic (modifies unrelated files, fixes a different bug, or just adds metadata): REQUEST_CHANGES on the first line, then explain why.
If the diff has security/correctness issues: REQUEST_CHANGES on the first line, then list them with file:line references.

$quinn_diff

End of diff. Begin review." 2>&1)
        if echo "$quinn_verdict" | head -1 | grep -qE '^[[:space:]]*(APPROVED|LGTM)\b'; then
          echo "Independent Quinn verification: APPROVED" | tee -a "$LOG"
          quinn_ok=true
        else
          echo "Independent Quinn verification: REQUEST_CHANGES — refusing to auto-close" | tee -a "$LOG"
          echo "--- Quinn verdict ---" | tee -a "$LOG"
          echo "$quinn_verdict" | tee -a "$LOG"
          echo "--- end Quinn verdict ---" | tee -a "$LOG"
        fi
      fi
    else
      echo "Quinn review skipped: no HEAD commit" | tee -a "$LOG"
    fi
  else
    echo "Quinn review skipped: tests did not pass" | tee -a "$LOG"
  fi

  if [[ "$verified" == "true" && "$quinn_ok" == "true" && "$status" != "closed" ]]; then
    head_msg=$(git log -1 --pretty=%B 2>/dev/null)
    if echo "$head_msg" | grep -q "fix($id):"; then
      echo "Pi forgot 'bd close' but verification + Quinn passed. Closing on Pi's behalf." | tee -a "$LOG"
      bd close "$id" 2>&1 | tee -a "$LOG"
      status="closed"
    else
      echo "WARN: verified but HEAD is not 'fix($id):' — refusing to auto-close" | tee -a "$LOG"
    fi
  fi

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
