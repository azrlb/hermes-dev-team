"""bd-gate: framework-level enforcement for the local dev-team workflow.

NOTE: This is a Hermes pre_tool_call hook on the `terminal` tool — NOT a git
pre-commit hook. `git commit --no-verify` does NOT bypass this gate.

Registers a pre_tool_call hook (see hermes_cli/plugins.py:743) that returns a
block directive when:

  Gate 1.  `bd close <id>` / `bd update <id> --status=closed` is called and
           the union of files across all commits referencing <id> contains
           nothing outside `.beads/`. (An empty close-metadata commit alone
           is not a real fix.)
  Gate 2.  `git commit` is called without staged changes (and without
           --allow-empty).  Skipped when `git add` is also in the same
           command string (the add will stage files before the commit runs).
  Gate 3.  `bd close <id>` is called while `git stash list` has entries —
           stashed work is hidden from commits and frequently masks an
           incomplete fix.
  Gate 4.  `bd close <id>` is called without a verified PASS for the test.
           Command-selection precedence (highest authority first):
             1. SCOPE-DERIVED — when `vitest.workspace.ts` exists at cwd,
                bd-gate inspects the files touched by commits referencing
                <id> and emits `npx vitest run --project <name>...` covering
                every workspace project those files belong to. This is the
                authoritative path: it ignores the brain's `Run:` line so a
                fabricated Run: cannot understate scope (beads_FlowInCash_Core-nty).
             2. BRAIN-DECLARED — `.hermes/sessions/<id>.prompt.txt` `Run:` line
                naming a known test runner (vitest/jest/mocha/npm test/pytest/
                cargo test/go test). Used only when scope-mode is unavailable.
           bd-gate executes the selected command itself with a 10-min timeout
           and writes the authoritative `.test-result` based on the actual
           exit code. Brain-written PASS attestations are overwritten — eval-5
           v2 (2026-04-30) showed the brain fabricating PASS while the actual
           file was untouched at the wrong path. Attestation is emitted as v2
           JSON by default; the reader still accepts the v1 `PASS <sha>` text
           form for legacy hand-written attestations.
           Fallback (no scope, no prompt): legacy v1 text-format read.
  Gate 5.  Tests are the contract. Three sub-rules, weakest action first:
             5a. DELETED or RENAMED test file → BLOCK unconditionally. A
                 legitimate rewrite touches the file in place.
             5b. MODIFIED test file where the post-state has materially fewer
                 lines than the pre-state (>20% shrink AND ≥10-line drop) →
                 BLOCK. Catches silent test removal disguised as a rewrite.
             5c. MODIFIED test file that introduces a softened assertion
                 (`toBeDefined`, `not.toBeNull`, `Number.isFinite`,
                 `toBeTruthy`, `>= 0`, `expect.anything`, or `.skip` without a
                 bead-ID reference) → BLOCK. Maps to AGENTS.md "soft-assertion
                 theater" — the only Test Theater pattern detectable from diff
                 text alone. Identity-function and circular-reference
                 tautologies are structural and require code review.
           Allowed: ADDED test files (legitimate new test work), and modified
           test files that grow or hold-steady AND keep the same hard
           assertion shape. Test paths: `**/*.test.*`, `**/*.spec.*`,
           `**/__tests__/**`, `**/tests/**`, `**/test/**`.
  Gate 6.  An export symbol disappeared from a non-test source file relative
           to the parent of the first commit referencing <id>. Allowed: the
           commit messages or issue title contain `BREAKING:`. Detection:
           `grep '^export'` line-set diff between parent and HEAD.
  Gate 7.  A non-test source file lost more than 50% of its lines, when its
           pre-state had at least 50 lines, and no commit message or issue
           title contains a refactor keyword (`rewrite`, `refactor`,
           `redesign`, `restructure`). Catches the rewrite-from-scratch bias.

Probes are short subprocess calls with a 5s timeout. On any probe failure
the gate fails OPEN — we'd rather let a legit action through than hang or
falsely block on an infra glitch.
"""

import logging
import re
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)

_PROBE_TIMEOUT_SEC = 5

# bd close [--flag[=val] ...] <issue-id>
#   - ID must start with alphanumeric (not '-') to avoid capturing a flag.
#   - Allow `--flag value` or `--flag=value` tokens between `close` and the ID.
_BD_CLOSE_RE = re.compile(
    r"\bbd\s+close\s+(?:--[^=\s]+(?:[=\s]\S+)?\s+)*([A-Za-z0-9][A-Za-z0-9_.-]*)"
)

# bd update <id> ... --status=closed  OR  --status closed
_BD_UPDATE_CLOSED_RE = re.compile(
    r"\bbd\s+update\s+([A-Za-z0-9][A-Za-z0-9_.-]*)\b[^|&;]*--status[=\\s]+closed\b"
)

_GIT_COMMIT_RE = re.compile(r"\bgit\s+commit\b")
# git add in the same command string — staged check is pointless.
_GIT_ADD_RE = re.compile(r"\bgit\s+add\b")
# --allow-empty but NOT --allow-empty-message (which only waives the message).
_ALLOW_EMPTY_DIFF_RE = re.compile(r"--allow-empty(?![-\w])")


