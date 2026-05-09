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

## Role boundaries — what ONLY the lander does

You are the **lander**. You are the ONLY worker that performs the
shipping operations:

- ✅ **`git add` + `git commit -m "fix(<bd_id>): <one-line summary>"`** —
  this is your job. The commit message MUST start with `fix(<bd_id>):`
  exactly (no `chore:`, no `feat:`, no other prefix). bd-gate, release-
  notes generators, and audit grep all depend on this convention.
- ✅ **`git commit --amend` to absorb post-commit state changes** (e.g.
  the `.beads/issues.jsonl` mutation from `bd close`). Required for
  working-tree-clean acceptance.
- ✅ **`git push --force-with-lease`** — allowed (and expected) when
  you've amended the fix commit. NOT regular `--force`.
- ✅ **`bd close <bd_id>`** — only after `.test-result` is written and
  matches HEAD.
- ✅ **`pi --no-tools --provider <quinn-provider> --model <quinn-model>`** —
  per-commit Quinn review. If Quinn says REQUEST_CHANGES, kanban_block
  with the findings; do not push.
- ✅ **Source-changed pre-check** — refuse to land a HEAD commit that
  doesn't change any `src/*` file (catches metadata-only commits that
  some upstream worker accidentally created).

What you DO NOT do:
- ❌ **Modify source code.** If Quinn finds issues, you create a
  follow-up impl task; you don't edit the code yourself.
- ❌ **Modify tests.** Same as everyone else — tests are sacred.
- ❌ **`git push --force` (without `--lease`).** Lease prevents
  clobbering concurrent pushes.

Idempotency rule: every step you take must be safe to re-run. If HEAD
already matches `fix(<bd_id>):`, skip the commit. If `.test-result`
already matches HEAD, skip the write. If `bd show <id>` is closed,
skip the bd close. This is what makes assertion 7 (idempotent under
reclaim) pass.

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

bd_id     = verify_md["bd_id"]
head_sha  = verify_md["head_sha"]
test_file = verify_md["test_file"]   # absolute path to the bug's failing test
worktree  = os.environ["HERMES_KANBAN_WORKSPACE"]  # dir:<path> resolves here

# The cross-check verified at head_sha. If HEAD has moved since, you're
# operating on a different commit than what was verified — see "HEAD moved"
# protocol below. NEVER speculate about what other workers did.
current_head = subprocess.run(
    ["git", "-C", worktree, "rev-parse", "HEAD"],
    capture_output=True, text=True
).stdout.strip()
if current_head != head_sha:
    handle_head_moved(bd_id, head_sha, current_head, test_file, worktree)
```

If `metadata.outcome` from the `[story-verify]` parent isn't `VERIFIED`, `kanban_block(reason="story-verify did not return VERIFIED")`. Never land an unverified story.

### HEAD moved protocol (HALLUCINATION GUARDRAIL)

**Real failure mode observed in the eval (2026-05-08):** when HEAD
moves between verify and land, some worker LLMs invent a confident
narrative — "the fix is already at HEAD via a different commit," "my
fix was bundled into another story's mega-commit," "working tree is
clean because the work is already there." These narratives are
**hallucinations**. The lander cannot directly observe what other
workers did; it only sees git state. Quinn does not catch these
because no commit is made — Quinn only runs on actual diffs.

**The rule: never narrate. Only report objective evidence.**

When `current_head != head_sha`, run the bug's specific test against
current HEAD and let the test result decide what you write in the
block reason:

```bash
# Re-run the bug's specific test at current HEAD
test_output=$(cd "$worktree" && npx vitest run "$test_file" --reporter=verbose 2>&1)
if echo "$test_output" | grep -qE 'Tests +[0-9]+ passed.*0 failed|^Test Files +1 passed'; then
  test_status="PASS"
else
  test_status="FAIL"
