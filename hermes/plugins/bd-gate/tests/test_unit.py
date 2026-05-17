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
                 dmr_files_for=None, dr_files_for=None, m_files_for=None,
                 parent_sha=None, file_at_sha=None,
                 file_at_head=None, commit_msgs="", issue_title="",
                 added_lines_for=None, scope_test_for=None):
    """Configure probe stubs for the next case.

    files_for:        dict mapping issue_id -> list[str] of files (Gate 1; ALL filter)
    has_staged:       value returned by the staged-changes probe
    stash_count:      value returned by the stash probe
    head_sha:         value returned by the HEAD probe
    test_result_for:  dict mapping issue_id -> (exists: bool, content: str)
    dmr_files_for:    legacy: dict mapping issue_id -> list[str] used as the
                      response for ANY diff-filter call (DR or M). Convenient
                      for legacy tests that don't distinguish.
    dr_files_for:     dict mapping issue_id -> list[str] for the DR filter
                      (Gate 5a — deleted/renamed test files).
    m_files_for:      dict mapping issue_id -> list[str] for the M filter
                      (Gate 5b/5c — modified files).
    parent_sha:       string returned by _first_commit_parent_for_issue
    file_at_sha:      dict mapping (sha, path) -> file content (str) or None
    file_at_head:     dict mapping path -> current file content (str) for HEAD
    commit_msgs:      string returned by _commit_messages_for_issue
    issue_title:      string returned by _issue_title
    added_lines_for:  dict mapping (parent_sha, path) -> list[str] of newly-
                      added (`+`-prefixed) lines for Gate 5c softened-assertion
                      detection.
    scope_test_for:   dict mapping issue_id -> (cmd, scope_desc) override for
                      _derive_scope_test_command. When set, scope-mode is
                      simulated as if vitest workspace + touched files matched.
                      When the cmd would run, _run_test_command is also stubbed
                      to return (passed_flag, output) per `scope_test_pass`.
    """
    files_for = files_for or {}
    test_result_for = test_result_for or {}
    dmr_files_for = dmr_files_for or {}
    dr_files_for = dr_files_for or {}
    m_files_for = m_files_for or {}
    file_at_sha = file_at_sha or {}
    file_at_head = file_at_head or {}
    added_lines_for = added_lines_for or {}
    scope_test_for = scope_test_for or {}
    probe_calls.clear()

    def fake_commit_files(issue_id, cwd):
        probe_calls.append(("commit_files", issue_id))
        if issue_id not in files_for:
            return (True, [])
        return (True, list(files_for[issue_id]))

    def fake_commit_files_filtered(issue_id, cwd, diff_filter):
        probe_calls.append(("commit_files_filtered", issue_id, diff_filter))
        # Route DR vs M to filter-specific fixtures when provided; otherwise
        # fall back to dmr_files_for (legacy combined fixture).
        if diff_filter == "DR" and issue_id in dr_files_for:
            return (True, list(dr_files_for[issue_id]))
        if diff_filter == "M" and issue_id in m_files_for:
            return (True, list(m_files_for[issue_id]))
        if issue_id in dmr_files_for:
            return (True, list(dmr_files_for[issue_id]))
        return (True, [])

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

    def fake_added_lines(parent_sha, path, cwd):
        probe_calls.append(("added_lines", parent_sha, path))
        return list(added_lines_for.get((parent_sha, path), []))

    def fake_scope_test(issue_id, cwd):
        probe_calls.append(("scope_test", issue_id))
        return scope_test_for.get(issue_id, (None, None))

    def fake_find_test_command(issue_id, cwd):
        # Always None in unit tests — the brain-Run path requires a real
        # prompt.txt and is exercised by the integration test.
        probe_calls.append(("find_test_command", issue_id))
        return None

    def fake_run_test_command(cmd, cwd):
        # When scope_test_for sets a (cmd, scope), the scope_test_pass
        # attribute on the dict says whether the run "passes" (True) or
        # "fails" (False). Default: pass.
        passed = bool(getattr(scope_test_for, "_pass", True))
        probe_calls.append(("run_test", cmd, passed))
        return (passed, "" if passed else "FAILED 1 test")

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
    mod._added_lines_for_file = fake_added_lines
    mod._derive_scope_test_command = fake_scope_test
    mod._find_test_command = fake_find_test_command
    mod._run_test_command = fake_run_test_command

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