def _run(argv, cwd):
    """Run a short git/bd probe. Returns (ok: bool, stdout: str)."""
    try:
        res = subprocess.run(
            argv,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=_PROBE_TIMEOUT_SEC,
        )
        return (res.returncode == 0, (res.stdout or "").strip())
    except Exception as exc:
        logger.debug("bd-gate probe %r failed: %s", argv, exc)
        return (False, "")


def _commit_files_for_issue(issue_id: str, cwd: Optional[str]) -> Tuple[bool, List[str]]:
    """Return (probe_ok, files_touched).

    Files are the union of paths changed by ALL commits reachable from HEAD
    whose message contains issue_id. Tolerates legitimate multi-commit fixes.
    """
    ok, out = _run(
        ["git", "log", "--grep", issue_id, "--name-only", "--format="],
        cwd=cwd,
    )
    if not ok:
        return (False, [])
    files = sorted({line.strip() for line in out.splitlines() if line.strip()})
    return (True, files)


def _has_staged_changes(cwd: Optional[str]) -> bool:
    """True iff `git diff --cached --stat` has any output."""
    ok, out = _run(["git", "diff", "--cached", "--stat"], cwd=cwd)
    return ok and bool(out)


def _stash_count(cwd: Optional[str]) -> int:
    """Number of `git stash` entries. Returns -1 on probe failure (fail-open)."""
    ok, out = _run(["git", "stash", "list"], cwd=cwd)
    if not ok:
        return -1
    return sum(1 for line in out.splitlines() if line.strip())


def _head_sha(cwd: Optional[str]) -> Optional[str]:
    ok, out = _run(["git", "rev-parse", "HEAD"], cwd=cwd)
    return out if ok and out else None


def _read_test_result(issue_id: str, cwd: Optional[str]) -> Tuple[bool, str]:
    """Read `.hermes/sessions/<issue_id>.test-result`. Returns (exists, content)."""
    base = Path(cwd) if cwd else Path.cwd()
    path = base / ".hermes" / "sessions" / f"{issue_id}.test-result"
    try:
        if path.is_file():
            return (True, path.read_text().strip())
        return (False, "")
    except Exception as exc:
        logger.debug("bd-gate: test-result probe %s failed: %s", path, exc)
        return (False, "")


def _parse_attestation(content: str) -> Tuple[str, Optional[str]]:
    """Parse an attestation file (v1 text or v2 JSON) into (result, head_sha).

    v2 JSON:  {"schema":"v2","result":"PASS","head_sha":"...", ...}
    v1 text:  PASS <sha>\\n# verified-by-bd-gate\\n  (legacy hand-written)

    Returns ("PASS"|"FAIL"|"UNKNOWN", sha-or-None). Malformed input yields
    ("UNKNOWN", None) so the caller emits the same "doesn't start with PASS"
    block message as before — no new error surface for users.
    """
    first_line = (content or "").split("\n", 1)[0].strip()
    if first_line.startswith("{"):
        try:
            import json as _json
            data = _json.loads(first_line)
            if isinstance(data, dict) and data.get("schema") == "v2":
                result = str(data.get("result", "")).upper()
                sha = data.get("head_sha")
                sha = str(sha) if sha else None
                if result in ("PASS", "FAIL"):
                    return (result, sha)
        except Exception:
            pass  # fall through to v1 parse
    parts = first_line.split()
    if len(parts) >= 2 and parts[0] in ("PASS", "FAIL"):
        return (parts[0], parts[1])
    return ("UNKNOWN", None)


# ─── Gate 4 re-run: bd-gate executes the test itself ──────────────────────────
# Allowlist of test-runner command shapes. The Run: line in the brain's
# prompt file is consulted, but bd-gate refuses to execute anything that
# doesn't match a known runner — the prompt is brain-written and untrusted.
_TEST_RUNNER_PATTERNS = (
    re.compile(r"^(?:npx\s+|pnpm\s+|yarn\s+|bun\s+)?vitest\b", re.IGNORECASE),
    re.compile(r"^(?:npx\s+|pnpm\s+|yarn\s+|bun\s+)?jest\b", re.IGNORECASE),
    re.compile(r"^(?:npx\s+|pnpm\s+|yarn\s+|bun\s+)?mocha\b", re.IGNORECASE),
    re.compile(r"^(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?test\b", re.IGNORECASE),
    re.compile(r"^go\s+test\b", re.IGNORECASE),
    re.compile(r"^(?:python3?\s+-m\s+)?pytest\b", re.IGNORECASE),
    re.compile(r"^cargo\s+test\b", re.IGNORECASE),
)

_RUN_LINE_RE = re.compile(r"^\s*Run:\s*(.+?)\s*$", re.IGNORECASE)
# 10 min — scope-mode can fan out across multiple --project flags, and
# integration tests in those projects often require Postgres (cold start
# is slow). The brain's single-file `Run:` line rarely needs more than 5
# min, but the worst-case ceiling has to clear scope fan-out.
_TEST_RERUN_TIMEOUT_SEC = 600


