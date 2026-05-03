#!/usr/bin/env python3
"""escalator — local-only escalation chain entry point.

Invoked by pi-build-loop.sh after Pi exits without close (and the wrapper
re-invoke loop didn't recover). Walks the work-loop SKILL.md Step 8 chain
plus Step 9b Deep Research, all using local Ollama models.

Output: a single JSON object on stdout, with exit code mirroring result:
  PASS         -> exit 0
  PARTIAL      -> exit 1
  NO_PROGRESS  -> exit 2
  GAVE_UP      -> exit 3

See `/home/bob/.claude/plans/lucky-bouncing-star.md` for full design.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path

# Make sibling 'escalator' package importable regardless of CWD.
sys.path.insert(0, str(Path(__file__).parent))

from escalator.chain import ChainOutcome, ChainState, run_chain
from escalator.deep_research import run_deep_research


_EXIT_CODES = {
    "PASS": 0,
    "PARTIAL": 1,
    "NO_PROGRESS": 2,
    "GAVE_UP": 3,
}


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Local-only escalation chain for Pi-built bd stories"
    )
    p.add_argument("--session", required=True, help="Pi's session jsonl path")
    p.add_argument("--issue-id", required=True)
    p.add_argument("--issue-title", required=True)
    p.add_argument("--issue-desc", required=True)
    p.add_argument("--repo", required=True, help="Working directory (clone)")
    p.add_argument("--test-command", required=True, help="bash command for verification")
    p.add_argument("--baseline-test-count", type=int, default=0)
    p.add_argument("--phase", type=int, default=1, help="Start at this tier (1..6)")
    p.add_argument("--max-wallclock", type=int, default=5400)
    p.add_argument("--per-pi-seconds", type=int, default=1800)
    p.add_argument("--skip-deep-research", action="store_true",
                   help="Don't escalate to Step 9b on HARD_PROBLEM")
    return p.parse_args(argv)


def _emit(outcome: ChainOutcome) -> None:
    payload: dict = {
        "result": outcome.result,
        "phase_reached": outcome.phase_reached,
        "head_sha": outcome.state.head_sha,
        "next_nudge": outcome.next_nudge,
        "test_count_passed": outcome.state.last_passed,
        "test_count_failed": outcome.state.last_failed,
        "approaches_tried": outcome.state.approaches_tried,
    }
    if outcome.blocker is not None:
        payload["blocker"] = {
            "type": outcome.blocker.blocker_type,
            "detail": outcome.blocker.blocker_detail,
            "suggested_action": outcome.blocker.suggested_action,
            "evidence": outcome.blocker.evidence,
        }
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")
    sys.stdout.flush()


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)

    state = ChainState(
        repo=Path(args.repo),
        session_path=Path(args.session),
        test_command=args.test_command,
        issue_id=args.issue_id,
        issue_title=args.issue_title,
        issue_desc=args.issue_desc,
        baseline_passed=args.baseline_test_count,
    )

    outcome = run_chain(
        state,
        max_wallclock_sec=args.max_wallclock,
        per_pi_seconds=args.per_pi_seconds,
        start_tier=args.phase,
    )

    # If chain returned NO_PROGRESS via tier6 and blocker is HARD_PROBLEM,
    # walk Step 9b unless explicitly skipped.
    if (outcome.result == "NO_PROGRESS"
        and outcome.blocker is not None
        and outcome.blocker.blocker_type == "HARD_PROBLEM"
        and not args.skip_deep_research):
        outcome = run_deep_research(
            state,
            per_pi_seconds=args.per_pi_seconds,
        )

    _emit(outcome)
    return _EXIT_CODES.get(outcome.result, 3)


if __name__ == "__main__":
    sys.exit(main())
