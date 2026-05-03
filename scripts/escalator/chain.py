"""Six-tier escalation chain — Step 8 of the work-loop SKILL.md, local-only.

Tier sequence:
  1. Different approach (devstral)
  2. Second different approach (devstral)
  3. Web search the error
  4. Devstral with research context
  5. Advisor (deepseek-r1:32b) — diagnosis + concrete patch
  6. failure-classifier — categorize blocker

Each tier ends with verify_and_resume(). PASS short-circuits the chain.
PARTIAL returns an early outcome with a nudge. NO_PROGRESS advances.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal

from . import classifier, search
from .models import (
    advisor_invocation,
    hands_invocation,
    invoke_pi,
)
from .verify import VerifyOutcome, verify_and_resume

ChainResult = Literal["PASS", "PARTIAL", "NO_PROGRESS", "GAVE_UP"]


@dataclass
class ChainState:
    repo: Path
    session_path: Path
    test_command: str
    issue_id: str
    issue_title: str
    issue_desc: str
    baseline_passed: int

    # Mutable state across tiers
    approaches_tried: list[str] = field(default_factory=list)
    research_results: list[search.SearchResult] = field(default_factory=list)
    last_test_output: str = ""
    last_passed: int = 0
    last_failed: int = 0
    head_sha: str | None = None
    classification: classifier.Classification | None = None


@dataclass
class ChainOutcome:
    result: ChainResult
    phase_reached: str
    state: ChainState
    next_nudge: str | None = None
    blocker: classifier.Classification | None = None


def _record_outcome(state: ChainState, outcome: VerifyOutcome) -> None:
    state.last_test_output = outcome.raw_output
    state.last_passed = outcome.test_count_passed
    state.last_failed = outcome.test_count_failed
    state.head_sha = outcome.head_sha


def _verify(state: ChainState, tier_label: str) -> VerifyOutcome:
    """Run Verify & Resume for the current state. Stamps a per-tier log
    file so forensics can reconstruct what happened."""
    log_path = state.repo / ".hermes" / "sessions" / (
        f"{state.issue_id}.escalator-{tier_label}.log"
    )
    outcome = verify_and_resume(
        state.repo,
        state.test_command,
        baseline_passed=state.baseline_passed,
        log_path=log_path,
    )
    _record_outcome(state, outcome)
    print(
        f"[escalator/{tier_label}] Verify & Resume: {outcome.result} "
        f"(passed={outcome.test_count_passed}, failed={outcome.test_count_failed})"
    )
    return outcome


def _maybe_short_circuit(
    outcome: VerifyOutcome, state: ChainState, tier_label: str
) -> ChainOutcome | None:
    """Return early ChainOutcome if PASS or PARTIAL, else None to continue."""
    if outcome.result == "PASS":
        return ChainOutcome(
            result="PASS",
            phase_reached=tier_label,
            state=state,
        )
    if outcome.result == "PARTIAL":
        nudge = (
            "The escalation step made partial progress. Remaining failures "
            "in the most recent test run:\n"
            f"---\n{outcome.raw_output[-1500:]}\n---\n"
            "Continue from this state. DO NOT modify test files."
        )
        return ChainOutcome(
            result="PARTIAL",
            phase_reached=tier_label,
            state=state,
            next_nudge=nudge,
        )
    return None


def _approaches_avoid_block(state: ChainState) -> str:
    if not state.approaches_tried:
        return "(no prior approaches recorded)"
    return "\n".join(f"- {a}" for a in state.approaches_tried)


# ---------------------------------------------------------------------------
# Tier 1: different approach
# ---------------------------------------------------------------------------
def tier_1_different_approach(state: ChainState, max_pi_seconds: int) -> ChainOutcome | None:
    label = "tier1"
    print(f"[escalator/{label}] Different approach (devstral)")
    nudge = (
        "Your prior approach did not converge. Try a DIFFERENT angle.\n\n"
        "Approaches already attempted (do NOT repeat these):\n"
        f"{_approaches_avoid_block(state)}\n\n"
        "If the test failure is a syntax/parse error in a file you edited, "
        "open the file FULLY (not via tail/head), find the exact line "
        "reported by the error, and fix it precisely. If the failure is "
        "logic, revert your last edits and try a structurally different "
        "implementation.\n\n"
        "When you finish editing, re-run the test command and confirm "
        "green before exiting."
    )
    state.approaches_tried.append("different-approach (devstral)")

    call = hands_invocation(
        nudge,
        session=state.session_path,
        timeout_sec=max_pi_seconds,
        cwd=state.repo,
    )
    result = invoke_pi(call)
    print(f"[escalator/{label}] Pi exit: {result.exit_code}")

    outcome = _verify(state, label)
    return _maybe_short_circuit(outcome, state, label)


# ---------------------------------------------------------------------------
# Tier 2: second different approach
# ---------------------------------------------------------------------------
def tier_2_second_approach(state: ChainState, max_pi_seconds: int) -> ChainOutcome | None:
    label = "tier2"
    print(f"[escalator/{label}] Second different approach (devstral)")
    nudge = (
        "First retry did not converge. Step back and reconsider the problem "
        "from scratch.\n\n"
        "Approaches already attempted (DO NOT repeat):\n"
        f"{_approaches_avoid_block(state)}\n\n"
        "Specifically: are you fighting the test runner, the type system, "
        "or the actual code logic? Identify the LAYER of the failure and "
        "address THAT layer. If you've been editing one file repeatedly, "
        "it may be the wrong file — check what other files exist with "
        "similar names or that import the failing symbol."
    )
    state.approaches_tried.append("second-approach (devstral)")

    call = hands_invocation(
        nudge,
        session=state.session_path,
        timeout_sec=max_pi_seconds,
        cwd=state.repo,
    )
    invoke_pi(call)

    outcome = _verify(state, label)
    return _maybe_short_circuit(outcome, state, label)


# ---------------------------------------------------------------------------
# Tier 3: web search
# ---------------------------------------------------------------------------
def tier_3_web_search(state: ChainState) -> None:
    """Search and store results in state. No verify here — search alone
    doesn't change code, so the next tier picks up the results.
    """
    label = "tier3"
    # Build query from the most recent failure signal we have.
    output = state.last_test_output[-3000:]
    # Pull the first error-shaped line we can find for a focused query.
    query_seed = ""
    for line in output.splitlines():
        if "Error" in line or "FAIL" in line or "Unexpected" in line:
            query_seed = line.strip()[:160]
            break
    if not query_seed:
        query_seed = state.issue_title

    query = f'{query_seed} {state.issue_title}'.strip()
    print(f"[escalator/{label}] Web search: {query[:120]}")
    results = search.search(query, max_results=5)
    state.research_results = results
    print(f"[escalator/{label}] {len(results)} results found")


# ---------------------------------------------------------------------------
# Tier 4: devstral with research context
# ---------------------------------------------------------------------------
def tier_4_with_research(state: ChainState, max_pi_seconds: int) -> ChainOutcome | None:
    label = "tier4"
    print(f"[escalator/{label}] Devstral with research context")
    research_block = search.format_results_for_prompt(state.research_results)
    nudge = (
        "Two prior attempts did not converge. Web search was performed for "
        "context. Use this research to choose a different strategy.\n\n"
        "## Research findings\n"
        f"{research_block}\n\n"
        "## Approaches already attempted (DO NOT repeat)\n"
        f"{_approaches_avoid_block(state)}\n\n"
        "Apply ONE specific finding from the research. If a finding "
        "suggests a library/version issue, address that. If it suggests "
        "an alternative API, try that. Do NOT just summarize the research "
        "— pick a concrete action and execute it."
    )
    state.approaches_tried.append("devstral-with-research")

    call = hands_invocation(
        nudge,
        session=state.session_path,
        timeout_sec=max_pi_seconds,
        cwd=state.repo,
    )
    invoke_pi(call)

    outcome = _verify(state, label)
    return _maybe_short_circuit(outcome, state, label)


# ---------------------------------------------------------------------------
# Tier 5: Advisor (deepseek-r1:32b)
# ---------------------------------------------------------------------------
def tier_5_advisor(state: ChainState, max_pi_seconds: int) -> ChainOutcome | None:
    label = "tier5"
    print(f"[escalator/{label}] Advisor (deepseek-r1:32b)")

    session_tail = ""
    if state.session_path.exists():
        session_tail = state.session_path.read_text()[-4000:]

    research_block = search.format_results_for_prompt(state.research_results)

    advisor_prompt = (
        "You are a senior engineer pairing with a junior who is stuck on a "
        "bd issue. Diagnose what they're missing and provide CONCRETE next "
        "steps.\n\n"
        f"ISSUE_ID:    {state.issue_id}\n"
        f"TITLE:       {state.issue_title}\n"
        f"DESCRIPTION: {state.issue_desc}\n\n"
        f"Bound test command: {state.test_command}\n\n"
        "## Most recent test failure\n"
        f"{state.last_test_output[-2000:]}\n\n"
        "## Junior's session tail (most recent events)\n"
        f"{session_tail}\n\n"
        "## Web research already performed\n"
        f"{research_block}\n\n"
        "## Approaches already attempted (do NOT repeat)\n"
        f"{_approaches_avoid_block(state)}\n\n"
        "Be terse and actionable. If the failure is a syntax/parse error, "
        "quote the exact broken line and the fix. If it's wrong file, name "
        "the right file with grep evidence. If it's a missing concept, "
        "explain it in 3 sentences with a concrete code pattern.\n\n"
        "The junior reads your response VERBATIM as their next instruction. "
        "Lead with the action, not the explanation."
    )
    state.approaches_tried.append("advisor (deepseek-r1:32b)")

    advisor_call = advisor_invocation(
        advisor_prompt,
        timeout_sec=600,
        cwd=state.repo,
    )
    advisor_result = invoke_pi(advisor_call)
    advice = advisor_result.stdout.strip() or "(advisor returned no text)"
    print(f"[escalator/{label}] Advisor exit: {advisor_result.exit_code}")

    # Stash advisor verdict for forensics.
    advice_path = state.repo / ".hermes" / "sessions" / (
        f"{state.issue_id}.advisor-verdict.txt"
    )
    advice_path.parent.mkdir(parents=True, exist_ok=True)
    advice_path.write_text(advice)

    # Re-invoke devstral with the advice as enriched nudge.
    pi_nudge = (
        "Senior engineer feedback on your work so far:\n"
        "============================================\n"
        f"{advice}\n"
        "============================================\n\n"
        "Apply these specific points to the source files. Run the bound "
        "test command after editing and confirm green before exiting. Do "
        "NOT modify test files. Do NOT use --allow-empty."
    )

    pi_call = hands_invocation(
        pi_nudge,
        session=state.session_path,
        timeout_sec=max_pi_seconds,
        cwd=state.repo,
    )
    invoke_pi(pi_call)

    outcome = _verify(state, label)
    return _maybe_short_circuit(outcome, state, label)


# ---------------------------------------------------------------------------
# Tier 6: failure-classifier
# ---------------------------------------------------------------------------
def tier_6_classify(state: ChainState) -> ChainOutcome:
    label = "tier6"
    print(f"[escalator/{label}] failure-classifier")
    context = classifier.build_classifier_context(
        issue_id=state.issue_id,
        issue_title=state.issue_title,
        issue_desc=state.issue_desc,
        test_command=state.test_command,
        last_test_output=state.last_test_output,
        approaches_tried=state.approaches_tried,
        session_path=state.session_path,
    )
    classification = classifier.classify(context, cwd=state.repo)
    state.classification = classification
    print(
        f"[escalator/{label}] blocker_type={classification.blocker_type} "
        f"detail={classification.blocker_detail[:120]}"
    )

    # Emit GAVE_UP unless HARD_PROBLEM (caller decides whether to invoke 9b).
    return ChainOutcome(
        result="NO_PROGRESS" if classification.blocker_type == "HARD_PROBLEM"
                              else "GAVE_UP",
        phase_reached=label,
        state=state,
        blocker=classification,
    )


# ---------------------------------------------------------------------------
# Top-level chain runner
# ---------------------------------------------------------------------------
def run_chain(
    state: ChainState,
    *,
    max_wallclock_sec: int = 5400,
    per_pi_seconds: int = 1800,
    start_tier: int = 1,
) -> ChainOutcome:
    """Walk the six-tier chain. Each tier returns ChainOutcome on PASS or
    PARTIAL (early exit), or None to continue.

    max_wallclock_sec is a safety cap on the whole chain. Each individual
    pi invocation is bounded by per_pi_seconds.
    """
    started = time.monotonic()

    # Initial Verify & Resume so we know baseline state.
    initial = _verify(state, "tier0-baseline")
    if initial.result == "PASS":
        return ChainOutcome(
            result="PASS",
            phase_reached="tier0-baseline",
            state=state,
        )
    state.baseline_passed = max(state.baseline_passed, initial.test_count_passed)

    tiers = [
        ("tier1", lambda s: tier_1_different_approach(s, per_pi_seconds)),
        ("tier2", lambda s: tier_2_second_approach(s, per_pi_seconds)),
        ("tier3", lambda s: (tier_3_web_search(s), None)[1]),
        ("tier4", lambda s: tier_4_with_research(s, per_pi_seconds)),
        ("tier5", lambda s: tier_5_advisor(s, per_pi_seconds)),
        ("tier6", lambda s: tier_6_classify(s)),
    ]

    for tier_index, (label, runner) in enumerate(tiers, start=1):
        if tier_index < start_tier:
            continue
        if time.monotonic() - started > max_wallclock_sec:
            print(f"[escalator] wallclock cap hit before {label}")
            return ChainOutcome(
                result="GAVE_UP",
                phase_reached="wallclock-cap",
                state=state,
            )
        out = runner(state)
        if out is not None:
            return out

    # Should be unreachable — tier6 always returns ChainOutcome.
    return ChainOutcome(
        result="GAVE_UP",
        phase_reached="end",
        state=state,
    )