def _find_test_command(issue_id: str, cwd: Optional[str]) -> Optional[str]:
    """Locate the test command for this issue from `.hermes/sessions/<id>.prompt.txt`.

    The brain writes this file (Step 7 of work-loop) with a `Run:` line that
    declares the test command for Pi. bd-gate parses it, validates against
    the test-runner allowlist, and returns the command string. Returns None
    if no prompt file, no Run: line, or the command isn't a recognized runner.
    """
    base = Path(cwd) if cwd else Path.cwd()
    path = base / ".hermes" / "sessions" / f"{issue_id}.prompt.txt"
    try:
        if not path.is_file():
            return None
        content = path.read_text()
    except Exception as exc:
        logger.debug("bd-gate: prompt.txt read error on %s: %s", issue_id, exc)
        return None
    for raw_line in content.splitlines():
        m = _RUN_LINE_RE.match(raw_line)
        if not m:
            continue
        cmd = m.group(1).strip()
        if not cmd:
            continue
        for pat in _TEST_RUNNER_PATTERNS:
            if pat.match(cmd):
                return cmd
        logger.debug("bd-gate: Run: command for %s not in allowlist: %r",
                     issue_id, cmd)
        return None
    return None


def _run_test_command(cmd: str, cwd: Optional[str]) -> Tuple[bool, str]:
    """Execute the test command directly. Returns (passed, output_tail).
    Timeout, non-zero exit, and exec errors all return (False, reason)."""
    try:
        result = subprocess.run(
            cmd,
            shell=True,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=_TEST_RERUN_TIMEOUT_SEC,
        )
        combined = (result.stdout or "") + (result.stderr or "")
        return (result.returncode == 0, combined[-1500:])
    except subprocess.TimeoutExpired:
        return (False, f"<TIMEOUT after {_TEST_RERUN_TIMEOUT_SEC}s>")
    except Exception as exc:
        return (False, f"<EXCEPTION: {exc}>")


def _write_attest_file(
    issue_id: str,
    head_sha: str,
    cwd: Optional[str],
    *,
    test_cmd: Optional[str] = None,
    scope: Optional[str] = None,
) -> None:
    """Write the authoritative `.test-result` after a bd-gate-verified test pass.

    Emits attestation v2 (JSON, one line). v2 is the only format bd-gate writes;
    the reader still accepts the legacy v1 `PASS <sha>` text form for hand-
    written attestations from older workflows. AC #3 of beads_FlowInCash_Core-nty
    requires HEAD SHA to be the verified post-commit sha (caller passes the
    output of `git rev-parse HEAD`).
    """
    try:
        import json as _json
        import datetime as _dt
        base = Path(cwd) if cwd else Path.cwd()
        path = base / ".hermes" / "sessions" / f"{issue_id}.test-result"
        path.parent.mkdir(parents=True, exist_ok=True)
        record = {
            "schema": "v2",
            "result": "PASS",
            "head_sha": head_sha,
            "head_sha_verified": True,
            "test_cmd": test_cmd or "",
            "scope": scope or "",
            "verified_by": "bd-gate",
            "ts": _dt.datetime.utcnow().isoformat(timespec="seconds") + "Z",
        }
        path.write_text(_json.dumps(record) + "\n")
    except Exception as exc:
        logger.debug("bd-gate: failed to write authoritative attestation: %s", exc)


# ─── Scope-derived test command (beads_FlowInCash_Core-nty fix #3) ────────────
#
# When a repo is a vitest workspace (vitest.workspace.ts at cwd), bd-gate derives
# the test command from the bead's touched files rather than trusting the brain's
# `Run:` line. Mapping mirrors FlowInCash-Core/AGENTS.md "Project Stack" table.
# The mapping is intentionally inline (not parsed from vitest.workspace.ts):
# the AGENTS.md table IS the algorithm, and parsing the TS config would introduce
# a fragile dependency on third-party workspace syntax.
_PACKAGE_FILE_RE = re.compile(r"^packages/([^/]+)/")
_ROOT_TEST_FILE_RE = re.compile(r"^tests/([^/]+)\.test\.[a-zA-Z0-9]+$")


def _vitest_workspace_present(cwd: Optional[str]) -> bool:
    try:
        base = Path(cwd) if cwd else Path.cwd()
        for candidate in ("vitest.workspace.ts", "vitest.workspace.js",
                          "vitest.workspace.mjs", "vitest.workspace.json"):
            if (base / candidate).is_file():
                return True
        return False
    except Exception as exc:
        # Probe failure (e.g. permission denied, unusual path layer) → assume
        # not a vitest workspace and fall back to brain's Run: line. Failing
        # open on detection keeps the legacy path reachable.
        logger.debug("bd-gate: vitest-workspace probe error in %r: %s", cwd, exc)
        return False


def _projects_for_touched_files(files: List[str]) -> List[str]:
    """Map touched paths to vitest --project names.

    Rules (in order — first match wins per file):
      tests/integration/*    → integration
      tests/contracts/*      → contracts
      tests/scripts/*        → ci-scripts
      tests/<name>.test.ts   → <name>            (root-level file)
      packages/<name>/...    → <name>
    Anything else: ignored (no project mapping; doesn't gate the close).
    """
    projects: set = set()
    for raw in files:
        p = raw.strip()
        if not p or p.startswith(".beads/"):
            continue
        if p.startswith("tests/integration/"):
            projects.add("integration")
            continue
        if p.startswith("tests/contracts/"):
            projects.add("contracts")
            continue
        if p.startswith("tests/scripts/"):
            projects.add("ci-scripts")
            continue
        m = _ROOT_TEST_FILE_RE.match(p)
        if m:
            projects.add(m.group(1))
            continue
        m = _PACKAGE_FILE_RE.match(p)
        if m:
            projects.add(m.group(1))
            continue
    return sorted(projects)