# ─── Gate 4: attestation v2 JSON parse (beads_FlowInCash_Core-nty #3) ────
# Reader accepts v2 JSON in addition to legacy `PASS <sha>` text.
all_pass &= expect(
    "bd close with v2 JSON attestation (PASS, fresh sha) → allow",
    run("bd close Core-9fhd",
        files_for={"Core-9fhd": ["src/foo.ts"]},
        stash_count=0, head_sha=HEAD,
        test_result_for={"Core-9fhd": (True,
            '{"schema":"v2","result":"PASS","head_sha":"abcd1234ef",'
            '"head_sha_verified":true,"test_cmd":"npx vitest run",'
            '"scope":"auth","verified_by":"bd-gate","ts":"2026-05-17T00:00:00Z"}')}),
    blocked=False,
)

all_pass &= expect(
    "bd close with v2 JSON attestation (FAIL) → BLOCK",
    run("bd close Core-9fhd",
        files_for={"Core-9fhd": ["src/foo.ts"]},
        stash_count=0, head_sha=HEAD,
        test_result_for={"Core-9fhd": (True,
            '{"schema":"v2","result":"FAIL","head_sha":"abcd1234ef"}')}),
    blocked=True, reason_contains="does not start with `PASS",
)

all_pass &= expect(
    "bd close with v2 JSON attestation (stale sha) → BLOCK",
    run("bd close Core-9fhd",
        files_for={"Core-9fhd": ["src/foo.ts"]},
        stash_count=0, head_sha=HEAD,
        test_result_for={"Core-9fhd": (True,
            '{"schema":"v2","result":"PASS","head_sha":"deadbeef0011"}')}),
    blocked=True, reason_contains="stale test attestation",
)

# ─── AC #4 REPRODUCER (beads_FlowInCash_Core-nty) ────────────────────────
# Scope-derived test command fails → bead does NOT close. This is the
# end-to-end behavioral test the bead's AC #4 demands.
class _ScopeFixture(dict):
    """dict subclass that holds a _pass flag (plain dict rejects attributes)."""
    _pass = True


def _failing_scope():
    d = _ScopeFixture({"Core-rep": ("npx vitest run --project integration",
                                    "integration")})
    d._pass = False
    return d


def _passing_scope():
    d = _ScopeFixture({"Core-rep": ("npx vitest run --project integration",
                                    "integration")})
    d._pass = True
    return d


all_pass &= expect(
    "AC#4: scope-derived test fails (red in affected suite) → BLOCK",
    run("bd close Core-rep",
        files_for={"Core-rep": ["tests/integration/foo.integration.test.ts"]},
        stash_count=0, head_sha=HEAD,
        scope_test_for=_failing_scope()),
    blocked=True, reason_contains="bd-gate re-ran the test command",
)

all_pass &= expect(
    "Scope-derived test passes (green) → allow",
    run("bd close Core-rep",
        files_for={"Core-rep": ["tests/integration/foo.integration.test.ts"]},
        stash_count=0, head_sha=HEAD,
        scope_test_for=_passing_scope()),
    blocked=False,
)

# ───────────────── Gate 5a: deletion/rename of test file → always BLOCK ─
# Tests are the contract. Deletion or rename masks removed coverage.
all_pass &= expect(
    "bd close with deleted test file (DR filter) → BLOCK",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        dr_files_for={"Core-djb": ["src/__tests__/foo.test.ts"]}),
    blocked=True, reason_contains="deleted or renamed existing test files",
)

all_pass &= expect(
    "bd close with renamed test file (DR filter) → BLOCK",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        dr_files_for={"Core-djb": ["pkg/auth/auth_test.go"]}),
    blocked=True, reason_contains="deleted or renamed existing test files",
)

# ───────────────── Gate 5b/5c: modification of test file → conditional ──
# Pure rewrite (no shrink, no soft assertion) is ALLOWED. This is the
# beads_FlowInCash_Core-nty relaxation — legitimate test refactors should
# not be blocked, only test theater should.
all_pass &= expect(
    "bd close with modified test file (no shrink, no softening) → allow",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        m_files_for={"Core-djb": ["packages/auth/src/__tests__/mtls.test.ts"]},
        parent_sha="parent123",
        file_at_sha={
            ("parent123", "packages/auth/src/__tests__/mtls.test.ts"):
                "expect(x).toBeLessThanOrEqual(100);\n" * 20,
        },
        file_at_head={
            "packages/auth/src/__tests__/mtls.test.ts":
                "expect(x).toBeLessThanOrEqual(100);\n" * 22,
        },
        added_lines_for={
            ("parent123", "packages/auth/src/__tests__/mtls.test.ts"):
                ["expect(x).toBeLessThanOrEqual(100);"],
        }),
    blocked=False,
)

