#!/usr/bin/env bash
# gepa-monthly.sh — automated monthly skill evolution.
#
# Schedule: first Sunday of each month at 03:00 (via cron).
# Each run rotates through one of four priority skills:
#   Month 1 → escalation-handler
#   Month 2 → pi-dispatcher
#   Month 3 → cross-check
#   Month 4 → land-the-plane
#   Month 5 → escalation-handler (cycle repeats)
#
# Per run:
#   1. Source ~/.gepa-env for the Nous API key
#   2. Pick this month's target skill from the rotation
#   3. Run GEPA (5 iterations) → produces an evolved SKILL.md candidate
#   4. Validate candidate via dspy's built-in constraint checker
#   5. Run a Quinn-style audit (sonnet-4.6) on the diff, looking for:
#        - banned-phrase regressions
#        - role-boundary drift (DO / DO NOT removals)
#        - table-structure regressions
#        - security-theater additions
#   6. APPROVED → create a branch, commit, push, open a GitHub PR
#      REJECTED → archive the candidate to _evolved/rejected/ with reasoning
#   7. Append outcome to logs/gepa-monthly.log
#
# All results are durable. The user reviews PRs at their convenience; nothing
# auto-merges into dev or main.

set -uo pipefail

REPO_ROOT="/media/bob/C/AI_Projects/hermes-dev-team"
EVO_REPO="/media/bob/C/AI_Projects/hermes-agent-self-evolution"
LOG_FILE="$REPO_ROOT/logs/gepa-monthly.log"
EVOLVED_DIR="$REPO_ROOT/_evolved"
ENV_FILE="$HOME/.gepa-env"

OPTIMIZER_MODEL="openai/anthropic/claude-sonnet-4.6"
EVAL_MODEL="openai/xiaomi/mimo-v2.5"
AUDIT_MODEL="anthropic/claude-sonnet-4.6"   # for direct curl in audit step
ITERATIONS=5

mkdir -p "$REPO_ROOT/logs" "$EVOLVED_DIR/approved" "$EVOLVED_DIR/rejected"

log() { printf '[%s] %s\n' "$(date -Iseconds)" "$*" | tee -a "$LOG_FILE"; }
fail() { log "FAIL: $*"; exit 1; }

# ─── Pre-flight ───────────────────────────────────────────────────────────────

[[ -f "$ENV_FILE" ]] || fail "no $ENV_FILE — see scripts/README-gepa-setup.md"
# shellcheck source=/dev/null
source "$ENV_FILE"
[[ -n "${NOUS_API_KEY:-}" ]] || fail "NOUS_API_KEY not set after sourcing $ENV_FILE"

[[ -d "$EVO_REPO" ]] || fail "hermes-agent-self-evolution not at $EVO_REPO"
[[ -x "$EVO_REPO/.venv/bin/python" ]] || fail "$EVO_REPO/.venv missing — run pip install -e .[dev]"

# ─── Pick this month's skill ──────────────────────────────────────────────────

