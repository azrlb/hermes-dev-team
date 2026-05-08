---
name: cross-check
description: Independent test re-run that replaces work-loop Step 8's MANDATORY CROSS-CHECK. The story-verify task runs the same {test_single_cmd} {test_file} the orchestrator declared, ignoring Pi's claim. On PASS, write .hermes/sessions/{bd_id}.test-result with PASS <HEAD-sha> — bd-gate enforces this file at bd close time, so omitting it blocks the lander.
version: 0.1.0
metadata:
  hermes:
    tags: [kanban, dev-team, verification, cross-check]
    related_skills: [kanban-decomposition, dev-team/pi-dispatcher, dev-team/land-the-plane]
---

# Cross-Check — Independent Test Verification

> You are a kanban worker on a `[story-verify]` task. Your role is the work-loop Step 8 cross-check, expressed as its own kanban task. Pi may have used a different test runner, missed a config flag, or hallucinated a PASS — you re-run the test independently and write the attest file the lander needs.

## Role boundaries — DO NOT

You are the **verifier**. Your ONLY job is to independently re-run the
test and write the `.test-result` attestation. You do NOT:

- ❌ **Modify ANY file in `src/` or `tests/` or any source path.** Not
  even to "fix a flaky test." If the test is wrong, surface it via
  `metadata.outcome=MISMATCH` with the diagnosis; the orchestrator
  routes to a TEST_MISMATCH branch (Quinn reviews the test file
  itself). You don't decide.
- ❌ **`git add` or `git commit`.** Only the lander commits.
- ❌ **`bd close` or any beads writes.** That belongs to the lander.
- ❌ **Push to git.**

Your output is: writing `.hermes/sessions/<bd_id>.test-result` (the
ATTESTATION file — not a source file) + a `kanban_complete` with
`outcome=VERIFIED|MISMATCH|FAIL` and the head_sha you tested against.
Nothing else writes outside `.hermes/sessions/`.

## Liveness — heartbeat to keep your kanban claim

The kanban dispatcher reclaims any task whose claim has been silent for **15 minutes**. When that fires, a duplicate worker spawns on the same task and you race against yourself — neither makes clean progress.

**Required:** call `kanban_heartbeat` with a one-line progress note **before any operation that could take more than 2 minutes**, and again **every ~3 minutes** while it's running. Test re-runs are exactly that kind of operation — heartbeat before you launch the runner, and again while it's executing:

```python
import os
kanban_heartbeat(
    task_id=os.environ["HERMES_KANBAN_TASK"],
    note="re-running npx vitest run on src/__tests__/add.test.ts",
)
```

Good notes name what's happening (`"running npx vitest run, awaiting result"`, `"writing .test-result PASS <sha>"`). Bad notes: `"still working"`, empty, or sub-second intervals. Skip heartbeats only if the whole run will finish in under 2 minutes.

## On startup

```python
ctx  = kanban_show()
body = ctx.get("body", "")
parents = ctx.get("parents", [])

# Two sources for test_single_cmd, in priority order:
#  1. An explicit `test_single_cmd=...` line in YOUR task body. The decomposer
#     puts it there when it has authoritative knowledge, sidestepping any
#     mistakes by stack-detect. THIS IS THE SOURCE OF TRUTH IF PRESENT.
#  2. Parent [story-impl]'s metadata.test_single_cmd (which itself derived
#     from [stack-detect]'s metadata).

import re
m = re.search(r'^test_single_cmd=(.+)$', body, re.MULTILINE)
if m:
    test_single_cmd = m.group(1).strip()
    source = "body"
else:
    impl_md = next(p["metadata"] for p in parents if "impl" in p.get("title", "").lower())
    test_single_cmd = impl_md.get("test_single_cmd")
    source = "parent_metadata"

bd_id     = re.search(r'^bd_id=(.+)$', body, re.MULTILINE).group(1).strip()
test_file = re.search(r'^test_file=(.+)$', body, re.MULTILINE).group(1).strip()
worktree  = os.environ.get("HERMES_KANBAN_WORKSPACE") or \
            re.search(r'^worktree=(.+)$', body, re.MULTILINE).group(1).strip()
```