all_pass &= expect(
    "bd close with test file shrunk >20% AND ≥10 lines (Gate 5b) → BLOCK",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        m_files_for={"Core-djb": ["src/foo.test.ts"]},
        parent_sha="parent123",
        file_at_sha={("parent123", "src/foo.test.ts"): "// line\n" * 100},
        file_at_head={"src/foo.test.ts": "// line\n" * 50},
        added_lines_for={("parent123", "src/foo.test.ts"): []}),
    blocked=True, reason_contains="test file src/foo.test.ts shrank",
)

all_pass &= expect(
    "bd close with test file shrunk only 10% (under 20% threshold) → allow",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        m_files_for={"Core-djb": ["src/foo.test.ts"]},
        parent_sha="parent123",
        file_at_sha={("parent123", "src/foo.test.ts"): "// line\n" * 100},
        file_at_head={"src/foo.test.ts": "// line\n" * 90},
        added_lines_for={("parent123", "src/foo.test.ts"): []}),
    blocked=False,
)

all_pass &= expect(
    "bd close with test file shrunk 50% BUT <10-line drop (small file) → allow",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        m_files_for={"Core-djb": ["src/tiny.test.ts"]},
        parent_sha="parent123",
        file_at_sha={("parent123", "src/tiny.test.ts"): "// line\n" * 8},
        file_at_head={"src/tiny.test.ts": "// line\n" * 4},
        added_lines_for={("parent123", "src/tiny.test.ts"): []}),
    blocked=False,
)

# Gate 5c: softened-assertion patterns from AGENTS.md "Test Theater".
all_pass &= expect(
    "bd close with toBeDefined() added in test (Gate 5c) → BLOCK",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        m_files_for={"Core-djb": ["src/foo.test.ts"]},
        parent_sha="parent123",
        file_at_sha={("parent123", "src/foo.test.ts"): "test\n" * 20},
        file_at_head={"src/foo.test.ts": "test\n" * 20},
        added_lines_for={
            ("parent123", "src/foo.test.ts"): ["expect(result).toBeDefined();"],
        }),
    blocked=True, reason_contains="softened-assertion pattern",
)

all_pass &= expect(
    "bd close with Number.isFinite() added in test (Gate 5c) → BLOCK",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        m_files_for={"Core-djb": ["src/foo.test.ts"]},
        parent_sha="parent123",
        file_at_sha={("parent123", "src/foo.test.ts"): "test\n" * 20},
        file_at_head={"src/foo.test.ts": "test\n" * 20},
        added_lines_for={
            ("parent123", "src/foo.test.ts"):
                ["expect(Number.isFinite(score)).toBe(true);"],
        }),
    blocked=True, reason_contains="softened-assertion pattern",
)

all_pass &= expect(
    "bd close with toBeGreaterThanOrEqual(0) added (Gate 5c) → BLOCK",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        m_files_for={"Core-djb": ["src/foo.test.ts"]},
        parent_sha="parent123",
        file_at_sha={("parent123", "src/foo.test.ts"): "test\n" * 20},
        file_at_head={"src/foo.test.ts": "test\n" * 20},
        added_lines_for={
            ("parent123", "src/foo.test.ts"):
                ["expect(latency).toBeGreaterThanOrEqual(0);"],
        }),
    blocked=True, reason_contains="softened-assertion pattern",
)

all_pass &= expect(
    "bd close with .skip without bead-ID reference (Gate 5c) → BLOCK",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        m_files_for={"Core-djb": ["src/foo.test.ts"]},
        parent_sha="parent123",
        file_at_sha={("parent123", "src/foo.test.ts"): "test\n" * 20},
        file_at_head={"src/foo.test.ts": "test\n" * 20},
        added_lines_for={
            ("parent123", "src/foo.test.ts"):
                ["it.skip('flaky for some reason', () => {});"],
        }),
    blocked=True, reason_contains="softened-assertion pattern",
)

all_pass &= expect(
    "bd close with .skip + bead-ID reference (legitimate skip) → allow",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        m_files_for={"Core-djb": ["src/foo.test.ts"]},
        parent_sha="parent123",
        file_at_sha={("parent123", "src/foo.test.ts"): "test\n" * 20},
        file_at_head={"src/foo.test.ts": "test\n" * 20},
        added_lines_for={
            ("parent123", "src/foo.test.ts"):
                ["it.skip('NFR retune pending — beads_Core-abc', () => {});"],
        }),
    blocked=False,
)

