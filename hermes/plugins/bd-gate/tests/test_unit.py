"""Offline regex+gate logic test for bd-gate.

Monkey-patches the probes so we can exercise the branching without spinning
up a git repo. Real repo behavior is covered by the integration test.
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


def set_fixtures(*, files_for=None, has_staged=False, stash_count=0,
                 head_sha="abcd1234ef", test_result_for=None,
                 # New (Gates 5/6/7) fixture inputs:
                 dmr_files_for=None, parent_sha=None, file_at_sha=None,
                 file_at_head=None, commit_msgs="", issue_title=""):
    """Configure probe stubs for the next case.

    files_for:        dict mapping issue_id -> list[str] of files (Gate 1; ALL filter)
    has_staged:       value returned by the staged-changes probe
    stash_count:      value returned by the stash probe
    head_sha:         value returned by the HEAD probe
    test_result_for:  dict mapping issue_id -> (exists: bool, content: str)
    dmr_files_for:    dict mapping issue_id -> list[str] (DMR-filter — for Gates 5/6/7)
    parent_sha:       string returned by _first_commit_parent_for_issue
    file_at_sha:      dict mapping (sha, path) -> file content (str) or None
    file_at_head:     dict mapping path -> current file content (str) for HEAD
    commit_msgs:      string returned by _commit_messages_for_issue
    issue_title:      string returned by _issue_title
    """
    files_for = files_for or {}
    test_result_for = test_result_for or {}
    dmr_files_for = dmr_files_for or {}
    file_at_sha = file_at_sha or {}
    file_at_head = file_at_head or {}
    probe_calls.clear()

    def fake_commit_files(issue_id, cwd):
        probe_calls.append(("commit_files", issue_id))
        if issue_id not in files_for:
            return (True, [])
        return (True, list(files_for[issue_id]))

    def fake_commit_files_filtered(issue_id, cwd, diff_filter):
        probe_calls.append(("commit_files_filtered", issue_id, diff_filter))
        if issue_id not in dmr_files_for:
            return (True, [])
        return (True, list(dmr_files_for[issue_id]))

    def fake_has_staged(cwd):
        probe_calls.append(("has_staged",))
        return has_staged

    def fake_stash_count(cwd):
        probe_calls.append(("stash_count",))
        return stash_count

    def fake_head_sha(cwd):
        probe_calls.append(("head_sha",))
        return head_sha

    def fake_test_result(issue_id, cwd):
        probe_calls.append(("test_result", issue_id))
        if issue_id not in test_result_for:
            return (False, "")
        return test_result_for[issue_id]

    def fake_first_parent(issue_id, cwd):
        probe_calls.append(("first_parent", issue_id))
        return parent_sha

    def fake_file_at_sha(sha, path, cwd):
        probe_calls.append(("file_at_sha", sha, path))
        return file_at_sha.get((sha, path))

    def fake_commit_msgs(issue_id, cwd):
        probe_calls.append(("commit_msgs", issue_id))
        return commit_msgs

    def fake_issue_title(issue_id, cwd):
        probe_calls.append(("issue_title", issue_id))
        return issue_title

    mod._commit_files_for_issue = fake_commit_files
    mod._commit_files_for_issue_filtered = fake_commit_files_filtered
    mod._has_staged_changes = fake_has_staged
    mod._stash_count = fake_stash_count
    mod._head_sha = fake_head_sha
    mod._read_test_result = fake_test_result
    mod._first_commit_parent_for_issue = fake_first_parent
    mod._file_at_sha = fake_file_at_sha
    mod._commit_messages_for_issue = fake_commit_msgs
    mod._issue_title = fake_issue_title

    # Patch Path(cwd) / path file reads for Gate 6/7 "after" state.
    # We monkey-patch Path.read_text for paths that match file_at_head keys.
    import builtins
    _original_open = builtins.open
    _file_at_head = dict(file_at_head)

    class _FakePath:
        def __init__(self, raw_path):
            self._raw = str(raw_path)
        def read_text(self):
            for key, content in _file_at_head.items():
                if self._raw.endswith(key):
                    return content
            raise FileNotFoundError(self._raw)

    # Monkey-patch on the gate module's Path attribute. The gate uses
    # `(Path(cwd) if cwd else Path.cwd()).joinpath(path).read_text()`.
    # We replace Path with a thin wrapper so .joinpath returns _FakePath.
    class _PathWrapper:
        def __init__(self, *args, **kwargs):
            pass
        def joinpath(self, path):
            return _FakePath(path)
        @staticmethod
        def cwd():
            return _PathWrapper()
        def __truediv__(self, path):
            return _FakePath(path)

    mod.Path = _PathWrapper


def run(command, **fixtures):
    set_fixtures(**fixtures)
    return mod._gate("terminal", {"command": command})


def expect(label, result, *, blocked: bool, reason_contains: str | None = None):
    ok = True
    if blocked:
        if not (isinstance(result, dict) and result.get("action") == "block"):
            ok = False
        elif reason_contains and reason_contains not in result.get("message", ""):
            ok = False
    else:
        if result is not None:
            ok = False
    status = "PASS" if ok else "FAIL"
    print(f"  [{status}] {label}")
    if not ok:
        print(f"    got result   = {result!r}")
        print(f"    probe_calls  = {probe_calls!r}")
    return ok


print("bd-gate offline cases:")
all_pass = True

# ─── Helpers for the most common allow-fixture ────────────────────────────────
# A "good close" needs: a real-code commit + no stash + fresh PASS@HEAD.
HEAD = "abcd1234ef"
GOOD_TEST_RESULT = (True, f"PASS {HEAD}")


def good_close_fixtures(issue_id, files=("src/foo.ts",)):
    """Fixtures representing a legitimate, fully-attested close."""
    return dict(
        files_for={issue_id: list(files)},
        stash_count=0,
        head_sha=HEAD,
        test_result_for={issue_id: GOOD_TEST_RESULT},
    )


# ───────────────── Gate 1: close-without-commit ─────────────────
all_pass &= expect(
    "bd close without any commit → BLOCK (no commit references)",
    run("bd close Core-9fhd"),
    blocked=True, reason_contains="no commit",
)

# ───────────────── Gate 1: substance check (NEW) ─────────────────
all_pass &= expect(
    "bd close with commit touching ONLY .beads/ → BLOCK (substance)",
    run("bd close Core-djb",
        files_for={"Core-djb": [".beads/issues.jsonl"]},
        stash_count=0, head_sha=HEAD,
        test_result_for={"Core-djb": GOOD_TEST_RESULT}),
    blocked=True, reason_contains="only touch .beads/",
)

all_pass &= expect(
    "bd close with multi-commit fix (.beads/ + real code) → allow",
    run("bd close Core-djb",
        files_for={"Core-djb": [".beads/issues.jsonl", "src/mtls.ts"]},
        stash_count=0, head_sha=HEAD,
        test_result_for={"Core-djb": GOOD_TEST_RESULT}),
    blocked=False,
)

# ───────────────── Gate 3: stash check (NEW) ─────────────────
all_pass &= expect(
    "bd close with non-empty stash → BLOCK",
    run("bd close Core-9fhd",
        files_for={"Core-9fhd": ["src/foo.ts"]},
        stash_count=1, head_sha=HEAD,
        test_result_for={"Core-9fhd": GOOD_TEST_RESULT}),
    blocked=True, reason_contains="stash entr",
)

all_pass &= expect(
    "bd close pluralization (3 stashes) → BLOCK with 'entries'",
    run("bd close Core-9fhd",
        files_for={"Core-9fhd": ["src/foo.ts"]},
        stash_count=3, head_sha=HEAD,
        test_result_for={"Core-9fhd": GOOD_TEST_RESULT}),
    blocked=True, reason_contains="3 stash entries",
)

# ───────────────── Gate 4: test-result attestation (NEW) ─────────────────
all_pass &= expect(
    "bd close without test-result file → BLOCK",
    run("bd close Core-9fhd",
        files_for={"Core-9fhd": ["src/foo.ts"]},
        stash_count=0, head_sha=HEAD),
    blocked=True, reason_contains="missing test attestation",
)

all_pass &= expect(
    "bd close with test-result starting FAIL → BLOCK",
    run("bd close Core-9fhd",
        files_for={"Core-9fhd": ["src/foo.ts"]},
        stash_count=0, head_sha=HEAD,
        test_result_for={"Core-9fhd": (True, f"FAIL {HEAD}")}),
    blocked=True, reason_contains="does not start with `PASS",
)

all_pass &= expect(
    "bd close with stale test-result (sha mismatch) → BLOCK",
    run("bd close Core-9fhd",
        files_for={"Core-9fhd": ["src/foo.ts"]},
        stash_count=0, head_sha=HEAD,
        test_result_for={"Core-9fhd": (True, "PASS deadbeef0011")}),
    blocked=True, reason_contains="stale test attestation",
)

all_pass &= expect(
    "bd close with PASS+abbreviated sha (prefix match) → allow",
    run("bd close Core-9fhd",
        files_for={"Core-9fhd": ["src/foo.ts"]},
        stash_count=0, head_sha="abcd1234ef0011223344",
        test_result_for={"Core-9fhd": (True, "PASS abcd1234")}),
    blocked=False,
)

# ───────────────── Gate 5: test-file immutability (NEW) ─────────────────
# Modifying an existing test file blocks. Adding NEW test files is OK
# (DMR filter excludes pure A — added files don't show up).
all_pass &= expect(
    "bd close with modified test file (DMR filter hit) → BLOCK",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        dmr_files_for={"Core-djb": ["packages/auth/src/__tests__/mtls.test.ts"]}),
    blocked=True, reason_contains="modified, deleted, or renamed existing test files",
)

all_pass &= expect(
    "bd close with deleted test file (DMR D) → BLOCK",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        dmr_files_for={"Core-djb": ["src/__tests__/foo.test.ts"]}),
    blocked=True, reason_contains="modified, deleted, or renamed existing test files",
)

all_pass &= expect(
    "bd close with .spec.ts file modified → BLOCK",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        dmr_files_for={"Core-djb": ["src/foo.spec.ts"]}),
    blocked=True, reason_contains="modified, deleted, or renamed existing test files",
)

all_pass &= expect(
    "bd close with foo_test.go (Go convention) → BLOCK",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        dmr_files_for={"Core-djb": ["pkg/auth/auth_test.go"]}),
    blocked=True, reason_contains="modified, deleted, or renamed existing test files",
)

all_pass &= expect(
    "bd close with NO test files in DMR list → allow (Gate 5 inert)",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        dmr_files_for={"Core-djb": ["src/foo.ts"]}),
    blocked=False,
)

# ───────────────── Gate 6: export preservation (NEW) ─────────────────
all_pass &= expect(
    "bd close with export removed (no BREAKING:) → BLOCK",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb", files=("src/foo.ts",)),
        dmr_files_for={"Core-djb": ["src/foo.ts"]},
        parent_sha="parent123",
        file_at_sha={
            ("parent123", "src/foo.ts"): "export function bar() { return 1; }\nexport class Baz {}\n",
        },
        file_at_head={"src/foo.ts": "export function bar() { return 1; }\n"},
        commit_msgs="fix(Core-djb): remove unused class\n",
        issue_title="[EVAL] Some bug"),
    blocked=True, reason_contains="export(s) removed",
)

all_pass &= expect(
    "bd close with export removed BUT BREAKING: in commit msg → allow",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb", files=("src/foo.ts",)),
        dmr_files_for={"Core-djb": ["src/foo.ts"]},
        parent_sha="parent123",
        file_at_sha={
            ("parent123", "src/foo.ts"): "export function bar() {}\nexport class Baz {}\n",
        },
        file_at_head={"src/foo.ts": "export function bar() {}\n"},
        commit_msgs="fix(Core-djb): BREAKING: remove Baz class — see migration\n",
        issue_title=""),
    blocked=False,
)

all_pass &= expect(
    "bd close with no exports removed → allow (Gate 6 inert)",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb", files=("src/foo.ts",)),
        dmr_files_for={"Core-djb": ["src/foo.ts"]},
        parent_sha="parent123",
        file_at_sha={
            ("parent123", "src/foo.ts"): "export function bar() {}\n",
        },
        file_at_head={"src/foo.ts": "export function bar() { return 'fixed'; }\nexport function newHelper() {}\n"},
        commit_msgs="fix(Core-djb): bug fix\n"),
    blocked=False,
)

# ───────────────── Gate 7: code-reduction sanity (NEW) ─────────────────
all_pass &= expect(
    "bd close with file shrinking 80% (no refactor keyword) → BLOCK",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb", files=("src/foo.ts",)),
        dmr_files_for={"Core-djb": ["src/foo.ts"]},
        parent_sha="parent123",
        file_at_sha={
            ("parent123", "src/foo.ts"): "// big file\n" * 100,  # 100 lines
        },
        file_at_head={"src/foo.ts": "// small\n" * 10},  # 10 lines
        commit_msgs="fix(Core-djb): bug fix\n"),
    blocked=True, reason_contains="shrank from",
)

all_pass &= expect(
    "bd close with file shrinking BUT 'refactor' in issue title → allow",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb", files=("src/foo.ts",)),
        dmr_files_for={"Core-djb": ["src/foo.ts"]},
        parent_sha="parent123",
        file_at_sha={
            ("parent123", "src/foo.ts"): "// big file\n" * 100,
        },
        file_at_head={"src/foo.ts": "// small\n" * 10},
        commit_msgs="fix(Core-djb): consolidate\n",
        issue_title="[EVAL] Refactor foo for clarity"),
    blocked=False,
)

all_pass &= expect(
    "bd close with small file shrinking (under 50-line floor) → allow",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb", files=("src/foo.ts",)),
        dmr_files_for={"Core-djb": ["src/foo.ts"]},
        parent_sha="parent123",
        file_at_sha={
            ("parent123", "src/foo.ts"): "// small\n" * 30,  # 30 lines, below floor
        },
        file_at_head={"src/foo.ts": "// tiny\n" * 5},
        commit_msgs="fix(Core-djb): minor\n"),
    blocked=False,
)

all_pass &= expect(
    "bd close with file shrinking only 30% → allow (under threshold)",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb", files=("src/foo.ts",)),
        dmr_files_for={"Core-djb": ["src/foo.ts"]},
        parent_sha="parent123",
        file_at_sha={
            ("parent123", "src/foo.ts"): "// line\n" * 100,
        },
        file_at_head={"src/foo.ts": "// line\n" * 70},
        commit_msgs="fix(Core-djb): minor cleanup\n"),
    blocked=False,
)

# ───────────────── Allow path — full positive case ─────────────────
all_pass &= expect(
    "bd close with real code commit + clean stash + fresh PASS → allow",
    run("bd close Core-9fhd", **good_close_fixtures("Core-9fhd")),
    blocked=False,
)

# ───────────────── Edge cases preserved from v1 ─────────────────
all_pass &= expect(
    "bd close --reason=done <id> → ID extracted correctly",
    run("bd close --reason=done Core-eyjm"),
    blocked=True, reason_contains="Core-eyjm",
)

all_pass &= expect(
    "bd update <id> --status=closed → BLOCK without commit",
    run("bd update Core-e4hj --status=closed"),
    blocked=True, reason_contains="Core-e4hj",
)

all_pass &= expect(
    "bd update <id> --claim → allow (not a close)",
    run("bd update Core-avqg --claim"),
    blocked=False,
)

# ───────────────── Gate 2: git commit ─────────────────
all_pass &= expect(
    "git commit with staged changes → allow",
    run('git commit -m "fix: whatever"', has_staged=True),
    blocked=False,
)

all_pass &= expect(
    "git commit empty diff → BLOCK",
    run('git commit -m "no-op"', has_staged=False),
    blocked=True, reason_contains="no staged",
)

all_pass &= expect(
    "git commit --allow-empty → allow (no probe)",
    run('git commit --allow-empty -m "marker"', has_staged=False),
    blocked=False,
)

all_pass &= expect(
    "git commit --allow-empty-message empty diff → BLOCK",
    run('git commit --allow-empty-message -F msg.txt', has_staged=False),
    blocked=True, reason_contains="no staged",
)

# ───────────────── Non-matching commands ─────────────────
all_pass &= expect(
    "ls -la → allow",
    run("ls -la"),
    blocked=False,
)

all_pass &= expect(
    "git status → allow",
    run("git status"),
    blocked=False,
)

# CHAINED git commit && bd close — close gate fires first, finds no commit
all_pass &= expect(
    "CHAINED git commit && bd close → BLOCK (known v1 limitation)",
    run('git commit -m "fix Core-9fhd" && bd close Core-9fhd'),
    blocked=True, reason_contains="Core-9fhd",
)

# Non-terminal tool is ignored.
all_pass &= (mod._gate("file_read", {"command": "bd close X"}) is None)
print(f"  [{'PASS' if all_pass else 'FAIL'}] non-terminal tool → allow")

print("\nRESULT:", "ALL PASS" if all_pass else "FAILURES ABOVE")
sys.exit(0 if all_pass else 1)
