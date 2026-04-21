"""bd-gate: framework-level enforcement for the local dev-team workflow.

Registers a pre_tool_call hook against the `terminal` tool and returns a
block directive (see hermes_cli/plugins.py:743) when:

  1. `bd close <id>` / `bd update <id> --status=closed` is called but no
     commit on the current branch references <id>, or
  2. `git commit` is called without staged changes (and without
     --allow-empty).

Probes are short subprocess calls with a 5s timeout. On any probe failure
the gate fails OPEN — we'd rather let a legit action through than hang or
falsely block on an infra glitch.
"""

import logging
import re
import subprocess
from typing import Any, Dict, Optional

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


def _commit_mentions(issue_id: str, cwd: Optional[str]) -> bool:
    """True iff any commit reachable from HEAD mentions issue_id."""
    ok, out = _run(
        ["git", "log", "--grep", issue_id, "-n", "1", "--format=%H"],
        cwd=cwd,
    )
    return ok and bool(out)


def _has_staged_changes(cwd: Optional[str]) -> bool:
    """True iff `git diff --cached --stat` has any output."""
    ok, out = _run(["git", "diff", "--cached", "--stat"], cwd=cwd)
    return ok and bool(out)


def _block(message: str) -> Dict[str, str]:
    logger.info("bd-gate: BLOCK — %s", message)
    return {"action": "block", "message": message}


def _gate(tool_name: str, args: Optional[Dict[str, Any]], **kwargs) -> Optional[Dict[str, str]]:
    """pre_tool_call hook. Return a block directive, or None to allow."""
    if tool_name != "terminal" or not isinstance(args, dict):
        return None

    command = args.get("command")
    if not isinstance(command, str) or not command.strip():
        return None

    cwd = args.get("workdir") or None

    # Gate 1: bd close / bd update --status=closed without a commit that
    # references the issue id. Fail-open on probe errors.
    for pattern in (_BD_CLOSE_RE, _BD_UPDATE_CLOSED_RE):
        m = pattern.search(command)
        if m is None:
            continue
        issue_id = m.group(1)
        try:
            if not _commit_mentions(issue_id, cwd):
                return _block(
                    f"Cannot close {issue_id}: no commit on this branch references "
                    f"{issue_id}. Commit the fix first (include '{issue_id}' in the "
                    f"commit message), then close the issue."
                )
        except Exception as exc:
            logger.debug("bd-gate: probe error on close of %s, failing open: %s",
                         issue_id, exc)
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
