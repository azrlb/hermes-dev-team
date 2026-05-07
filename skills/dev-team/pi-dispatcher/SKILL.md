---
name: pi-dispatcher
description: Bash-wrapping kanban worker that subprocesses Pi (devstral via Ollama) for story implementation. Preserves the production text-only-turn nudge loop from scripts/pi-build-loop.sh — when devstral exits on a narration turn without a tool call, re-invoke up to N times with a continue prompt. The worker's own LLM (also devstral-small-2:24b on the coder-hands endpoint) drives kanban_* tools and the Pi subprocess; Pi runs its own model and uses its own tools inside the spawned process.
version: 0.1.0
metadata:
  hermes:
    tags: [kanban, dev-team, pi, tdd, subprocess]
    related_skills: [kanban-decomposition, dev-team/cross-check, dev-team/land-the-plane]
---

# Pi Dispatcher — Bash-Wrapping Pi Worker

> You are a kanban worker on a `[story-impl]` task assigned to the `pi-coder` profile. Your job is **not to write code yourself** — it's to dispatch Pi as a subprocess, monitor its progress (including the production text-only-turn nudge loop), and complete the kanban task with a structured handoff. The kanban_* tools you call (kanban_show, kanban_complete, kanban_block) are YOUR tools; Pi inside the subprocess has its own tools. The two are separate.

## Liveness — heartbeat to keep your kanban claim

The kanban dispatcher reclaims any task whose claim has been silent for **15 minutes**. When that fires, a duplicate worker spawns on the same task and you race against yourself — neither makes clean progress.

**Required:** call `kanban_heartbeat` with a one-line progress note **before any operation that could take more than 2 minutes**, and again **every ~3 minutes** while it's running. The Pi subprocess is exactly that kind of long operation — heartbeat before you spawn it, and again periodically while polling its output:

```python
import os
kanban_heartbeat(
    task_id=os.environ["HERMES_KANBAN_TASK"],
    note="spawning Pi subprocess (devstral) on story X",
)
# ... later, while polling Pi's stdout ...
kanban_heartbeat(task_id=..., note="Pi turn 4: 2 tests still failing")
```

Good notes name what's happening (`"Pi turn 4: 2 tests still failing"`, `"text-only-turn nudge sent, awaiting tool call"`). Bad notes: `"still working"`, empty, or sub-second intervals. Skip heartbeats only if the whole run will finish in under 2 minutes.

## On startup

```python
import os, json
ctx = kanban_show()
md  = ctx.get("metadata", {})
prior_runs = ctx.get("runs", [])
```

Inspect `prior_runs`. If non-empty, you're a retry — read prior `outcome`/`summary`/`error` to avoid repeating a failed path. (Slice 1 does not exercise retries; Slice 2+ will.)

Pull from your task body and parent metadata via `kanban_show()`:

- `bd_id` — beads issue id
- `story_file` — absolute path to the story spec
- `test_file` — absolute path to the failing TDD test
- `worktree` — absolute path the orchestrator pre-created and threaded as your `workspace=dir:<path>`
- `test_single_cmd` — from `[stack-detect]` parent's metadata
- `pi_session_file` — if set in metadata, you're resuming an earlier Pi session (Slice 2+)

If `test_single_cmd` is missing from any parent's metadata, `kanban_block(reason="stack-detect parent did not emit test_single_cmd in metadata")`.

## The production prompt construction

Faithfully reproduce the prompt structure from `scripts/pi-build-loop.sh:120-220`. Key points:

