"""Progress detection — STALLED / LOOP / THRASH signals.

Reads Pi's session jsonl (per work-loop SKILL.md:204-207, 260-265). Each
line is a session event. We care about assistant turn toolCalls.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal


ProgressSignal = Literal["NONE", "STALLED", "LOOP", "THRASH"]


@dataclass
class SessionFingerprint:
    bash_commands: list[str] = field(default_factory=list)
    edited_paths: list[str] = field(default_factory=list)
    last_assistant_had_toolcall: bool = True


def fingerprint_session(session_path: Path) -> SessionFingerprint:
    fp = SessionFingerprint()
    if not session_path.exists():
        return fp
    last_assistant_idx: int | None = None
    events: list[dict] = []
    for line in session_path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue

    for i, e in enumerate(events):
        msg = e.get("message", {})
        role = msg.get("role")
        contents = msg.get("content", [])
        if role == "assistant":
            last_assistant_idx = i
            for c in contents:
                if c.get("type") == "toolCall":
                    name = c.get("name", "")
                    args = c.get("arguments", {})
                    if name == "bash":
                        cmd = args.get("command", "")
                        if cmd:
                            fp.bash_commands.append(cmd)
                    elif name == "edit":
                        path = args.get("path", "")
                        if path:
                            fp.edited_paths.append(path)

    # Determine if the LAST assistant turn had any toolCall (the wrapper-
    # loop's text-only-detection signal).
    if last_assistant_idx is not None:
        last_msg = events[last_assistant_idx].get("message", {})
        had_tool = any(
            c.get("type") == "toolCall" for c in last_msg.get("content", [])
        )
        fp.last_assistant_had_toolcall = had_tool

    return fp


def detect_loop(bash_commands: list[str], window: int = 5) -> bool:
    """LOOP: same window of `window` commands appears at least twice in the
    sequence. Hashes commands so trivial whitespace differences don't
    break detection.
    """
    if len(bash_commands) < window * 2:
        return False
    seen: set[str] = set()
    for i in range(len(bash_commands) - window + 1):
        key = hashlib.sha1(
            "|".join(c.strip() for c in bash_commands[i : i + window]).encode()
        ).hexdigest()
        if key in seen:
            return True
        seen.add(key)
    return False


def detect_thrash(edited_paths: list[str], threshold: int = 3) -> str | None:
    """THRASH: ≥`threshold` edits to same path. Returns the thrashing path
    or None. (Caller checks "no commit between first edit" externally —
    this signal is just the count.)
    """
    counts: dict[str, int] = {}
    for p in edited_paths:
        counts[p] = counts.get(p, 0) + 1
    for path, n in counts.items():
        if n >= threshold:
            return path
    return None


def detect_stalled(prior_passed: int, current_passed: int) -> bool:
    """STALLED: test count unchanged across 2 consecutive verifications."""
    return current_passed == prior_passed