# Gate 5c expansions added after Murat's review (the P0 bypasses Bob's
# integration test originally used to pass trivially before tightening).
def gate5c_block(label, added_line):
    return expect(
        f"Gate 5c expanded: {label} → BLOCK",
        run("bd close Core-djb",
            **good_close_fixtures("Core-djb"),
            m_files_for={"Core-djb": ["src/foo.test.ts"]},
            parent_sha="parent123",
            file_at_sha={("parent123", "src/foo.test.ts"): "test\n" * 20},
            file_at_head={"src/foo.test.ts": "test\n" * 20},
            added_lines_for={("parent123", "src/foo.test.ts"): [added_line]}),
        blocked=True, reason_contains="softened-assertion pattern",
    )

all_pass &= gate5c_block(
    "expect(true).toBe(true) literal tautology",
    "it('passes', () => expect(true).toBe(true));")
all_pass &= gate5c_block(
    "expect(1).toBe(1) literal tautology",
    "it('passes', () => expect(1).toBe(1));")
all_pass &= gate5c_block(
    "expect('x').toEqual('x') literal-string tautology",
    "it('passes', () => expect('foo').toEqual('foo'));")
all_pass &= gate5c_block(
    "expect(x).toBe(x) identifier tautology",
    "it('passes', () => expect(result).toBe(result));")
all_pass &= gate5c_block(
    "expect.any(Number) loose matcher",
    "expect(score).toEqual(expect.any(Number));")
all_pass &= gate5c_block(
    "it.todo without bead ID",
    "it.todo('build the retune logic');")
all_pass &= gate5c_block(
    "xtest variant without bead ID",
    "xtest('legacy disabled flow', () => expect(x).toBe(1));")

# Negative: a legitimate non-tautology assertion that ALSO matches the
# `expect(x).toBe(...)` shape but with DIFFERENT identifiers should ALLOW.
all_pass &= expect(
    "Gate 5c expanded: expect(actual).toBe(expected) (different ids) → allow",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        m_files_for={"Core-djb": ["src/foo.test.ts"]},
        parent_sha="parent123",
        file_at_sha={("parent123", "src/foo.test.ts"): "test\n" * 20},
        file_at_head={"src/foo.test.ts": "test\n" * 20},
        added_lines_for={
            ("parent123", "src/foo.test.ts"):
                ["expect(actual).toBe(expected);"],
        }),
    blocked=False,
)

# Negative: a literal non-tautology like expect(1).toBe(2) is a real test
# (will fail at runtime) — should NOT be flagged as theater.
all_pass &= expect(
    "Gate 5c expanded: expect(1).toBe(2) (literal non-tautology) → allow",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        m_files_for={"Core-djb": ["src/foo.test.ts"]},
        parent_sha="parent123",
        file_at_sha={("parent123", "src/foo.test.ts"): "test\n" * 20},
        file_at_head={"src/foo.test.ts": "test\n" * 20},
        added_lines_for={
            ("parent123", "src/foo.test.ts"):
                ["expect(1).toBe(2);"],
        }),
    blocked=False,
)

# Negative: it.todo WITH a bead-ID reference (deliberate backlog marker) → allow.
all_pass &= expect(
    "Gate 5c expanded: it.todo + bead ID (legitimate backlog) → allow",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        m_files_for={"Core-djb": ["src/foo.test.ts"]},
        parent_sha="parent123",
        file_at_sha={("parent123", "src/foo.test.ts"): "test\n" * 20},
        file_at_head={"src/foo.test.ts": "test\n" * 20},
        added_lines_for={
            ("parent123", "src/foo.test.ts"):
                ["it.todo('flake retune — tracked in beads_Core-fl4');"],
        }),
    blocked=False,
)