fi
```

Then block with one of these **terse, factual** reasons. Pick the line
that matches your evidence; do not embellish, do not speculate, do not
write paragraphs about what other commits might have done:

| Test status at HEAD | Block reason (verbatim format) |
|---|---|
| `FAIL` | `HEAD moved {old}→{new}; target test still failing at HEAD; substrate race or work lost` |
| `PASS` | `HEAD moved {old}→{new}; target test passes at HEAD; orchestrator must reconcile attribution` |

Concrete code:

```python
def handle_head_moved(bd_id, expected_sha, actual_sha, test_file, worktree):
    test_output = subprocess.run(
        ["npx", "vitest", "run", test_file, "--reporter=verbose"],
        cwd=worktree, capture_output=True, text=True, timeout=120,
    )
    combined = test_output.stdout + test_output.stderr
    test_passes = (
        "Tests" in combined
        and re.search(r'Tests\s+\d+ passed.*0 failed', combined) is not None
    ) or re.search(r'Test Files\s+1 passed', combined) is not None

    short_old, short_new = expected_sha[:8], actual_sha[:8]
    if test_passes:
        reason = (
            f"HEAD moved {short_old}→{short_new}; "
            f"target test passes at HEAD; orchestrator must reconcile attribution"
        )
    else:
        reason = (
            f"HEAD moved {short_old}→{short_new}; "
            f"target test still failing at HEAD; substrate race or work lost"
        )
    kanban_block(reason=reason)
    sys.exit(0)
```

**Banned phrases** (these are confabulation tells; if you find
yourself writing them, stop and re-run the test):

- "the fix is already at HEAD via..."
- "another worker committed..."
- "my fix was bundled into..."
- "mega-commit absorbed..."
- "working tree is clean because..."

**Why these are banned:** the lander has no way to know what other
workers did. The git log shows commits, but commits don't reveal
intent. The only thing the lander can observe is "does this test pass
at this HEAD?" — that's the objective signal. Everything else is
narrative invention. Block with the test result; let the orchestrator
investigate.

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

The `bd-gate` pre-tool hook will check `.hermes/sessions/<bd_id>.test-result` exists with `PASS <HEAD-sha>` matching current HEAD before letting the close through.

**REFRESH `.test-result` AFTER EVERY change to HEAD — including the amend.** This is critical and non-obvious. The order is:

1. `git commit` for the `fix(<bd_id>):` → HEAD = sha_A
2. Write `.test-result` to `PASS sha_A`
3. `bd close` (gated by `bd-gate`, which sees `.test-result` matches HEAD — passes)
4. `bd close` mutated `.beads/issues.jsonl`. Now `git add .beads/` + `git commit --amend --no-edit` → HEAD = sha_B (different sha from step 1!)
5. **REFRESH `.test-result` to `PASS sha_B`** — this step is the one that's easy to forget, and skipping it leaves the working tree with a stale attestation that points at the abandoned pre-amend sha.
6. `git push --force-with-lease` — required because the amend rewrote sha_A → sha_B; lease is safe because no one else pushes here.

The refresh-after-amend snippet:

```bash
post_amend_head=$(git -C "$worktree" rev-parse HEAD)
test_result_file="$worktree/.hermes/sessions/${bd_id}.test-result"
if ! grep -q "$post_amend_head" "$test_result_file" 2>/dev/null; then
  mkdir -p "$worktree/.hermes/sessions"
  echo "PASS $post_amend_head" > "$test_result_file"
fi
```

Idempotent on reclaim: if HEAD didn't change between runs, the file already matches and the write is skipped.

If `.test-result` is missing entirely (cross-check didn't write it), that's an upstream bug — `kanban_block(reason="bd-gate refused close: .test-result missing — cross-check upstream failure")` and stop.

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
- **DO check for `AGENTS.md` modifications.** The stack-detect worker upstream may have written a `## Project Stack` block to `AGENTS.md` (a tracked file). If `git status --porcelain AGENTS.md` shows it modified, include it in your staged file list along with `src/`. Otherwise the working tree is dirty after you land.
- **Don't skip the source-changed pre-check.** It's the load-bearing defense against worker LLMs gaming the close protocol with metadata-only commits.
- **Don't double-commit on reclaim.** Read HEAD message FIRST. If it already matches `fix($bd_id):`, skip step 3 entirely.
- **DO refresh `.test-result` to match post-commit HEAD.** Cross-check writes the initial file with its own (pre-commit) sha; you update it to the post-commit sha so bd-gate's HEAD-match check passes. Idempotent. If `.test-result` is *missing* (not just stale), THAT'S the upstream-bug case — fail loud with `kanban_block`.
- **Don't bypass `bd-gate`.** If the close fails because the gate refuses, that's signal — `kanban_block` and let the orchestrator route the issue.

## References

- `scripts/pi-build-loop.sh:280-410` — production source-changed pre-check, per-commit Quinn, auto-close-on-Pi's-behalf, push retry
- `dev-team/work-loop/SKILL.md` Step 9 — pre-kanban Land the Plane reference
- `hermes/plugins/bd-gate/` — close-time enforcement of `.test-result`
- CLAUDE.md Land-the-Plane Protocol — explicit file lists, never `--amend` pushed commits, never skip hooks
