"""Integration test — drive the gate through Hermes's real plugin manager.

Uses get_pre_tool_call_block_message() (the exact enforcement path
model_tools.py:454-472 calls at tool-dispatch time). A live Hermes session
would take the same code path, so a PASS here means the plugin will fire.
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

# Each probe runs against /tmp/bd-gate-smoketest so the git state is known.
REPO = "/tmp/bd-gate-smoketest"

# Re-create from scratch — earlier runs may have left this in arbitrary state
# (e.g. stash entries, attestation files, the wrong branch).
if os.path.isdir(REPO):
    shutil.rmtree(REPO)
os.makedirs(REPO)
os.chdir(REPO)
subprocess.run(["git", "init", "-q", "-b", "main"], cwd=REPO, check=True)
subprocess.run(["git", "config", "user.email", "test@bd-gate"], cwd=REPO, check=True)
subprocess.run(["git", "config", "user.name", "bd-gate-test"], cwd=REPO, check=True)
Path(REPO, "README.md").write_text("init\n")
subprocess.run(["git", "add", "README.md"], cwd=REPO, check=True)
subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=REPO, check=True)

sys.path.insert(0, str(Path.home() / ".hermes" / "hermes-agent"))

from hermes_cli.plugins import (  # type: ignore
    discover_plugins,
    get_pre_tool_call_block_message,
    get_plugin_manager,
)

discover_plugins()

mgr = get_plugin_manager()
loaded = getattr(mgr, "_loaded", getattr(mgr, "plugins", None))
if isinstance(loaded, dict):
    print("Loaded plugins:", list(loaded.keys()))
elif isinstance(loaded, list):
    print("Loaded plugins:", [getattr(p, "name", p) for p in loaded])
else:
    print("Loaded plugins: (introspecting manager fields)",
          [k for k in vars(mgr) if "plugin" in k.lower() or "hook" in k.lower()])


def case(label, tool, args, *, expect_block: bool, contains: str | None = None):
    msg = get_pre_tool_call_block_message(tool, args)
    blocked = msg is not None
    ok = blocked == expect_block
    if ok and contains is not None:
        ok = contains in (msg or "")
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}")
    if not ok:
        print(f"    expect_block={expect_block} got_msg={msg!r}")
    return ok


def git(*argv):
    return subprocess.run(["git", *argv], cwd=REPO, capture_output=True, text=True)


def head_sha() -> str:
    return git("rev-parse", "HEAD").stdout.strip()


def attest(issue_id: str, status: str, sha: str | None = None):
    """Write `.hermes/sessions/{id}.test-result`."""
    sha = sha if sha is not None else head_sha()
    p = Path(REPO, ".hermes", "sessions")
    p.mkdir(parents=True, exist_ok=True)
    (p / f"{issue_id}.test-result").write_text(f"{status} {sha}\n")


def remove_attest(issue_id: str):
    p = Path(REPO, ".hermes", "sessions", f"{issue_id}.test-result")
    if p.exists():
        p.unlink()


all_ok = True

# ─── Stage 1: bd close with no commit at all ────────────────────────────────
all_ok &= case(
    "bd close Core-9fhd, no matching commit anywhere → BLOCK",
    "terminal", {"command": "bd close Core-9fhd"},
    expect_block=True, contains="no commit",
)
all_ok &= case(
    "bd update Core-9fhd --status=closed (no commit) → BLOCK",
    "terminal", {"command": "bd update Core-9fhd --status=closed"},
    expect_block=True, contains="Core-9fhd",
)
all_ok &= case(
    "bd close --reason=done Core-9fhd (flag before id) → BLOCK",
    "terminal", {"command": "bd close --reason=done Core-9fhd"},
    expect_block=True, contains="Core-9fhd",
)

# ─── Stage 2: substance check — commit touching ONLY .beads/ ────────────────
# Simulate the failed-eval-style gaming: a commit that references the issue
# but only modifies .beads/issues.jsonl.
Path(REPO, ".beads").mkdir(exist_ok=True)
Path(REPO, ".beads", "issues.jsonl").write_text('{"id":"Core-djb","status":"closed"}\n')
git("add", ".beads/issues.jsonl")
git("commit", "-q", "-m", "fix(Core-djb): empty close-metadata only")

all_ok &= case(
    "bd close with commit touching ONLY .beads/ → BLOCK (substance)",
    "terminal", {"command": "bd close Core-djb"},
    expect_block=True, contains="only touch .beads/",
)

# ─── Stage 3: substance — multi-commit (.beads/ + real code) → allow path ───
# Add a second commit that touches a real source file (still references Core-djb).
Path(REPO, "src").mkdir(exist_ok=True)
Path(REPO, "src", "mtls.ts").write_text("// real fix\n")
git("add", "src/mtls.ts")
git("commit", "-q", "-m", "fix(Core-djb): real code change")

# Without attestation file, this still fails — but on Gate 4 (test-result),
# not Gate 1 (substance). Confirm by content of error message.
all_ok &= case(
    "real-code commit but no attestation file → BLOCK (test-result)",
    "terminal", {"command": "bd close Core-djb"},
    expect_block=True, contains="missing test attestation",
)

# Write attestation for current HEAD
attest("Core-djb", "PASS")
all_ok &= case(
    "real-code commit + fresh PASS attestation + clean stash → allow",
    "terminal", {"command": "bd close Core-djb"},
    expect_block=False,
)

# ─── Stage 4: stash-non-empty blocks even with everything else right ────────
# Make a real change, stash it.
Path(REPO, "src", "scratch.ts").write_text("// scratch\n")
git("add", "src/scratch.ts")
git("stash")  # stash the staged change

all_ok &= case(
    "real-code commit + fresh PASS but non-empty stash → BLOCK",
    "terminal", {"command": "bd close Core-djb"},
    expect_block=True, contains="stash entr",
)

# Drop the stash; should re-allow.
git("stash", "drop")
all_ok &= case(
    "stash dropped → close re-allowed",
    "terminal", {"command": "bd close Core-djb"},
    expect_block=False,
)

# ─── Stage 5: test-result lifecycle ─────────────────────────────────────────
# 5a. FAIL attestation — block
attest("Core-djb", "FAIL")
all_ok &= case(
    "attestation says FAIL → BLOCK",
    "terminal", {"command": "bd close Core-djb"},
    expect_block=True, contains="does not start with `PASS",
)

# 5b. Stale sha — block
attest("Core-djb", "PASS", sha="0000deadbeef")
all_ok &= case(
    "attestation has stale sha (mismatched HEAD) → BLOCK",
    "terminal", {"command": "bd close Core-djb"},
    expect_block=True, contains="stale test attestation",
)

# 5c. Restore good attestation
attest("Core-djb", "PASS")
all_ok &= case(
    "fresh PASS attestation restored → allow",
    "terminal", {"command": "bd close Core-djb"},
    expect_block=False,
)

# ─── Stage 5b: Gate 5 — test-file modification blocks ──────────────────────
# Issue Core-tst5: real source change PLUS modifying an existing test file.
# Set up a baseline commit for the test file (so it pre-exists).
Path(REPO, "src", "__tests__").mkdir(exist_ok=True)
Path(REPO, "src", "__tests__", "lib.test.ts").write_text(
    "import { lib } from '../lib';\ndescribe('lib', () => {\n  it('works', () => expect(lib()).toBe(1));\n});\n"
)
Path(REPO, "src", "lib.ts").write_text("export function lib() { return 1; }\n")
git("add", "src/lib.ts", "src/__tests__/lib.test.ts")
git("commit", "-q", "-m", "baseline: lib + test")

# Now Issue Core-tst5: model rewrites the test to soften the assertion
# (replaces `toBe(1)` with `toBeDefined()`). This is the AGENTS.md "soft-
# assertion theater" pattern that Gate 5c catches — beads_FlowInCash_Core-nty
# fix #4.
Path(REPO, "src", "__tests__", "lib.test.ts").write_text(
    "import { lib } from '../lib';\n"
    "describe('lib', () => {\n"
    "  it('returns something', () => expect(lib()).toBeDefined());\n"
    "});\n"
)
Path(REPO, "src", "lib.ts").write_text("export function lib() { return 99; }\n")
git("add", "src/lib.ts", "src/__tests__/lib.test.ts")
git("commit", "-q", "-m",
    "fix(Core-tst5): soften assertion from toBe(1) to toBeDefined()")
attest("Core-tst5", "PASS")

all_ok &= case(
    "Gate 5c: softened-assertion in modified test file → BLOCK",
    "terminal", {"command": "bd close Core-tst5"},
    expect_block=True, contains="softened-assertion pattern",
)

# Also exercise Gate 5a: a deletion of the test file still blocks.
import os as _os
_os.remove(Path(REPO, "src", "__tests__", "lib.test.ts"))
git("add", "-A", "src/__tests__/lib.test.ts")
git("commit", "-q", "-m", "fix(Core-tst5d): drop the test file entirely")
attest("Core-tst5d", "PASS")

# Need a real-code commit referencing Core-tst5d as well so Gate 1 doesn't
# trip first.
Path(REPO, "src", "lib.ts").write_text(
    "export function lib() { return 100; } // Core-tst5d\n")
git("add", "src/lib.ts")
git("commit", "-q", "-m", "fix(Core-tst5d): code change too")
attest("Core-tst5d", "PASS")

all_ok &= case(
    "Gate 5a: test file DELETED → BLOCK",
    "terminal", {"command": "bd close Core-tst5d"},
    expect_block=True, contains="deleted or renamed existing test files",
)

# ─── Stage 5c: Gate 6 — export removal blocks (no BREAKING) ────────────────
# Issue Core-tst6: removes an existing export from a non-test source file.
Path(REPO, "src", "api.ts").write_text(
    "export function alpha() { return 1; }\n"
    "export function beta() { return 2; }\n"
    "export class Client {}\n"
)
git("add", "src/api.ts")
git("commit", "-q", "-m", "baseline: api with three exports")

# Now Core-tst6: model removes `Client` export.
Path(REPO, "src", "api.ts").write_text(
    "export function alpha() { return 1; }\n"
    "export function beta() { return 2; }\n"
)
git("add", "src/api.ts")
git("commit", "-q", "-m", "fix(Core-tst6): clean up api")
attest("Core-tst6", "PASS")

all_ok &= case(
    "Gate 6: export removed without BREAKING → BLOCK",
    "terminal", {"command": "bd close Core-tst6"},
    expect_block=True, contains="export(s) removed",
)

# Amend the message with BREAKING: marker — should now allow.
git("commit", "--amend", "-q", "-m",
    "fix(Core-tst6): BREAKING: remove unused Client class")
# After amend, HEAD changed — re-attest.
attest("Core-tst6", "PASS")
all_ok &= case(
    "Gate 6: export removed WITH BREAKING marker → allow",
    "terminal", {"command": "bd close Core-tst6"},
    expect_block=False,
)

# ─── Stage 5d: Gate 7 — file shrinks > 50% blocks ──────────────────────────
# Issue Core-tst7: source file shrinks dramatically. To isolate Gate 7 from
# Gate 6, the file has ONE export and lots of internal helpers — the export
# stays in both versions, but the file shrinks.
big_internals = "// big internal file\nexport function entry() { return helper50(); }\n"
big_internals += "".join(f"function helper{i}() {{ return {i}; }}\n" for i in range(60))
Path(REPO, "src", "internals.ts").write_text(big_internals)
git("add", "src/internals.ts")
git("commit", "-q", "-m", "baseline: big internals file with 1 export")

# Shrink: keep the one export, drop all helpers.
small_internals = "// trimmed\nexport function entry() { return 0; }\n"
Path(REPO, "src", "internals.ts").write_text(small_internals)
git("add", "src/internals.ts")
git("commit", "-q", "-m", "fix(Core-tst7): consolidate")
attest("Core-tst7", "PASS")

all_ok &= case(
    "Gate 7: file shrinks 95% with no refactor keyword → BLOCK",
    "terminal", {"command": "bd close Core-tst7"},
    expect_block=True, contains="shrank from",
)

# Now amend with 'refactor' in the commit message — Gate 7 should allow.
git("commit", "--amend", "-q", "-m",
    "fix(Core-tst7): refactor — collapse helpers into single body")
attest("Core-tst7", "PASS")
all_ok &= case(
    "Gate 7: file shrinks BUT 'refactor' keyword in commit msg → allow",
    "terminal", {"command": "bd close Core-tst7"},
    expect_block=False,
)

# ─── Stage 6: Gate 2 (git commit empty diff) — preserved from v1 ────────────
# Reset index so nothing is staged.
git("reset")
all_ok &= case(
    "git commit with no staged diff → BLOCK",
    "terminal", {"command": 'git commit -m "no changes"'},
    expect_block=True, contains="no staged",
)

Path(REPO, "another.txt").write_text("x\n")
git("add", "another.txt")
all_ok &= case(
    "git commit with staged diff → allow",
    "terminal", {"command": 'git commit -m "fix: real change"'},
    expect_block=False,
)

git("reset")  # unstage
all_ok &= case(
    "git commit --allow-empty → allow",
    "terminal", {"command": 'git commit --allow-empty -m "marker"'},
    expect_block=False,
)

# ─── Stage 7: misc preserved ────────────────────────────────────────────────
all_ok &= case(
    "file_read tool → allow (not terminal)",
    "file_read", {"path": "/tmp/foo"},
    expect_block=False,
)

all_ok &= case(
    "bd update Core-avqg --claim → allow (not a close)",
    "terminal", {"command": "bd update Core-avqg --claim"},
    expect_block=False,
)

print("\nRESULT:", "ALL PASS" if all_ok else "FAILURES ABOVE")
sys.exit(0 if all_ok else 1)