all_pass &= expect(
    "bd close with NO test files in M list → allow (Gate 5 inert)",
    run("bd close Core-djb",
        **good_close_fixtures("Core-djb"),
        m_files_for={"Core-djb": ["src/foo.ts"]}),
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

# ─── Scope mapping unit tests (beads_FlowInCash_Core-nty #3) ─────────────
# These test _projects_for_touched_files in isolation against the AGENTS.md
# Project Stack mapping table.
def expect_scope(label, files, expected):
    got = mod._projects_for_touched_files(files)
    ok = got == expected
    print(f"  [{'PASS' if ok else 'FAIL'}] scope: {label}")
    if not ok:
        print(f"    expected = {expected!r}")
        print(f"    got      = {got!r}")
    return ok

all_pass &= expect_scope(
    "tests/integration/foo.integration.test.ts → integration",
    ["tests/integration/foo.integration.test.ts"], ["integration"],
)
all_pass &= expect_scope(
    "tests/contracts/x.test.ts → contracts",
    ["tests/contracts/x.test.ts"], ["contracts"],
)
all_pass &= expect_scope(
    "tests/scripts/ci.test.ts → ci-scripts",
    ["tests/scripts/ci.test.ts"], ["ci-scripts"],
)
all_pass &= expect_scope(
    "tests/sidecar-skills.test.ts (root) → sidecar-skills",
    ["tests/sidecar-skills.test.ts"], ["sidecar-skills"],
)
all_pass &= expect_scope(
    "packages/auth/src/foo.ts → auth",
    ["packages/auth/src/foo.ts"], ["auth"],
)
all_pass &= expect_scope(
    "union of mixed files → all matching projects, sorted",
    [
        "packages/auth/src/foo.ts",
        "tests/integration/x.integration.test.ts",
        "packages/charts/src/y.ts",
        ".beads/issues.jsonl",   # excluded
        "docs/notes.md",         # no mapping → ignored
    ],
    ["auth", "charts", "integration"],
)
all_pass &= expect_scope(
    "no mappable files → empty list (scope-mode N/A)",
    ["README.md", "docs/x.md"], [],
)

# ─── Attestation v2 write contract (beads_FlowInCash_Core-nty #3) ────────
# Verifies _write_attest_file emits valid v2 JSON with the verified HEAD SHA,
# the test command, and the scope description — not just "no block".
def test_v2_write():
    import tempfile, json as _json
    from pathlib import Path as _RealPath
    with tempfile.TemporaryDirectory() as tmpdir:
        # _write_attest_file uses `mod.Path` (which the harness monkey-patched
        # earlier) — restore real Path for the duration of this test.
        saved_path = mod.Path
        mod.Path = _RealPath
        try:
            mod._write_attest_file(
                "Core-vc1", "f00dbabef00dbabef00dbabef00dbabef00dbabe", tmpdir,
                test_cmd="npx vitest run --project integration",
                scope="integration",
            )
            f = _RealPath(tmpdir) / ".hermes" / "sessions" / "Core-vc1.test-result"
            ok = f.is_file()
            if not ok:
                print("  [FAIL] v2 write: file not created"); return False
            content = f.read_text().strip()
            try:
                data = _json.loads(content)
            except Exception as exc:
                print(f"  [FAIL] v2 write: not JSON ({exc}): {content!r}"); return False
            checks = [
                ("schema == v2", data.get("schema") == "v2"),
                ("result == PASS", data.get("result") == "PASS"),
                ("head_sha matches", data.get("head_sha", "").startswith("f00dbabe")),
                ("head_sha_verified", data.get("head_sha_verified") is True),
                ("test_cmd carried", "vitest run" in data.get("test_cmd", "")),
                ("scope carried", data.get("scope") == "integration"),
                ("verified_by bd-gate", data.get("verified_by") == "bd-gate"),
                ("ts present", isinstance(data.get("ts"), str) and "T" in data["ts"]),
            ]
            for label, ok in checks:
                print(f"  [{'PASS' if ok else 'FAIL'}] v2 write: {label}")
                if not ok:
                    return False
            return True
        finally:
            mod.Path = saved_path

all_pass &= test_v2_write()

# ─── Attestation reader: dual-format (v1 text + v2 JSON) ─────────────────
def test_attest_parser():
    cases = [
        ("v1 PASS line",
         "PASS abcd1234ef0011\n# verified-by-bd-gate", ("PASS", "abcd1234ef0011")),
        ("v1 FAIL line",
         "FAIL deadbeef", ("FAIL", "deadbeef")),
        ("v2 PASS JSON",
         '{"schema":"v2","result":"PASS","head_sha":"abcd1234"}',
         ("PASS", "abcd1234")),
        ("v2 FAIL JSON",
         '{"schema":"v2","result":"FAIL","head_sha":"abcd1234"}',
         ("FAIL", "abcd1234")),
        ("malformed", "garbage line", ("UNKNOWN", None)),
        ("v2 missing schema → falls through to v1",
         '{"result":"PASS","head_sha":"x"}', ("UNKNOWN", None)),
    ]
    ok_all = True
    for label, content, expected in cases:
        got = mod._parse_attestation(content)
        ok = got == expected
        print(f"  [{'PASS' if ok else 'FAIL'}] parser: {label}")
        if not ok:
            print(f"    expected = {expected!r}  got = {got!r}")
        ok_all &= ok
    return ok_all

all_pass &= test_attest_parser()

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