def _derive_scope_test_command(
    issue_id: str, cwd: Optional[str]
) -> Tuple[Optional[str], Optional[str]]:
    """Return (cmd, scope_description) or (None, None) if scope-mode N/A.

    Scope-mode is only active when:
      (a) `vitest.workspace.ts` (or .js/.mjs/.json) is present at cwd, AND
      (b) at least one touched file maps to a known vitest project.

    Probe errors return (None, None) so Gate 4 falls through to the brain's
    Run: line rather than failing the entire gate open.
    """
    try:
        if not _vitest_workspace_present(cwd):
            return (None, None)
        ok, files = _commit_files_for_issue(issue_id, cwd)
        if not ok or not files:
            return (None, None)
        projects = _projects_for_touched_files(files)
        if not projects:
            return (None, None)
        project_flags = " ".join(f"--project {p}" for p in projects)
        cmd = f"npx vitest run {project_flags}"
        scope = ",".join(projects)
        return (cmd, scope)
    except Exception as exc:
        logger.debug("bd-gate: scope-derive error on %s: %s", issue_id, exc)
        return (None, None)


# ─── Test-file detection (Gate 5) ─────────────────────────────────────────────
# Match common test-file conventions across JS/TS/Python/Go/Rust ecosystems.
_TEST_PATH_RE = re.compile(
    r"(?:^|/)("
    r"__tests__/"
    r"|tests?/"
    r"|.+\.test\.[a-zA-Z0-9]+$"
    r"|.+\.spec\.[a-zA-Z0-9]+$"
    r"|.+_test\.[a-zA-Z0-9]+$"
    r")"
)


def _is_test_path(path: str) -> bool:
    return bool(_TEST_PATH_RE.search(path))


# ─── Gate 5b/5c: rewrite-vs-deletion heuristic (beads_FlowInCash_Core-nty #4) ─
# AGENTS.md "Test Theater" names three patterns. Only soft-assertion theater
# is detectable from raw diff text — identity-function and circular-reference
# tautologies require structural analysis and stay an explicit known gap.
_SOFTENED_ASSERTION_PATTERNS = (
    # `expect(x).toBeDefined()` / .not.toBeDefined()
    re.compile(r"\.toBeDefined\s*\(", re.IGNORECASE),
    # `expect(x).not.toBeNull()`
    re.compile(r"\.not\s*\.\s*toBeNull\s*\(", re.IGNORECASE),
    # `Number.isFinite(x)` inside an expect(...)
    re.compile(r"Number\.isFinite\s*\(", re.IGNORECASE),
    # `expect(x).toBeTruthy()` / .toBeFalsy()
    re.compile(r"\.toBeTruthy\s*\(", re.IGNORECASE),
    re.compile(r"\.toBeFalsy\s*\(", re.IGNORECASE),
    # `expect.anything()` and `expect.any(Type)` — loose matchers
    re.compile(r"expect\.anything\s*\(", re.IGNORECASE),
    re.compile(r"expect\.any\s*\(", re.IGNORECASE),
    # `expect(x).toBeGreaterThanOrEqual(0)` — open-ended floor, no NFR ceiling
    re.compile(r"\.toBeGreaterThanOrEqual\s*\(\s*0\s*\)"),
    re.compile(r"\.toBeLessThanOrEqual\s*\(\s*(?:Infinity|Number\.MAX_(?:SAFE_INTEGER|VALUE))\s*\)"),
    # Literal tautology: `expect(true).toBe(true)`, `expect(1).toBe(1)`,
    # `expect('x').toEqual('x')` — same literal on both sides. Trivially passes.
    re.compile(
        r"expect\s*\(\s*(true|false|null|undefined|\d+|'[^']*'|\"[^\"]*\")\s*\)"
        r"\s*\.(?:toBe|toEqual|toStrictEqual)\s*\(\s*\1\s*\)"
    ),
    # Identifier tautology: `expect(x).toBe(x)` — same name both sides.
    re.compile(
        r"expect\s*\(\s*(\w+)\s*\)\s*\.(?:toBe|toEqual|toStrictEqual)\s*\(\s*\1\s*\)"
    ),
)
# .skip / .skipIf / .todo / xit / xtest / xdescribe without a bead-ID reference
# on the same line. The bead-ID regex matches FlowInCash-Core's
# `beads_*-<3+ chars>` shape and the simpler `Core-<n>` form some old tools use.
# `.todo` counts as theater because the test reports as passing/pending without
# running anything.
_SKIP_RE = re.compile(
    r"\b(?:it|test|describe)\.(?:skip(?:If)?|todo)\s*\("
    r"|\bx(?:it|test|describe)\s*\("
)
_BEAD_REF_RE = re.compile(r"\b(?:beads?_[A-Za-z0-9_]+|Core)-[A-Za-z0-9]{3,}\b")