SKILLS_ROTATION=(escalation-handler pi-dispatcher cross-check land-the-plane)
MONTH_INDEX=$(( ($(date +%-m) - 1) % ${#SKILLS_ROTATION[@]} ))
SKILL_OVERRIDE="${1:-}"
if [[ -n "$SKILL_OVERRIDE" ]]; then
  SKILL="$SKILL_OVERRIDE"
  log "skill override: $SKILL (passed via CLI arg)"
else
  SKILL="${SKILLS_ROTATION[$MONTH_INDEX]}"
  log "this month's rotation pick: $SKILL (month index $MONTH_INDEX)"
fi

ORIGINAL_SKILL_PATH="$REPO_ROOT/skills/dev-team/$SKILL/SKILL.md"
[[ -f "$ORIGINAL_SKILL_PATH" ]] || fail "skill file not found: $ORIGINAL_SKILL_PATH"

DATESTAMP="$(date +%Y-%m)"
RUN_DIR="$EVOLVED_DIR/$DATESTAMP-$SKILL"
mkdir -p "$RUN_DIR"

cp "$ORIGINAL_SKILL_PATH" "$RUN_DIR/original.md"

# ─── Step 1: Run GEPA ─────────────────────────────────────────────────────────

log "starting GEPA on $SKILL ($ITERATIONS iterations)..."
GEPA_LOG="$RUN_DIR/gepa.log"
EVOLVED_OUTPUT="$EVO_REPO/output/$SKILL/evolved.md"
EVOLVED_FAILED="$EVO_REPO/output/$SKILL/evolved_FAILED.md"

(
  export OPENAI_API_KEY="$NOUS_API_KEY"
  export OPENAI_API_BASE="https://inference-api.nousresearch.com/v1"
  cd "$EVO_REPO"
  .venv/bin/python -m evolution.skills.evolve_skill \
    --skill "$SKILL" \
    --hermes-repo "$REPO_ROOT" \
    --iterations "$ITERATIONS" \
    --optimizer-model "$OPTIMIZER_MODEL" \
    --eval-model "$EVAL_MODEL" \
    --eval-source synthetic
) > "$GEPA_LOG" 2>&1
GEPA_EXIT=$?

if [[ "$GEPA_EXIT" != "0" ]]; then
  log "GEPA exited non-zero ($GEPA_EXIT). Tail:"
  tail -20 "$GEPA_LOG" | sed 's/^/  /' | tee -a "$LOG_FILE"
  mv "$RUN_DIR" "$EVOLVED_DIR/rejected/$DATESTAMP-$SKILL-gepa-error"
  fail "GEPA invocation failed; archive at $EVOLVED_DIR/rejected/$DATESTAMP-$SKILL-gepa-error"
fi

# Pick whichever output GEPA produced (passes or fails dspy's own validators)
if [[ -f "$EVOLVED_OUTPUT" ]]; then
  cp "$EVOLVED_OUTPUT" "$RUN_DIR/evolved.md"
  log "GEPA produced evolved.md (passed dspy constraints)"
elif [[ -f "$EVOLVED_FAILED" ]]; then
  cp "$EVOLVED_FAILED" "$RUN_DIR/evolved.md"
  log "GEPA produced evolved_FAILED.md (failed dspy constraints — still auditing)"
else
  log "GEPA produced no output file. Tail:"
  tail -10 "$GEPA_LOG" | sed 's/^/  /' | tee -a "$LOG_FILE"
  mv "$RUN_DIR" "$EVOLVED_DIR/rejected/$DATESTAMP-$SKILL-no-output"
  fail "GEPA produced no candidate; archive at $EVOLVED_DIR/rejected/$DATESTAMP-$SKILL-no-output"
fi

# ─── Step 2: Quick equality check — skip downstream if unchanged ──────────────

if diff -q "$RUN_DIR/original.md" "$RUN_DIR/evolved.md" >/dev/null 2>&1; then
  log "evolved == original (GEPA found no improvement). Archiving as no-op."
  mv "$RUN_DIR" "$EVOLVED_DIR/rejected/$DATESTAMP-$SKILL-no-change"
  log "DONE: no-op archive at $EVOLVED_DIR/rejected/$DATESTAMP-$SKILL-no-change"
  exit 0
fi

# ─── Step 3: Re-run fixtures against the evolved SKILL ────────────────────────

log "swapping evolved SKILL into place temporarily for fixture run..."
BACKUP="$RUN_DIR/original-backup.md"
cp "$ORIGINAL_SKILL_PATH" "$BACKUP"
cp "$RUN_DIR/evolved.md" "$ORIGINAL_SKILL_PATH"

FIXTURE_FAIL=0
case "$SKILL" in
  escalation-handler|block-watcher)
    log "running kanban-block-watcher fixture..."
    if bash "$REPO_ROOT/dev-team-work-loop/tests/kanban-block-watcher/run-block-watcher.sh" \
         > "$RUN_DIR/fixture-block-watcher.log" 2>&1 \
       && bash "$REPO_ROOT/dev-team-work-loop/tests/kanban-block-watcher/assert-block-watcher.sh" \
         >> "$RUN_DIR/fixture-block-watcher.log" 2>&1; then
      log "  PASS: kanban-block-watcher"
    else
      log "  FAIL: kanban-block-watcher"
      FIXTURE_FAIL=1
    fi
    ;;
  land-the-plane)
    log "running kanban-lander-head-moved fixture..."
    if bash "$REPO_ROOT/dev-team-work-loop/tests/kanban-lander-head-moved/run-head-moved.sh" \
         > "$RUN_DIR/fixture-head-moved.log" 2>&1 \
       && bash "$REPO_ROOT/dev-team-work-loop/tests/kanban-lander-head-moved/assert-head-moved.sh" \
         >> "$RUN_DIR/fixture-head-moved.log" 2>&1; then
      log "  PASS: kanban-lander-head-moved"
    else
      log "  FAIL: kanban-lander-head-moved"
      FIXTURE_FAIL=1
    fi
    ;;
  *)
    log "no fixture mapping for $SKILL — relying on audit only"
    ;;
