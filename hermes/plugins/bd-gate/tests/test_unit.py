"""Offline regex+gate logic test for bd-gate.

Monkey-patches the two probes so we can exercise the branching without
spinning up a git repo. Real repo behavior is covered by the smoke test.
"""
import importlib.util
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "bd_gate", Path.home() / ".hermes/plugins/bd-gate/__init__.py"
)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

# Track probe calls so we can assert the gate is probing the right thing.
probe_calls = []


def set_fixtures(*, has_commit_for=None, has_staged=False):
    """Configure probe stubs for the next case."""
    has_commit_for = has_commit_for or set()
    probe_calls.clear()

    def fake_commit_mentions(issue_id, cwd):
        probe_calls.append(("commit_mentions", issue_id))
        return issue_id in has_commit_for

    def fake_has_staged(cwd):
        probe_calls.append(("has_staged",))
        return has_staged

    mod._commit_mentions = fake_commit_mentions
    mod._has_staged_changes = fake_has_staged


def run(command, **fixtures):
    set_fixtures(**fixtures)
    return mod._gate("terminal", {"command": command})


def expect(label, result, *, blocked: bool, reason_contains: str | None = None,
           probed: list | None = None):
    ok = True
    if blocked:
        if not (isinstance(result, dict) and result.get("action") == "block"):
            ok = False
        elif reason_contains and reason_contains not in result.get("message", ""):
            ok = False
    else:
        if result is not None:
            ok = False
    if probed is not None and probe_calls != probed:
        ok = False
    status = "PASS" if ok else "FAIL"
    print(f"  [{status}] {label}")
    if not ok:
        print(f"    got result   = {result!r}")
        print(f"    probe_calls  = {probe_calls!r}")
        print(f"    expected probes = {probed!r}")
    return ok


print("bd-gate offline cases:")
all_pass = True

# ---- Gate 1: bd close ----
all_pass &= expect(
    "bd close without commit → BLOCK",
    run("bd close Core-9fhd"),
    blocked=True, reason_contains="Core-9fhd",
    probed=[("commit_mentions", "Core-9fhd")],
)

all_pass &= expect(
    "bd close WITH commit → allow",
    run("bd close Core-9fhd", has_commit_for={"Core-9fhd"}),
    blocked=False,
    probed=[("commit_mentions", "Core-9fhd")],
)

# Advisor edge case #1: --reason="done" T2 — flag token shouldn't hijack ID.
all_pass &= expect(
    "bd close --reason=done <id> → probes <id>, not '--reason'",
    run("bd close --reason=done Core-eyjm"),
    blocked=True, reason_contains="Core-eyjm",
    probed=[("commit_mentions", "Core-eyjm")],
)

all_pass &= expect(
    "bd close --reason done <id> (space-separated flag)",
    run("bd close --reason done Core-eyjm"),
    blocked=True, reason_contains="Core-eyjm",
    probed=[("commit_mentions", "Core-eyjm")],
)

# bd update --status=closed variant
all_pass &= expect(
    "bd update <id> --status=closed → BLOCK without commit",
    run("bd update Core-e4hj --status=closed"),
    blocked=True, reason_contains="Core-e4hj",
    probed=[("commit_mentions", "Core-e4hj")],
)

# bd update --claim must NOT fire the close gate
all_pass &= expect(
    "bd update <id> --claim → allow (not a close)",
    run("bd update Core-avqg --claim"),
    blocked=False,
    probed=[],
)

# ---- Gate 2: git commit ----
all_pass &= expect(
    "git commit with staged changes → allow",
    run('git commit -m "fix: whatever"', has_staged=True),
    blocked=False,
    probed=[("has_staged",)],
)

all_pass &= expect(
    "git commit empty diff → BLOCK",
    run('git commit -m "no-op"', has_staged=False),
    blocked=True, reason_contains="no staged",
    probed=[("has_staged",)],
)

all_pass &= expect(
    "git commit --allow-empty → allow (no probe)",
    run('git commit --allow-empty -m "marker"', has_staged=False),
    blocked=False,
    probed=[],
)

# Advisor edge case #2: --allow-empty-message is a DIFFERENT flag;
# it must NOT suppress the staged-changes check.
all_pass &= expect(
    "git commit --allow-empty-message empty diff → BLOCK",
    run('git commit --allow-empty-message -F msg.txt', has_staged=False),
    blocked=True, reason_contains="no staged",
    probed=[("has_staged",)],
)

# ---- Non-matching commands ----
all_pass &= expect(
    "ls -la → allow (no probes)",
    run("ls -la"),
    blocked=False,
    probed=[],
)

all_pass &= expect(
    "git status → allow",
    run("git status"),
    blocked=False,
    probed=[],
)

all_pass &= expect(
    "empty command → allow",
    run(""),
    blocked=False,
    probed=[],
)

# Chained commit+close: order of probes matters.
# Current behavior: we probe close FIRST (which will see no commit yet
# since the chained git commit hasn't run). That's the known limitation
# documented in the plan. Assert the block so a future fix is forced to
# update this test.
all_pass &= expect(
    "CHAINED git commit && bd close → BLOCK (known v1 limitation)",
    run('git commit -m "fix Core-9fhd" && bd close Core-9fhd'),
    blocked=True, reason_contains="Core-9fhd",
    probed=[("commit_mentions", "Core-9fhd")],
)

# Non-terminal tool is ignored.
all_pass &= (mod._gate("file_read", {"command": "bd close X"}) is None)
print(f"  [{'PASS' if all_pass else 'FAIL'}] non-terminal tool → allow")

print("\nRESULT:", "ALL PASS" if all_pass else "FAILURES ABOVE")
sys.exit(0 if all_pass else 1)