def _has_softened_assertion(added_lines: List[str]) -> Optional[str]:
    """Return the matching pattern's source text if any added line introduces
    a softened-assertion shape. Otherwise None."""
    for line in added_lines:
        # Strip leading '+' that callers may pass through.
        text = line.lstrip("+")
        for pat in _SOFTENED_ASSERTION_PATTERNS:
            m = pat.search(text)
            if m:
                return m.group(0)
        # .skip-without-bead-ref
        if _SKIP_RE.search(text) and not _BEAD_REF_RE.search(text):
            return ".skip without bead-ID reference"
    return None


def _added_lines_for_file(
    parent_sha: str, path: str, cwd: Optional[str]
) -> List[str]:
    """Lines that appear in HEAD's version of `path` but not in `parent_sha`'s.
    Best-effort: uses `git diff` and falls back to empty list on probe failure.
    """
    ok, out = _run(
        ["git", "diff", "--no-color", "-U0", parent_sha, "HEAD", "--", path],
        cwd=cwd,
    )
    if not ok:
        return []
    added: List[str] = []
    for raw in out.splitlines():
        if raw.startswith("+++"):
            continue
        if raw.startswith("+"):
            added.append(raw[1:])
    return added


# Refactor keywords (Gate 6 BREAKING + Gate 7 size override)
_REFACTOR_KEYWORDS = ("rewrite", "refactor", "redesign", "restructure")
_BREAKING_MARKER_RE = re.compile(r"\bBREAKING:", re.IGNORECASE)


def _commit_files_for_issue_filtered(
    issue_id: str, cwd: Optional[str], diff_filter: str
) -> Tuple[bool, List[str]]:
    """Like _commit_files_for_issue but with a --diff-filter (e.g. 'M', 'DM',
    'DMR'). Includes --find-renames so renames don't slip past as add+delete.
    """
    ok, out = _run(
        [
            "git", "log", "--grep", issue_id,
            f"--diff-filter={diff_filter}",
            "--find-renames",
            "--name-only", "--format=",
        ],
        cwd=cwd,
    )
    if not ok:
        return (False, [])
    files = sorted({line.strip() for line in out.splitlines() if line.strip()})
    return (True, files)


def _first_commit_parent_for_issue(issue_id: str, cwd: Optional[str]) -> Optional[str]:
    """SHA of the parent of the OLDEST commit referencing issue_id. This is
    the 'before' state for export-preservation and code-reduction checks.
    """
    ok, out = _run(
        ["git", "log", "--grep", issue_id, "--reverse", "--format=%H"],
        cwd=cwd,
    )
    if not ok or not out:
        return None
    first_sha = out.splitlines()[0].strip()
    ok2, parent = _run(["git", "rev-parse", f"{first_sha}^"], cwd=cwd)
    return parent if ok2 and parent else None


def _commit_messages_for_issue(issue_id: str, cwd: Optional[str]) -> str:
    """Concatenated commit messages for all commits referencing issue_id."""
    ok, out = _run(
        ["git", "log", "--grep", issue_id, "--format=%B%n---"],
        cwd=cwd,
    )
    return out if ok else ""


def _file_at_sha(sha: str, path: str, cwd: Optional[str]) -> Optional[str]:
    """Return the contents of `path` at `sha`, or None if the file did not
    exist at that commit (or probe failed)."""
    ok, out = _run(["git", "show", f"{sha}:{path}"], cwd=cwd)
    return out if ok else None


# Identifier-based export extraction. We extract the EXPORTED NAME, not the
# whole line, so signature changes on an existing export don't register as
# "export removed." Covers TS/JS conventions; re-exports and `export *` are
# intentionally skipped (too noisy to compare reliably).
_EXPORT_DECL_RE = re.compile(
    r"^\s*export\s+(?:default\s+)?(?:async\s+)?(?:abstract\s+)?"
    r"(?:function|class|const|let|var|interface|type|enum)\s+(\w+)"
)
_EXPORT_DEFAULT_RE = re.compile(r"^\s*export\s+default\b(?!\s+(?:function|class|const|let|var|interface|type|enum)\s+\w+)")
_EXPORT_NAMED_RE = re.compile(r"^\s*export\s*\{\s*([^}]+)\s*\}")


def _exports_in(content: str) -> set:
    """Set of exported identifier names found in `content`. Robust to
    signature/body changes: we extract names like `bar`, `Foo`, `X` rather
    than full lines."""
    names = set()
    for raw_line in content.splitlines():
        line = raw_line.split("//", 1)[0]  # strip line comments
        m = _EXPORT_DECL_RE.match(line)
        if m:
            names.add(m.group(1))
            continue
        if _EXPORT_DEFAULT_RE.match(line):
            names.add("default")
            continue
        m = _EXPORT_NAMED_RE.match(line)
        if m:
            for token in m.group(1).split(","):
                token = token.strip()
                if not token:
                    continue
                # `name as alias` → exported name is the alias
                if " as " in token:
                    parts = token.split(" as ")
                    name = parts[-1].strip()
                else:
                    name = token
                # strip trailing semicolon/whitespace
                name = name.rstrip(";").strip()
                if name:
                    names.add(name)
    return names


