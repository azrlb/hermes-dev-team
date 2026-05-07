---
name: land-the-plane
description: Convergent landing protocol — reads HEAD message + bd status + push state BEFORE acting, skips any step that's already done. Absorbs the production source-changed pre-check (rejects metadata-only commits) and per-commit Quinn (deepseek-r1:32b APPROVED/REQUEST_CHANGES). Idempotent under crash/reclaim by construction. Replaces work-loop Step 9 LAND THE PLANE with kanban-native semantics.
version: 0.1.0
metadata:
  hermes:
    tags: [kanban, dev-team, landing, convergent, idempotent, quinn]
    related_skills: [kanban-decomposition, dev-team/cross-check, dev-team/pi-dispatcher]
---

# Land the Plane — Convergent Landing

> You are a kanban worker on a `[story-land]` task. Your job is to converge the worktree's state to "code committed, bd closed, pushed" — but you're idempotent: if any step is already done, you skip it. This is what makes Slice 1 survive crash/reclaim without double-committing or double-closing.

## Liveness — heartbeat to keep your kanban claim

The kanban dispatcher reclaims any task whose claim has been silent for **15 minutes**. When that fires, a duplicate worker spawns on the same task and you race against yourself — neither makes clean progress.

**Required:** call `kanban_heartbeat` with a one-line progress note **before any operation that could take more than 2 minutes**, and again **every ~3 minutes** while it's running. The per-commit Quinn review (deepseek-r1:32b cold-start ~5 min on first call) is exactly that kind of operation — heartbeat before invoking Quinn:

```python
import os
kanban_heartbeat(
    task_id=os.environ["HERMES_KANBAN_TASK"],
    note="invoking per-commit Quinn (deepseek-r1:32b)",
)
```

Good notes name what's happening (`"running source-changed pre-check"`, `"awaiting Quinn APPROVED/REQUEST_CHANGES"`, `"git push origin main"`). Bad notes: `"still working"`, empty, or sub-second intervals. Skip heartbeats only if the whole run will finish in under 2 minutes.

## On startup

```python
ctx = kanban_show()
parents = ctx.get("parents", [])
verify_md = next(p["metadata"] for p in parents if "story_verify" in p.get("title", ""))

bd_id    = verify_md["bd_id"]
head_sha = verify_md["head_sha"]
worktree = os.environ["HERMES_KANBAN_WORKSPACE"]  # dir:<path> resolves here

# The cross-check verified at head_sha. If HEAD has moved since (race), you're
# operating on a different commit than what was verified — refuse to close.
current_head = subprocess.run(
    ["git", "-C", worktree, "rev-parse", "HEAD"],
    capture_output=True, text=True
).stdout.strip()
if current_head != head_sha:
    kanban_block(reason=f"HEAD moved between verify ({head_sha[:8]}) and land ({current_head[:8]}) — manual review")
```

If `metadata.outcome` from the `[story-verify]` parent isn't `VERIFIED`, `kanban_block(reason="story-verify did not return VERIFIED")`. Never land an unverified story.

## Convergent state checks (the load-bearing pattern)

For each step below, **read state first, act only if needed**. This is what makes the lander idempotent.

### Step 1: Stage non-test files (if not already staged)

The pre-kanban convention bans `git add -A` and `git add .` (per CLAUDE.md Land-the-Plane Protocol — preserve). Stage explicitly using the file list from the `[story-impl]` parent's `metadata.changed_files`:

```bash
impl_changed_files="${impl_md_changed_files[@]}"
# Filter out test files — Pi must never modify them, but defense in depth.
non_test_changed=()
for f in "${impl_changed_files[@]}"; do
  case "$f" in
    *.test.ts|*.test.tsx|*.test.js|*.spec.ts|tests/*|*/__tests__/*) continue ;;
    *) non_test_changed+=("$f") ;;
  esac
done

# Skip if all already in the index.
if ! git -C "$worktree" diff --cached --quiet -- "${non_test_changed[@]}"; then
  staged_already=true
else
  git -C "$worktree" add -- "${non_test_changed[@]}"
  staged_already=false
fi
```

### Step 2: Source-changed pre-check (reject metadata-only commits)

Reproduce verbatim from `scripts/pi-build-loop.sh:339-360`. If the diff only touches `.beads/`, `.hermes/`, `dist/`, `build/`, `node_modules/`, `*.log`, `*.jsonl`, this is NOT a real fix — Pi may have gamed the loop by committing session state with the right prefix.

```bash
source_changed=false
changed_files=$(git -C "$worktree" diff --cached --name-only)
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  case "$f" in
    .beads/*|.hermes/*|dist/*|build/*|node_modules/*|*.log|*.jsonl) ;;
    */dist/*|*/build/*|*/node_modules/*) ;;
    *) source_changed=true ;;
  esac
done <<< "$changed_files"

if [[ "$source_changed" != "true" ]]; then
  # Refuse — fall through to kanban_block below
  block_reason="source-changed pre-check failed: diff only modifies generated/log files"
  kanban_block(reason="$block_reason")
fi
```

### Step 3: Commit (if HEAD doesn't already match)

```bash
head_msg=$(git -C "$worktree" log -1 --pretty=%B 2>/dev/null)
if echo "$head_msg" | grep -q "fix($bd_id):"; then
  # Already committed for this bd id; skip.
  committed_already=true
else
  git -C "$worktree" commit -m "fix($bd_id): $story_title

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
  committed_already=false
fi
```

### Step 4: Per-commit Quinn (production parity)

Reproduce from `scripts/pi-build-loop.sh:362-395`. Independent adversarial review at HEAD via deepseek-r1:32b through the `quinn` provider with `--no-tools` (deepseek rejects tool arrays). Single APPROVED/REQUEST_CHANGES verdict gates auto-close.