esac

cp "$BACKUP" "$ORIGINAL_SKILL_PATH"
log "restored original SKILL to working tree"

if [[ "$FIXTURE_FAIL" == "1" ]]; then
  cp "$RUN_DIR/evolved.md" "$EVOLVED_DIR/rejected/$DATESTAMP-$SKILL-fixture-fail.md"
  log "REJECTED — fixture failure. Archive at $EVOLVED_DIR/rejected/$DATESTAMP-$SKILL-fixture-fail.md"
  mv "$RUN_DIR" "$EVOLVED_DIR/rejected/$DATESTAMP-$SKILL-fixture-fail"
  exit 0
fi

# ─── Step 4: Quinn-style audit (sonnet-4.6 reads diff, decides) ──────────────

log "running Quinn-style audit via sonnet-4.6..."
ORIGINAL_CONTENT=$(cat "$RUN_DIR/original.md")
EVOLVED_CONTENT=$(cat "$RUN_DIR/evolved.md")
AUDIT_PROMPT_FILE="$RUN_DIR/audit-prompt.txt"
AUDIT_RESPONSE_FILE="$RUN_DIR/audit-response.txt"

cat > "$AUDIT_PROMPT_FILE" <<EOF
You are auditing a proposed change to a Hermes Agent skill file. The skill is dev-team/$SKILL — a runtime instruction file followed by an LLM worker in production.

Review checklist (each must hold for APPROVED):

1. BANNED-PHRASE PRESERVATION — any "banned phrases" or "must-not-write" lists in the ORIGINAL must be preserved verbatim in the EVOLVED version. Removing or weakening them is auto-REJECTED.

2. ROLE-BOUNDARY PRESERVATION — DO and DO NOT lists ("you ONLY do X", "you MUST NOT do Y") must be preserved. Adding new boundaries is OK; removing or weakening existing ones is auto-REJECTED.

3. TABLE-STRUCTURE PRESERVATION — classification tables, recovery-routing tables, and acceptance-criteria tables must be preserved. Adding rows is OK if labeled as additions; removing or reordering rows is auto-REJECTED.

4. NO SECURITY-THEATER ADDITIONS — rules that look strict but actually permit weaker behavior (e.g. "verify X is true" without specifying how, "validate appropriately"). Auto-REJECTED if found.

5. NO SEMANTIC DRIFT — the skill's stated purpose, role boundaries, and downstream contract (what calls it, what it produces) must be preserved.

