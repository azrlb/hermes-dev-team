"""Verify & Resume invariant — runs after every model invocation in the
escalation chain.

Mirrors work-loop SKILL.md:236-256. The escalation model is a problem
solver, not a story finisher; every invocation MUST be followed by an
independent test re-run, with three branches:

  PASS              -> chain exits, caller proceeds to gate auto-close
  PARTIAL_PROGRESS  -> caller resumes with reduced error set
  NO_PROGRESS       -> caller advances to next tier
"""

from __future__ import annotations

import re
import shlex
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Literal


VerifyResult = Literal["PASS", "PARTIAL", "NO_PROGRESS"]


@dataclass
class VerifyOutcome:
    result: VerifyResult
    test_count_passed: int
    test_count_failed: int
    raw_output: str
    head_sha: str | None
    log_path: Path | None


# Vitest patterns. Examples we need to parse:
#   "Tests  149 passed (149)"
#   "Tests  146 passed (146)"
#   "Test Files  1 failed | 9 passed (10)"
_VITEST_PASS_COUNT_RE = re.compile(r"\bTests\s+(\d+)\s+passed\b", re.IGNORECASE)
_VITEST_FAIL_COUNT_RE = re.compile(r"\bTests\s+(\d+)\s+failed", re.IGNORECASE)
_VITEST_TEST_FILES_FAILED_RE = re.compile(r"\bTest Files\s+(\d+)\s+failed", re.IGNORECASE)

# Generic fallbacks for non-vitest runners.
_GENERIC_PASS_COUNT_RE = re.compile(r"(\d+)\s+(?:tests?|specs?)\s+pass", re.IGNORECASE)


def parse_test_counts(output: str) -> tuple[int, int]:
    """Return (passed, failed). 0/0 if unparseable."""
    pass_m = _VITEST_PASS_COUNT_RE.search(output)
    fail_m = _VITEST_FAIL_COUNT_RE.search(output)
    files_fail_m = _VITEST_TEST_FILES_FAILED_RE.search(output)

    passed = int(pass_m.group(1)) if pass_m else 0
    failed = int(fail_m.group(1)) if fail_m else 0

    # Vitest reports "Tests N passed" but a "Test Files M failed" line
    # indicates a file failed to load (parse error etc). Treat that as a
    # failure even if the per-test count looks clean.
    if files_fail_m and int(files_fail_m.group(1)) > 0 and failed == 0:
        failed = max(failed, 1)

    if passed == 0 and failed == 0:
        # Fall back to generic patterns for non-vitest runners.
        m = _GENERIC_PASS_COUNT_RE.search(output)
        if m:
            passed = int(m.group(1))
    return passed, failed


def get_head_sha(repo: Path | str) -> str | None:
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=str(repo),
            capture_output=True,
            text=True,
            check=False,
        )
        if proc.returncode == 0:
            return proc.stdout.strip()
    except FileNotFoundError:
        pass
    return None


def verify_and_resume(
    repo: Path | str,
    test_command: str,
    baseline_passed: int,
    *,
    log_path: Path | None = None,
    timeout_sec: int = 300,
) -> VerifyOutcome:
    """Run test_command, parse output, return outcome.

    Branches:
      - exit code 0                          -> PASS (regardless of counts;
                                                  the runner declared success)
      - exit code != 0, passed > baseline    -> PARTIAL (progress)
      - exit code != 0, passed <= baseline   -> NO_PROGRESS

    test_command is run as a single shell string (`bash -c`) so callers can
    pass exactly what the eval fixture binds to (e.g. "npx vitest run
    packages/auth"). Output is captured combined (stdout+stderr).
    """
    proc = subprocess.run(
        ["bash", "-c", test_command],
        cwd=str(repo),
        capture_output=True,
        text=True,
        check=False,
        timeout=timeout_sec,
    )
    output = (proc.stdout or "") + (proc.stderr or "")

    if log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text(output)

    passed, failed = parse_test_counts(output)
    head = get_head_sha(repo)

    if proc.returncode == 0:
        result: VerifyResult = "PASS"
    elif passed > baseline_passed:
        result = "PARTIAL"
    else:
        result = "NO_PROGRESS"

    return VerifyOutcome(
        result=result,
        test_count_passed=passed,
        test_count_failed=failed,
        raw_output=output,
        head_sha=head,
        log_path=log_path,
    )