```bash
quinn_diff=$(git -C "$worktree" show HEAD --stat -p)
head_sha_now=$(git -C "$worktree" log -1 --pretty=%H)

quinn_verdict=$(timeout 300 pi --print --no-tools \
  --provider ollama-quinn --model deepseek-r1:32b \
  "You are reviewing whether a commit actually addresses a specific bd issue.

ISSUE ID:    $bd_id
ISSUE TITLE: $story_title
ISSUE GOAL:  $story_description_first_600_chars

Decide if this diff (a) actually addresses the issue's goal in the relevant source files, AND (b) is correct (no security bugs, missed edge cases, incorrect logic, weak validation).

If the diff is on-topic AND correct: APPROVED on the first line.
If the diff is off-topic: REQUEST_CHANGES on the first line, then explain why.
If the diff has security/correctness issues: REQUEST_CHANGES on the first line, then list them with file:line references.

$quinn_diff

End of diff. Begin review." 2>&1)

if echo "$quinn_verdict" | head -1 | grep -qE '^[[:space:]]*(APPROVED|LGTM)\b'; then
  quinn_ok=true
else
  quinn_ok=false
  # On REQUEST_CHANGES, complete with metadata.outcome=QUINN_BLOCK so the
  # orchestrator (Slice 2+) can create a [story-impl-quinn-fix-N] sibling.
  # Slice 1 stalls here — that's intentional scope.
fi
```

To **disable per-commit Quinn** (override default), set `metadata.quinn_check_enabled=false` on your task body — the lander reads it and skips this step. Default is enabled (production parity).

### Step 5: bd close (if not already closed)

```bash
bd_status=$(bd show "$bd_id" --json | python3 -c "...status extractor...")
if [[ "$bd_status" != "closed" ]]; then
  bd close "$bd_id"
fi
```

The `bd-gate` pre-tool hook will check `.hermes/sessions/<bd_id>.test-result` exists with `PASS <HEAD-sha>` matching current HEAD before letting the close through. Cross-check already wrote this file; if it's missing, the close fails — `kanban_block(reason="bd-gate refused close: .test-result missing/mismatched")`.

### Step 6: Push (if origin is behind HEAD)

```bash
git -C "$worktree" pull --rebase --autostash
local_head=$(git -C "$worktree" rev-parse HEAD)
remote_head=$(git -C "$worktree" rev-parse "origin/$(git rev-parse --abbrev-ref HEAD)" 2>/dev/null || echo "none")

if [[ "$local_head" != "$remote_head" ]]; then
  git -C "$worktree" push
fi
```

If `git push` fails (network, auth, non-fast-forward), retry once after `git pull --rebase`. Second failure: `kanban_block(reason="push failed: <error>")`. **Never `--force-push`.**

## Completing the task

```python
kanban_complete(
    summary=f"landed story {bd_id} at HEAD={head_sha_now[:8]} (committed={not committed_already}, pushed={pushed_this_run}, quinn=APPROVED)",
    metadata={
        "bd_id": bd_id,
        "outcome": "LANDED",
        "head_sha": head_sha_now,
        "committed_this_run": not committed_already,
        "pushed_this_run": pushed_this_run,
        "quinn_verdict": "APPROVED",
        "skipped_steps": skipped_steps,  # ["already_committed", "already_closed", ...] — useful for retry forensics
    },
)
```

## Idempotency invariant

Re-running this skill twice (e.g., kanban dispatcher reclaims after timeout) MUST leave the repo unchanged after the first successful run. Steps 1–6 each begin with a state read; if state is already at the target, the step is skipped. The Slice 1 acceptance suite includes an explicit re-run check:

> 7. `hermes kanban reclaim {story-land-id}` post-success leaves the repo unchanged (idempotency check, ACs §Slice 1)

If you find yourself wanting to add a "redo this if reclaimed" branch, you've broken the invariant — don't.

## What this skill does NOT do

- **No deploy / no e2e / no report.** Slice 4.
- **No epic-end Quinn 3-layer review.** Slice 3.
- **No reactive fix-loop on Quinn REQUEST_CHANGES.** Slice 2 — the orchestrator creates a `[story-impl-quinn-fix-N]` sibling on QUINN_BLOCK; Slice 1 stalls.
- **No bd dolt push.** That's a separate `bd sync` consideration; the standard `git push` from the worktree is sufficient for Slice 1. Add bd-sync wiring in Slice 5 (Phase 8 bridge) if needed.

## Pitfalls

- **Don't `git add -A` or `git add .`** — bans inherited from CLAUDE.md Land-the-Plane Protocol; ESLint CI hook bans them; this lander honors the same constraint via explicit file lists.
- **Don't skip the source-changed pre-check.** It's the load-bearing defense against worker LLMs gaming the close protocol with metadata-only commits.
- **Don't double-commit on reclaim.** Read HEAD message FIRST. If it already matches `fix($bd_id):`, skip step 3 entirely.
- **Don't write `.test-result` from this skill.** Cross-check does that. If it's missing here, fail loud (`kanban_block`) — don't paper over.
- **Don't bypass `bd-gate`.** If the close fails because the gate refuses, that's signal — `kanban_block` and let the orchestrator route the issue.

## References

- `scripts/pi-build-loop.sh:280-410` — production source-changed pre-check, per-commit Quinn, auto-close-on-Pi's-behalf, push retry
- `dev-team/work-loop/SKILL.md` Step 9 — pre-kanban Land the Plane reference
- `hermes/plugins/bd-gate/` — close-time enforcement of `.test-result`
- CLAUDE.md Land-the-Plane Protocol — explicit file lists, never `--amend` pushed commits, never skip hooks
