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
           --allow-empty).
  Gate 3.  `bd close <id>` is called while `git stash list` has entries —
           stashed work is hidden from commits and frequently masks an
           incomplete fix.
  Gate 4.  `bd close <id>` is called without a verified PASS for the test.
           When `.hermes/sessions/<id>.prompt.txt` exists with a `Run:` line
           naming a known test runner (vitest/jest/mocha/npm test/pytest/
           cargo test/go test), bd-gate executes that command itself with a
           5-min timeout and writes the authoritative `.test-result` based
           on the actual exit code. Brain-written PASS attestations are
           overwritten — eval-5 v2 (2026-04-30) showed the brain fabricating
           PASS while the actual file was untouched at the wrong path.
           Fallback (no prompt / unknown runner): legacy file-format check.
  Gate 5.  Any commit referencing <id> MODIFIED, DELETED, or RENAMED a test
           file. Allowed: ADDED test files (legitimate new test work). Test
           paths: `**/*.test.*`, `**/*.spec.*`, `**/__tests__/**`,
           `**/tests/**`, `**/test/**`. Tests are the contract — the model
           must not rewrite them to pass trivially.
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
    r"\bbd\s+close\s+(?:--[^\s=]+(?:[=\s]\S+)?\s+)*([A-Za-z0-9][A-Za-z0-9_-]*)"
)

# bd update <id> ... --status=closed  OR  --status closed
_BD_UPDATE_CLOSED_RE = re.compile(
    r"\bbd\s+update\s+([A-Za-z0-9][A-Za-z0-9_-]*)\b[^|&;]*--status[=\s]+closed\b"
)

_GIT_COMMIT_RE = re.compile(r"\bgit\s+commit\b")
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
_TEST_RERUN_TIMEOUT_SEC = 300  # 5 min — vitest cold start is slow


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


def _write_attest_file(issue_id: str, head_sha: str, cwd: Optional[str]) -> None:
    """Write the authoritative `.test-result` after a bd-gate-verified test pass."""
    try:
        base = Path(cwd) if cwd else Path.cwd()
        path = base / ".hermes" / "sessions" / f"{issue_id}.test-result"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"PASS {head_sha}\n# verified-by-bd-gate\n")
    except Exception as exc:
        logger.debug("bd-gate: failed to write authoritative attestation: %s", exc)


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
    # Authoritative path: when `<id>.prompt.txt` exists with a `Run:` line for
    # a known test runner, bd-gate runs the test ITSELF and overwrites the
    # `.test-result` file with its own verdict. The brain's self-reported PASS
    # is not trusted (eval-5 v2 closed an issue with a fabricated attestation
    # while the actual file was untouched at the wrong path).
    #
    # Fallback path: when no prompt or no recognizable Run: line is found,
    # fall back to the legacy file-format check (preserves backward compat
    # for hand-written attestations and non-eval workflows).
    try:
        head = _head_sha(cwd)
        test_cmd = _find_test_command(issue_id, cwd)
        if test_cmd and head:
            ok, output_tail = _run_test_command(test_cmd, cwd)
            if not ok:
                return _block(
                    f"Cannot close {issue_id}: bd-gate re-ran the test command "
                    f"(`{test_cmd}`) and it failed or timed out. The brain's "
                    f"self-reported PASS is not trusted by bd-gate.\n"
                    f"Last output:\n{output_tail[-800:]}"
                )
            _write_attest_file(issue_id, head, cwd)
        else:
            # Legacy file-format-only check.
            exists, content = _read_test_result(issue_id, cwd)
            if not exists:
                return _block(
                    f"Cannot close {issue_id}: missing test attestation at "
                    f".hermes/sessions/{issue_id}.test-result. Run the project's own "
                    f"test command against the closing commit, then write `PASS <sha>` "
                    f"to that file (sha = current HEAD). bd-gate will not trust an "
                    f"agent's self-reported PASS without verification."
                )
            first = content.split("\n", 1)[0].strip()
            parts = first.split()
            if len(parts) < 2 or parts[0] != "PASS":
                return _block(
                    f"Cannot close {issue_id}: test attestation does not start with "
                    f"`PASS <sha>` (got: {first!r}). The project's own test command "
                    f"must succeed before close."
                )
            attest_sha = parts[1]
            if head and not (attest_sha == head or head.startswith(attest_sha)
                             or attest_sha.startswith(head)):
                return _block(
                    f"Cannot close {issue_id}: stale test attestation. File records "
                    f"PASS for {attest_sha[:12]} but HEAD is {head[:12]}. Re-run the "
                    f"test command against the current HEAD and rewrite the file."
                )
    except Exception as exc:
        logger.debug("bd-gate: Gate 4 (test verification) error on %s, "
                     "failing open: %s", issue_id, exc)

    # Gates 5/6/7 share these probes — compute once.
    try:
        # Re-fetch full file list (Gate 1 already did this but used a different
        # shape). Use a wider filter for 5 (catches deletes + renames).
        ok5, touched_test_paths = _commit_files_for_issue_filtered(
            issue_id, cwd, "DMR"  # Deleted, Modified, Renamed
        )
        commit_msgs = _commit_messages_for_issue(issue_id, cwd)
        title = _issue_title(issue_id, cwd)
        parent_sha = _first_commit_parent_for_issue(issue_id, cwd)

        # Gate 5: test-file immutability (modify/delete/rename — added is OK).
        if ok5:
            test_violations = [p for p in touched_test_paths if _is_test_path(p)]
            if test_violations:
                preview = ", ".join(test_violations[:5]) + (
                    "..." if len(test_violations) > 5 else "")
                return _block(
                    f"Cannot close {issue_id}: commit(s) modified, deleted, or "
                    f"renamed existing test files: {preview}. Tests are the "
                    f"contract — adding new test files is allowed, but rewriting "
                    f"or removing existing ones to make a trivial test pass is "
                    f"not. Restore the original test file(s) and ensure the fix "
                    f"makes the existing tests pass."
                )
    except Exception as exc:
        logger.debug("bd-gate: test-immutability probe error on %s, failing open: %s",
                     issue_id, exc)
        commit_msgs, title, parent_sha = "", "", None

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

    # Close gates: bd close / bd update --status=closed
    for pattern in (_BD_CLOSE_RE, _BD_UPDATE_CLOSED_RE):
        m = pattern.search(command)
        if m is None:
            continue
        issue_id = m.group(1)
        decision = _check_close(issue_id, cwd)
        if decision is not None:
            return decision
        break  # matched one close pattern — don't re-probe with the other

    # Gate 2: git commit with no staged diff (and not --allow-empty).
    if _GIT_COMMIT_RE.search(command) and not _ALLOW_EMPTY_DIFF_RE.search(command):
        try:
            if not _has_staged_changes(cwd):
                return _block(
                    "Cannot commit: no staged changes. Stage real modified files "
                    "with `git add <paths>` first, or pass --allow-empty if an "
                    "empty commit is intentional."
                )
        except Exception as exc:
            logger.debug("bd-gate: staged-probe error, failing open: %s", exc)

    return None


def register(ctx) -> None:
    """Plugin entry point — wires the pre_tool_call gate."""
    ctx.register_hook("pre_tool_call", _gate)
    logger.info("bd-gate: pre_tool_call hook registered")