def _line_count(content: str) -> int:
    return content.count("\n") + (1 if content and not content.endswith("\n") else 0)


def _refactor_override_active(commit_msgs: str, issue_title: str) -> bool:
    """True iff any refactor keyword appears in the commit messages or the
    issue title (case-insensitive). Override for Gate 7's size limit."""
    haystack = (commit_msgs + "\n" + (issue_title or "")).lower()
    return any(kw in haystack for kw in _REFACTOR_KEYWORDS)


def _breaking_override_active(commit_msgs: str, issue_title: str) -> bool:
    """True iff any commit message or issue title contains a BREAKING: marker.
    Override for Gate 6's export-removal check."""
    return bool(
        _BREAKING_MARKER_RE.search(commit_msgs)
        or _BREAKING_MARKER_RE.search(issue_title or "")
    )


def _issue_title(issue_id: str, cwd: Optional[str]) -> str:
    """Best-effort: read the issue title via `bd show`. Empty on failure."""
    ok, out = _run(["bd", "show", issue_id, "--json"], cwd=cwd)
    if not ok or not out:
        return ""
    try:
        import json as _json
        data = _json.loads(out)
        if isinstance(data, list):
            data = data[0] if data else {}
        return str(data.get("title", ""))
    except Exception:
        return ""


def _block(message: str) -> Dict[str, str]:
    logger.info("bd-gate: BLOCK — %s", message)
    return {"action": "block", "message": message}