ORIGINAL SKILL:
\`\`\`markdown
$ORIGINAL_CONTENT
\`\`\`

PROPOSED EVOLVED SKILL:
\`\`\`markdown
$EVOLVED_CONTENT
\`\`\`

Output format:
- First line: exactly APPROVED or REJECTED (no other words).
- Subsequent lines: bullet list of specific concerns (REJECTED) or specific improvements (APPROVED). Reference exact line content where relevant.

Your audit:
EOF

curl -sS -X POST https://api.anthropic.com/v1/messages \
  -H "x-api-key: ${ANTHROPIC_API_KEY:-}" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d "$(python3 -c "
import json, sys
with open('$AUDIT_PROMPT_FILE') as f: prompt = f.read()
print(json.dumps({
    'model': 'claude-sonnet-4-6',
    'max_tokens': 2048,
    'messages': [{'role': 'user', 'content': prompt}]
}))
")" > "$RUN_DIR/audit-raw.json" 2>&1

# Try Anthropic direct first; fall back to Nous Portal if that fails
if ! python3 -c "
import json
with open('$RUN_DIR/audit-raw.json') as f:
    d = json.load(f)
if 'content' in d and d['content']:
    print(d['content'][0]['text'])
else:
    raise SystemExit('no content')
" > "$AUDIT_RESPONSE_FILE" 2>/dev/null; then
  log "Anthropic API failed; falling back to Nous Portal for audit..."
  curl -sS -X POST https://inference-api.nousresearch.com/v1/chat/completions \
    -H "Authorization: Bearer $NOUS_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "
import json
with open('$AUDIT_PROMPT_FILE') as f: prompt = f.read()
print(json.dumps({
    'model': 'anthropic/claude-sonnet-4.6',
    'messages': [{'role': 'user', 'content': prompt}],
    'max_tokens': 2048
}))
")" > "$RUN_DIR/audit-raw.json" 2>&1
  python3 -c "
import json, sys
with open('$RUN_DIR/audit-raw.json') as f:
    d = json.load(f)
print(d['choices'][0]['message']['content'])
" > "$AUDIT_RESPONSE_FILE" 2>/dev/null \
    || fail "audit failed via both Anthropic + Nous endpoints; see $RUN_DIR/audit-raw.json"
fi

VERDICT=$(head -1 "$AUDIT_RESPONSE_FILE" | tr -d '[:space:]' | tr 'a-z' 'A-Z')
log "audit verdict: $VERDICT"

# ─── Step 5: Act on verdict ───────────────────────────────────────────────────

case "$VERDICT" in
  APPROVED)
    log "APPROVED — opening PR"
    BRANCH="gepa/$DATESTAMP-$SKILL"
    cd "$REPO_ROOT"
    git checkout -b "$BRANCH" 2>&1 | tee -a "$LOG_FILE" || fail "could not create branch $BRANCH"
    cp "$RUN_DIR/evolved.md" "$ORIGINAL_SKILL_PATH"
    git add "$ORIGINAL_SKILL_PATH"

    PR_BODY_FILE="$RUN_DIR/pr-body.md"
    cat > "$PR_BODY_FILE" <<PR
## Summary

GEPA-evolved \`dev-team/$SKILL\` (monthly automated run, $DATESTAMP).

## Audit verdict: APPROVED

$(tail -n +2 "$AUDIT_RESPONSE_FILE")

## Provenance

- GEPA log:           \`_evolved/$DATESTAMP-$SKILL/gepa.log\`
- Audit prompt:       \`_evolved/$DATESTAMP-$SKILL/audit-prompt.txt\`
- Audit response:     \`_evolved/$DATESTAMP-$SKILL/audit-response.txt\`
- Iterations:         $ITERATIONS
- Optimizer model:    $OPTIMIZER_MODEL
- Eval model:         $EVAL_MODEL
- Audit model:        $AUDIT_MODEL

## Test plan

- [ ] Skim the SKILL.md diff for surprises
- [ ] If escalation-handler / block-watcher / land-the-plane: re-run the corresponding fixture locally
- [ ] Merge if comfortable

🤖 Generated automatically by \`scripts/gepa-monthly.sh\`
PR

    git -c user.email=gepa-bot@local -c user.name="gepa-bot" \
      commit -m "feat(skill): GEPA-evolved $SKILL ($DATESTAMP)

Audited by Sonnet 4.6 — APPROVED.
See _evolved/$DATESTAMP-$SKILL/ for the full provenance trail.
" 2>&1 | tee -a "$LOG_FILE"

    git push -u origin "$BRANCH" 2>&1 | tee -a "$LOG_FILE" \
      || { log "push failed — branch retained locally"; }

    if command -v gh >/dev/null 2>&1; then
      gh pr create --title "GEPA-evolved $SKILL ($DATESTAMP)" --body-file "$PR_BODY_FILE" \
        2>&1 | tee -a "$LOG_FILE" \
        || log "gh pr create failed; you can open the PR manually from $BRANCH"
    else
      log "gh not installed — open the PR manually from branch $BRANCH"
    fi

    git checkout - 2>&1 | tee -a "$LOG_FILE"
    cp "$BACKUP" "$ORIGINAL_SKILL_PATH"

    mv "$RUN_DIR" "$EVOLVED_DIR/approved/$DATESTAMP-$SKILL"
    log "DONE: PR opened, archive at $EVOLVED_DIR/approved/$DATESTAMP-$SKILL"
    ;;

  REJECTED)
    log "REJECTED — archiving"
    cp "$RUN_DIR/audit-response.txt" "$RUN_DIR/decision.md"
    mv "$RUN_DIR" "$EVOLVED_DIR/rejected/$DATESTAMP-$SKILL"
    log "DONE: rejected archive at $EVOLVED_DIR/rejected/$DATESTAMP-$SKILL"
    ;;

  *)
    log "audit returned unexpected verdict: '$VERDICT' — treating as REJECTED"
    cp "$RUN_DIR/audit-response.txt" "$RUN_DIR/decision.md"
    mv "$RUN_DIR" "$EVOLVED_DIR/rejected/$DATESTAMP-$SKILL-unexpected-verdict"
    ;;
esac

log "gepa-monthly.sh complete."