1. **Pi reads AGENTS.md** for project conventions (auto via `--append-system-prompt ~/.pi/agents/tdd-coder.md` plus Pi's own context auto-load from cwd).
2. **Run only the story's test file**, not the full suite.
3. **Hard rules** Pi must respect: never modify test files, never modify config files, never use `git commit --allow-empty`, never write a PASS `.test-result` without actually running and passing the tests.
4. **Escalation hint** at the bottom: "If you can't make tests pass after 3 different approaches, escalate by spawning the reasoning model: `pi --print --no-tools --provider ollama-quinn --model deepseek-r1:32b ...`" — Slice 1 doesn't exercise this, but the prompt should still mention it so Pi behaves identically to the production path.

Write the full prompt to `<worktree>/.hermes/sessions/<bd_id>.prompt.txt` — preserves newlines, gives the user something to grep, matches `pi-build-loop.sh` convention. Then invoke Pi reading from that file.

## Invoking Pi

```bash
cd $worktree
session_file=".hermes/sessions/${bd_id}.jsonl"
prompt_file=".hermes/sessions/${bd_id}.prompt.txt"
mkdir -p ".hermes/sessions"

# (write $prompt_file with the full production prompt — see above)

# First invocation — fresh session if no pi_session_file in metadata, else --continue.
if [[ -n "${pi_session_file:-}" && -f "$pi_session_file" ]]; then
  pi --print --continue \
     --provider ollama --model devstral-small-2:24b \
     --session "$pi_session_file" \
     --append-system-prompt "$HOME/.pi/agents/tdd-coder.md" \
     "$(cat "$prompt_file")"
else
  pi --print \
     --provider ollama --model devstral-small-2:24b \
     --session "$session_file" \
     --append-system-prompt "$HOME/.pi/agents/tdd-coder.md" \
     "$(cat "$prompt_file")"
fi
exit_code=$?
```

The session file lives **inside the worktree** at `.hermes/sessions/<bd_id>.jsonl` so it's durable — survives kanban task restarts and can be resumed by sibling tasks.

## The text-only-turn nudge loop (load-bearing)

Reproduce verbatim from `scripts/pi-build-loop.sh:229-265`. Devstral sometimes exits with a narration-only assistant turn (no tool call) — Pi's `--print` honors that as "done." If the bd issue isn't actually closed and the last assistant turn has zero tool calls, re-invoke with a "continue" nudge up to `re_invoke_max=5` times.

```bash
re_invoke_max=5
re_invoke_n=0

while [[ "$exit_code" == "0" && $re_invoke_n -lt $re_invoke_max && -f "$session_file" ]]; do
  bd_status=$(bd show "$bd_id" --json 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    i = d[0] if isinstance(d, list) else d
    print(i.get('status', 'unknown'))
except Exception:
    print('unknown')
")
  if [[ "$bd_status" == "closed" ]]; then break; fi

  last_assistant=$(grep '"role":"assistant"' "$session_file" | tail -n1)
  [[ -z "$last_assistant" ]] && break

  tool_call_count=$(echo "$last_assistant" | jq '[.message.content[]? | select(.type=="toolCall")] | length' 2>/dev/null)
  [[ -z "$tool_call_count" || "$tool_call_count" != "0" ]] && break

  re_invoke_n=$((re_invoke_n + 1))
  pi --print \
     --provider ollama --model devstral-small-2:24b \
     --session "$session_file" \
     --append-system-prompt "$HOME/.pi/agents/tdd-coder.md" \
     "Your previous turn was narration only (no tool call) so the runtime exited. Continue the workflow now: emit your next tool call directly, no preamble. Run the tests and complete the work."
  exit_code=$?
done
```

**Why this matters:** without this loop, devstral stalls on narration turns and your kanban worker reports FAIL even though the issue is one tool call from green. The escalation regression suite (`dev-team-work-loop/tests/escalation/assert-escalation-test.sh`) contains an assertion that catches this if dropped — Slice 2 acceptance.

## After Pi returns

Check the actual state — Pi's exit code is necessary but not sufficient. Read the bd issue status and the test result independently:

```bash
post_status=$(bd show "$bd_id" --json | python3 -c "...status extractor...")
test_passed=false
if bash -c "$test_single_cmd $test_file" >> "$run_log" 2>&1; then
  test_passed=true
fi
```

You are NOT the verifier (that's `[story-verify]`'s job, which respawns and runs the same check independently). You ARE responsible for completing your task with accurate metadata so the verifier has signal.

## Completing the task

**On Pi success (tests pass per your subprocess re-run):**

```python
kanban_complete(
    summary=f"shipped story {bd_id} — Pi returned PASS, test re-run confirmed",
    metadata={
        "bd_id": bd_id,
        "outcome": "PASS",
        "exit_code": exit_code,
        "re_invoke_count": re_invoke_n,
        "pi_session_file": session_file_abs,
        "test_single_cmd": test_single_cmd,
        "test_file": test_file,
        "tests_passed": tests_passed,    # parsed from test output
        "tests_failed": 0,
        "changed_files": changed_files,  # git diff --name-only
    },
)
```

**On Pi failure (tests still fail or Pi exited non-zero):**

```python
kanban_complete(
    summary=f"story {bd_id} FAIL after {re_invoke_n} re-invokes — {one_line_reason}",
    metadata={
        "bd_id": bd_id,
        "outcome": "FAIL",
        "exit_code": exit_code,
        "re_invoke_count": re_invoke_n,
        "pi_session_file": session_file_abs,  # so retries can --continue
        "tests_passed": tests_passed,
        "tests_failed": tests_failed,
        "last_error_excerpt": tail_of_run_log,
    },
)
```

**On environmental failure (Pi binary missing, model server down, worktree gone):**

```python
kanban_block(reason=f"infra: {one_line_reason}")
```

Slice 1 expects PASS first try. If you complete with `outcome=FAIL`, the orchestrator is expected to handle it — but Slice 1's orchestrator doesn't react to FAIL yet, so the story stalls. That's OK for Slice 1; it's intentional scope.

## Pitfalls

- **Do not run `bd close` from this skill.** Closing is `[story-land]`'s convergent action. Your job ends with `kanban_complete`.
- **Do not write `.hermes/sessions/<id>.test-result`.** That's `[story-verify]`'s job — bd-gate enforces it as the close gate.
- **Do not modify test files.** Pi's system prompt forbids this; if Pi tried, your worker should detect and FAIL the task with a `last_error_excerpt` showing the diff.
- **Do not invoke `claude -p`.** That's an escalation step encoded in `pi-dispatcher-escalation` (Slice 2), not here.

## References

- `scripts/pi-build-loop.sh:120-265` — canonical prompt construction + text-only-turn nudge loop
- `pi/agents/tdd-coder.md` — Pi's system prompt, loaded via `--append-system-prompt`
- `dev-team/work-loop/SKILL.md` Step 7 — pre-kanban Pi dispatch reference
- `dev-team-work-loop/tests/escalation/assert-escalation-test.sh` — Slice 2 acceptance includes invariants this skill must preserve
