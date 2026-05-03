"""Local Ollama endpoints + pi --print invocation helpers."""

from __future__ import annotations

import os
import shlex
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

# Provider / model constants (matches ~/.pi/agent/models.json).
HANDS_PROVIDER = "ollama"
HANDS_MODEL = "devstral-small-2:24b"
ADVISOR_PROVIDER = "ollama-quinn"
ADVISOR_MODEL = "deepseek-r1:32b"

# Pi agent definitions (loadable via --append-system-prompt).
TDD_CODER_AGENT = Path.home() / ".pi" / "agents" / "tdd-coder.md"
FAILURE_CLASSIFIER_AGENT = Path.home() / ".pi" / "agents" / "failure-classifier.md"
QUINN_VALIDATOR_AGENT = Path.home() / ".pi" / "agents" / "quinn-validator.md"


@dataclass
class PiInvocation:
    prompt: str
    session: Path | None = None
    provider: str = HANDS_PROVIDER
    model: str = HANDS_MODEL
    append_system_prompt: Path | None = None
    no_tools: bool = False
    timeout_sec: int = 1800
    cwd: str | Path | None = None


@dataclass
class PiResult:
    exit_code: int
    stdout: str
    stderr: str
    timed_out: bool


def invoke_pi(call: PiInvocation) -> PiResult:
    """Run pi --print with the given invocation. Returns combined output.

    Honors call.timeout_sec via the bash `timeout` command (matches what
    pi-build-loop.sh does — the model has no internal time awareness).
    """
    args: list[str] = ["timeout", str(call.timeout_sec), "pi", "--print"]
    args += ["--provider", call.provider, "--model", call.model]
    if call.session is not None:
        args += ["--session", str(call.session)]
    if call.append_system_prompt is not None:
        args += ["--append-system-prompt", str(call.append_system_prompt)]
    if call.no_tools:
        args += ["--no-tools"]
    args.append(call.prompt)

    try:
        proc = subprocess.run(
            args,
            cwd=str(call.cwd) if call.cwd else None,
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError as exc:
        return PiResult(exit_code=127, stdout="", stderr=str(exc), timed_out=False)

    timed_out = proc.returncode == 124
    return PiResult(
        exit_code=proc.returncode,
        stdout=proc.stdout or "",
        stderr=proc.stderr or "",
        timed_out=timed_out,
    )


def hands_invocation(prompt: str, session: Path, *, timeout_sec: int = 1800,
                      cwd: str | Path | None = None) -> PiInvocation:
    """Build an invocation of the hands tier (devstral on coder-hands).

    Loads the tdd-coder agent prompt by default — preserves the same
    behavioral constraints pi-build-loop.sh uses.
    """
    return PiInvocation(
        prompt=prompt,
        session=session,
        provider=HANDS_PROVIDER,
        model=HANDS_MODEL,
        append_system_prompt=TDD_CODER_AGENT if TDD_CODER_AGENT.exists() else None,
        no_tools=False,
        timeout_sec=timeout_sec,
        cwd=cwd,
    )


def advisor_invocation(prompt: str, *, timeout_sec: int = 600,
                        cwd: str | Path | None = None) -> PiInvocation:
    """Build an invocation of the advisor tier (deepseek-r1:32b).

    Read-only by default (no_tools=True) — Advisor diagnoses, doesn't edit.
    """
    return PiInvocation(
        prompt=prompt,
        session=None,  # Advisor is stateless; no session continuity
        provider=ADVISOR_PROVIDER,
        model=ADVISOR_MODEL,
        append_system_prompt=None,
        no_tools=True,
        timeout_sec=timeout_sec,
        cwd=cwd,
    )


def classifier_invocation(prompt: str, *, timeout_sec: int = 300,
                           cwd: str | Path | None = None) -> PiInvocation:
    """Build a failure-classifier invocation. Uses the existing Pi agent at
    ~/.pi/agents/failure-classifier.md (do NOT re-implement the prompt)."""
    if not FAILURE_CLASSIFIER_AGENT.exists():
        print(
            f"WARN: failure-classifier agent missing at {FAILURE_CLASSIFIER_AGENT}",
            file=sys.stderr,
        )
    return PiInvocation(
        prompt=prompt,
        session=None,
        provider=ADVISOR_PROVIDER,
        model=ADVISOR_MODEL,
        append_system_prompt=FAILURE_CLASSIFIER_AGENT
        if FAILURE_CLASSIFIER_AGENT.exists()
        else None,
        no_tools=True,
        timeout_sec=timeout_sec,
        cwd=cwd,
    )