def _check_close(issue_id: str, cwd: Optional[str]) -> Optional[Dict[str, str]]:
    """Run all close-time gates. Return a block directive, or None to allow.

    Each probe fails open on infra error.
    """
    # Gate 1: substance check — at least one file outside .beads/
    try:
        ok, files = _commit_files_for_issue(issue_id, cwd)
        if ok:
            non_beads = [f for f in files if not f.startswith(".beads/")]
            if not files:
                return _block(
                    f"Cannot close {issue_id}: no commit on this branch references "
                    f"{issue_id}. Commit the fix first (include '{issue_id}' in the "
                    f"commit message), then close the issue."
                )
            if not non_beads:
                preview = ", ".join(files[:5]) + ("..." if len(files) > 5 else "")
                return _block(
                    f"Cannot close {issue_id}: commit(s) referencing it only touch "
                    f".beads/ files ({preview}). The fix must change real code "
                    f"outside .beads/. Stage and commit the actual code changes."
                )
    except Exception as exc:
        logger.debug("bd-gate: substance probe error on %s, failing open: %s",
                     issue_id, exc)

    # Gate 3: stash entries hide work from commits.
    try:
        n = _stash_count(cwd)
        if n > 0:
            plural = "ies" if n > 1 else "y"
            return _block(
                f"Cannot close {issue_id}: found {n} stash entr{plural} "
                f"(`git stash list`). Stashed work is hidden from commits. "
                f"If the stash holds the real fix, `git stash pop` and commit it. "
                f"If unrelated, `git stash drop` it before closing."
            )
    except Exception as exc:
        logger.debug("bd-gate: stash probe error on %s, failing open: %s",
                     issue_id, exc)

    # Gate 4: bd-gate-verified test attestation.
    #
    # Command-selection precedence (highest authority first):
    #   1. SCOPE-DERIVED — vitest workspace + touched files → `npx vitest run
    #      --project ...`. Authoritative. Ignores brain's `Run:` line entirely
    #      so a fabricated/understated Run: cannot smuggle a close past the
    #      gate (the failure mode that opened beads_FlowInCash_Core-nty).
    #   2. BRAIN-DECLARED — `<id>.prompt.txt` `Run:` line, validated against
    #      the test-runner allowlist. Used only when scope-mode is unavailable.
    # In both cases bd-gate runs the test ITSELF and overwrites `.test-result`
    # with its own v2 JSON verdict. Brain's self-reported PASS is not trusted.
    #
    # Fallback (no scope, no prompt): legacy v1/v2 file-format check, retained
    # for hand-written attestations and non-vitest workflows.
    try:
        head = _head_sha(cwd)
        scope_cmd, scope_desc = _derive_scope_test_command(issue_id, cwd)
        if scope_cmd:
            test_cmd, scope = scope_cmd, scope_desc
        else:
            test_cmd, scope = _find_test_command(issue_id, cwd), "brain-Run"
        if test_cmd and head:
            ok, output_tail = _run_test_command(test_cmd, cwd)
            if not ok:
                return _block(
                    f"Cannot close {issue_id}: bd-gate re-ran the test command "
                    f"(`{test_cmd}`) and it failed or timed out (scope={scope}). "
                    f"The brain's self-reported PASS is not trusted by bd-gate.\n"
                    f"Last output:\n{output_tail[-800:]}"
                )
            _write_attest_file(issue_id, head, cwd,
                               test_cmd=test_cmd, scope=scope)
        else:
            # Legacy file-format-only check. Accepts v1 text OR v2 JSON.
            exists, content = _read_test_result(issue_id, cwd)
            if not exists:
                return _block(
                    f"Cannot close {issue_id}: missing test attestation at "
                    f".hermes/sessions/{issue_id}.test-result. Run the project's own "
                    f"test command against the closing commit, then write `PASS <sha>` "
                    f"to that file (sha = current HEAD). bd-gate will not trust an "
                    f"agent's self-reported PASS without verification."
                )
            result_str, attest_sha = _parse_attestation(content)
            if result_str != "PASS":
                return _block(
                    f"Cannot close {issue_id}: test attestation does not start with "
                    f"`PASS <sha>` (got: {content.splitlines()[0][:120]!r}). The "
                    f"project's own test command must succeed before close."
                )
            if head and attest_sha and not (
                attest_sha == head or head.startswith(attest_sha)
                or attest_sha.startswith(head)
            ):
                return _block(
                    f"Cannot close {issue_id}: stale test attestation. File records "
                    f"PASS for {attest_sha[:12]} but HEAD is {head[:12]}. Re-run the "
                    f"test command against the current HEAD and rewrite the file."
                )
    except Exception as exc:
        logger.debug("bd-gate: Gate 4 (test verification) error on %s, "
                     "failing open: %s", issue_id, exc)

    # Gates 5/6/7 share these probes — compute once. parent_sha/title/commit_msgs
    # are pre-set so an exception inside the Gate 5 block can't leave them unbound
    # for Gates 6/7 below.
    commit_msgs, title, parent_sha = "", "", None
    try:
        commit_msgs = _commit_messages_for_issue(issue_id, cwd)
        title = _issue_title(issue_id, cwd)
        parent_sha = _first_commit_parent_for_issue(issue_id, cwd)

        # Gate 5a: deletion/rename of a test file → unconditional block.
        ok_dr, dr_paths = _commit_files_for_issue_filtered(issue_id, cwd, "DR")
        if ok_dr:
            dr_test = [p for p in dr_paths if _is_test_path(p)]
            if dr_test:
                preview = ", ".join(dr_test[:5]) + (
                    "..." if len(dr_test) > 5 else "")
                return _block(
                    f"Cannot close {issue_id}: commit(s) deleted or renamed "
                    f"existing test files: {preview}. A legitimate test rewrite "
                    f"touches the file in place; deletion/rename masks removed "
                    f"coverage. Restore the file at its original path."
                )

        # Gates 5b/5c: modification of a test file — allow only if neither
        # materially shrunk NOR softened.
        ok_m, m_paths = _commit_files_for_issue_filtered(issue_id, cwd, "M")
        if ok_m and parent_sha:
            m_test_paths = [p for p in m_paths if _is_test_path(p)]
            for path in m_test_paths:
                before = _file_at_sha(parent_sha, path, cwd)
                if before is None:
                    continue
                try:
                    after = (Path(cwd) if cwd else Path.cwd()).joinpath(
                        path).read_text()
                except Exception:
                    after = ""
                pre_lines = _line_count(before)
                post_lines = _line_count(after)
                # 5b: material shrinkage (>20% AND ≥10-line drop).
                if pre_lines > 0 and (pre_lines - post_lines) >= 10:
                    shrink = (pre_lines - post_lines) / pre_lines
                    if shrink > 0.20:
                        return _block(
                            f"Cannot close {issue_id}: test file {path} shrank "
                            f"from {pre_lines} → {post_lines} lines "
                            f"({int(shrink * 100)}% removed). A legitimate "
                            f"rewrite preserves or grows coverage; silent test "
                            f"removal disguised as a rewrite is the failure "
                            f"mode in beads_FlowInCash_Core-nty."
                        )
                # 5c: softened-assertion theater on any newly-added line.
                added = _added_lines_for_file(parent_sha, path, cwd)
                softened = _has_softened_assertion(added)
                if softened:
                    return _block(
                        f"Cannot close {issue_id}: test file {path} introduces "
                        f"a softened-assertion pattern (`{softened}`). Per "
                        f"FlowInCash-Core AGENTS.md 'Test Theater', NFR gates "
                        f"must compare against the actual threshold "
                        f"(`toBeLessThanOrEqual(NFR_THRESHOLD)`), not "
                        f"open-ended predicates like toBeDefined, "
                        f"Number.isFinite, or `>= 0`. If the NFR is genuinely "
                        f"unmet, mark the test `.skip` with the open retune "
                        f"bead ID on the same line."
                    )
    except Exception as exc:
        logger.debug("bd-gate: test-mod probe error on %s, failing open: %s",
                     issue_id, exc)

    # Gate 6: export preservation. Compare exports in each non-test source file
    # at parent_sha vs current HEAD. Block if any export disappeared without a
    # BREAKING: marker.
    if parent_sha:
        try:
            ok_all, all_files = _commit_files_for_issue_filtered(
                issue_id, cwd, "DMR"
            )
            if ok_all:
                non_test_files = [
                    p for p in all_files
                    if not p.startswith(".beads/") and not _is_test_path(p)
                ]
                breaking_ok = _breaking_override_active(commit_msgs, title)
                for path in non_test_files:
                    before = _file_at_sha(parent_sha, path, cwd)
                    if before is None:
                        # File didn't exist at parent — nothing to preserve.
                        continue
                    try:
                        after = (Path(cwd) if cwd else Path.cwd()).joinpath(path).read_text()
                    except Exception:
                        # File deleted at HEAD — every export "removed."
                        after = ""
                    before_exports = _exports_in(before)
                    after_exports = _exports_in(after)
                    removed = before_exports - after_exports
                    if removed and not breaking_ok:
                        sample = next(iter(sorted(removed)))
                        return _block(
                            f"Cannot close {issue_id}: {len(removed)} export(s) "
                            f"removed from {path} (e.g. `{sample}`) without a "
                            f"`BREAKING:` marker. Other code may import these "
                            f"symbols. Either restore the exports, or add "
                            f"`BREAKING:` to a commit message / issue title to "
                            f"acknowledge the API change."
                        )
        except Exception as exc:
            logger.debug("bd-gate: export-preservation probe error on %s, "
                         "failing open: %s", issue_id, exc)

    # Gate 7: code-reduction sanity. For non-test source files >= 50 lines
    # before the change, refuse if they shrank by more than 50% with no
    # refactor keyword in the commit messages or issue title.
    if parent_sha:
        try:
            ok_all, all_files = _commit_files_for_issue_filtered(
                issue_id, cwd, "DMR"
            )
            if ok_all:
                non_test_files = [
                    p for p in all_files
                    if not p.startswith(".beads/") and not _is_test_path(p)
                ]
                refactor_ok = _refactor_override_active(commit_msgs, title)
                for path in non_test_files:
                    before = _file_at_sha(parent_sha, path, cwd)
                    if before is None:
                        continue
                    pre_lines = _line_count(before)
                    if pre_lines < 50:
                        continue
                    try:
                        after = (Path(cwd) if cwd else Path.cwd()).joinpath(path).read_text()
                        post_lines = _line_count(after)
                    except Exception:
                        post_lines = 0
                    if pre_lines == 0:
                        continue
                    reduction = (pre_lines - post_lines) / pre_lines
                    if reduction > 0.5 and not refactor_ok:
                        return _block(
                            f"Cannot close {issue_id}: {path} shrank from "
                            f"{pre_lines} → {post_lines} lines "
                            f"({int(reduction * 100)}% reduction). Surgical "
                            f"fixes shouldn't delete most of a file. If this is "
                            f"intentional, mark the issue title or a commit "
                            f"message with one of: rewrite, refactor, redesign, "
                            f"restructure."
                        )
        except Exception as exc:
            logger.debug("bd-gate: size-reduction probe error on %s, "
                         "failing open: %s", issue_id, exc)

    return None