If `test_single_cmd` is empty in BOTH sources, `kanban_block(reason="cross-check requires test_single_cmd in body or parent metadata")`. Don't guess the test runner.

## The check

```bash
cd "$worktree"
log_file=".hermes/sessions/${bd_id}.cross-check.log"
mkdir -p ".hermes/sessions"

if bash -c "$test_single_cmd $test_file" > "$log_file" 2>&1; then
  outcome="VERIFIED"
else
  outcome="MISMATCH"
fi
```

`MISMATCH` means Pi claimed PASS but the test fails when run independently — usually a wrong-runner mismatch (Pi used `vitest` directly when the project's `test_single_cmd` is `npm test --` or `CI=true npm test --`).

## Writing the attest file (load-bearing for `[story-land]`)

On `VERIFIED`, write the file `bd-gate` will check at `bd close` time:

```bash
if [[ "$outcome" == "VERIFIED" ]]; then
  head_sha=$(git rev-parse HEAD)
  echo "PASS $head_sha" > ".hermes/sessions/${bd_id}.test-result"
fi
```

Format must be exactly `PASS <40-char-sha>` on the first line. The `bd-gate` plugin at `hermes/plugins/bd-gate/` rejects `bd close` calls if this file is missing or doesn't match HEAD. Don't add extra lines.

## Completing the task

**On VERIFIED:**

```python
kanban_complete(
    summary=f"verified story {bd_id}: {tests_passed} tests pass at HEAD={head_sha[:8]}",
    metadata={
        "bd_id": bd_id,
        "outcome": "VERIFIED",
        "head_sha": head_sha,
        "test_single_cmd": test_single_cmd,
        "test_file": test_file,
        "tests_passed": tests_passed,
        "test_result_file": f"{worktree}/.hermes/sessions/{bd_id}.test-result",
    },
)
```

**On MISMATCH:**

```python
kanban_complete(
    summary=f"MISMATCH for story {bd_id} — Pi claimed PASS but independent re-run failed; tail of test output: {tail}",
    metadata={
        "bd_id": bd_id,
        "outcome": "MISMATCH",
        "test_single_cmd": test_single_cmd,
        "tests_passed": tests_passed,
        "tests_failed": tests_failed,
        "log_file": log_file,
    },
)
```

`MISMATCH` is a `kanban_complete` (not block) so the orchestrator can react: in Slice 1 the story stalls; in Slice 2 the orchestrator creates a new `[story-impl-attempt-N+1]` with a `metadata.correction_note` describing the runner mismatch.

**On infra failure (test command can't even run — missing binary, missing dep):**

```python
kanban_block(reason=f"infra: {test_single_cmd} cannot execute — {one_line}")
```

## What this skill does NOT do

- **No bd close.** That's `[story-land]`'s job after reading `metadata.outcome=VERIFIED`.
- **No git commit.** You're read-only on the worktree.
- **No retry of Pi.** You're a verifier, not a fixer.
- **No fall-back to alternate test commands.** `test_single_cmd` is the canonical command from stack-detect; if it's wrong, file a bug against stack-detect via `kanban_block`, don't guess.

## Pitfalls

- **Don't write `.test-result` on FAIL.** bd-gate would let the close through and you'd ship broken code. Empty/missing file on FAIL is correct.
- **Don't write `.test-result` with mismatched sha.** `git rev-parse HEAD` AFTER the test passes — the test should run against the same HEAD bd-gate will check at close time.
- **Don't include the test log inline in summary.** Cap at one line + tail; full output goes to `metadata.log_file` path.

## References

- `dev-team/work-loop/SKILL.md` Step 8 — canonical cross-check definition (lines 226–256 of work-loop)
- `hermes/plugins/bd-gate/` — the pre-tool hook that enforces `.test-result` at `bd close`
- `scripts/pi-build-loop.sh:280-298` — production "Independent verification" block this skill replicates
