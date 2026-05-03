"""Failure classification — thin wrapper around the existing Pi agent at
~/.pi/agents/failure-classifier.md.

Per the agent's prompt, it emits ONLY this JSON (no other text):
{
  "blocker_type": "STORY_AMBIGUITY|MISSING_DEPENDENCY|TEST_MISMATCH|HARD_PROBLEM|INFRA",
  "blocker_detail": "...",
  "suggested_action": "...",
  "evidence": ["...", "..."]
}

deepseek-r1:32b often emits <think>...</think> blocks before the JSON
(reasoning model behavior). We strip those and find the first JSON object.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .models import classifier_invocation, invoke_pi


_THINK_BLOCK_RE = re.compile(r"<think>.*?</think>", re.DOTALL)
_JSON_OBJECT_RE = re.compile(r"\{.*?\}", re.DOTALL)


@dataclass
class Classification:
    blocker_type: str
    blocker_detail: str
    suggested_action: str
    evidence: list[str]
    raw_output: str


def _extract_json(text: str) -> dict[str, Any] | None:
    """Strip <think> blocks, then return the first JSON object that
    contains a 'blocker_type' key. Returns None if unparseable."""
    cleaned = _THINK_BLOCK_RE.sub("", text)
    # Try the whole cleaned blob first.
    cleaned = cleaned.strip()
    candidates = []
    if cleaned:
        candidates.append(cleaned)
    candidates.extend(m.group(0) for m in _JSON_OBJECT_RE.finditer(text))

    for cand in candidates:
        try:
            obj = json.loads(cand)
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict) and "blocker_type" in obj:
            return obj
    return None


def classify(context: str, *, cwd: Path | str | None = None,
             timeout_sec: int = 300) -> Classification:
    """Run the failure-classifier Pi agent on the given context."""
    call = classifier_invocation(context, timeout_sec=timeout_sec, cwd=cwd)
    result = invoke_pi(call)
    obj = _extract_json(result.stdout) or {}
    return Classification(
        blocker_type=str(obj.get("blocker_type", "UNKNOWN")),
        blocker_detail=str(obj.get("blocker_detail", "")),
        suggested_action=str(obj.get("suggested_action", "")),
        evidence=[str(e) for e in obj.get("evidence", []) if isinstance(e, str)],
        raw_output=result.stdout,
    )


def build_classifier_context(
    *,
    issue_id: str,
    issue_title: str,
    issue_desc: str,
    test_command: str,
    last_test_output: str,
    approaches_tried: list[str],
    session_path: Path | None,
) -> str:
    """Assemble the prompt body the failure-classifier sees. Keep it
    focused — the agent reads the story file/test file via tools if it
    needs them; we just summarize state.
    """
    session_tail = ""
    if session_path is not None and session_path.exists():
        # Truncate to last ~3000 chars — enough for recent activity, won't
        # blow the agent's context budget.
        session_tail = session_path.read_text()[-3000:]

    approaches_block = "\n".join(f"- {a}" for a in approaches_tried) or "(none recorded)"
    return f"""Story to classify:
ISSUE_ID:    {issue_id}
TITLE:       {issue_title}
DESCRIPTION:
{issue_desc}

Test command bound to this story:
{test_command}

Most recent test run output (tail):
---
{last_test_output[-2000:]}
---

Approaches the implementing model has already tried:
{approaches_block}

Session jsonl tail (most recent events):
---
{session_tail}
---

Classify the blocker per your agent rules. Output ONLY the JSON object."""