def _gate(tool_name: str, args: Optional[Dict[str, Any]], **kwargs) -> Optional[Dict[str, str]]:
    """pre_tool_call hook. Return a block directive, or None to allow."""
    if tool_name != "terminal" or not isinstance(args, dict):
        return None

    command = args.get("command")
    if not isinstance(command, str) or not command.strip():
        return None

    cwd = args.get("workdir") or None

    # Strip quoted strings from command to avoid matching 'bd close' inside
    # string arguments, heredocs, or echo statements (the "will" bug).
    # This is critical: bd-gate must only match bd close in actual shell commands,
    # not in quoted text that happens to contain those words.
    def _strip_quotes(cmd):
        """Remove quoted sections from command before pattern matching."""
        result = []
        i = 0
        while i < len(cmd):
            if cmd[i] in ('"', "'"):
                # Skip to matching close quote
                quote = cmd[i]
                i += 1
                while i < len(cmd) and cmd[i] != quote:
                    if cmd[i] == '\\':
                        i += 1  # skip escaped char
                    i += 1
                i += 1  # skip close quote
            elif cmd[i:i+2] == '$(':
                # Skip $() command substitution
                depth = 1
                i += 2
                while i < len(cmd) and depth > 0:
                    if cmd[i] == '(':
                        depth += 1
                    elif cmd[i] == ')':
                        depth -= 1
                    i += 1
            else:
                result.append(cmd[i])
                i += 1
        return ''.join(result)

    clean_cmd = _strip_quotes(command)

    # Close gates: bd close / bd update --status=closed
    for pattern in (_BD_CLOSE_RE, _BD_UPDATE_CLOSED_RE):
        m = pattern.search(clean_cmd)
        if m is None:
            continue
        issue_id = m.group(1)
        decision = _check_close(issue_id, cwd)
        if decision is not None:
            return decision
        break  # matched one close pattern — don't re-probe with the other

    # Gate 2: DISABLED — was blocking legitimate commits due to cwd mismatch
    # when `cd /path && git commit` is used without explicit workdir param.
    # See: https://github.com/azrlb/FlowInCash-Core/issues/bd-gate-cwd
    # if _GIT_COMMIT_RE.search(command) and not _GIT_ADD_RE.search(command) and not _ALLOW_EMPTY_DIFF_RE.search(command):
    #     try:
    #         if not _has_staged_changes(cwd):
    #             return _block(
    #                 "Cannot commit: no staged changes. Stage real modified files "
    #                 "with `git add <paths>` first, or pass --allow-empty if an "
    #                 "empty commit is intentional."
    #             )
    #     except Exception as exc:
    #         logger.debug("bd-gate: staged-probe error, failing open: %s", exc)

    return None


def register(ctx) -> None:
    """Plugin entry point — wires the pre_tool_call gate."""
    ctx.register_hook("pre_tool_call", _gate)
    logger.info("bd-gate: pre_tool_call hook registered")
