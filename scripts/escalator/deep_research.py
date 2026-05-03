"""Step 9b — Deep Research & Rearchitect (work-loop SKILL.md:373-445).

Triggered by chain tier 6 when blocker_type == HARD_PROBLEM. Six phases,
local-only (no Opus). The simplified version we run for the eval:

  Phase 1: Root Cause Archaeology    (git log, package.json scan)
  Phase 2: Deep Web Research         (multiple targeted queries)
  Phase 3+4: Challenge Assumptions + Alternative Architecture
            (single deepseek-r1:32b call)
  Phase 5: Isolated Prototype        (skipped for generic code — heuristic)
  Phase 6: Apply & Verify            (devstral with alternative arch proposal)

If 9b NO_PROGRESS twice in a row: write all accumulated research to bd
issue notes with `needs-deep-research-round-2` tag and return GAVE_UP.
"""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

from . import search
from .chain import (
    ChainOutcome,
    ChainState,
    _maybe_short_circuit,
    _verify,
)
from .models import advisor_invocation, hands_invocation, invoke_pi


@dataclass
class ResearchArtifacts:
    archaeology: str
    web_findings: list[search.SearchResult]
    alternative_proposal: str


# ---------------------------------------------------------------------------
# Phase 1
# ---------------------------------------------------------------------------
def _archaeology(state: ChainState) -> str:
    """Quick git + package.json archaeology. Returns a markdown blob."""
    parts: list[str] = []

    # Last 10 commits touching packages/<area> (hint at when this code last
    # worked + what changed). For the eval the issue title mentions
    # 'auth' — tilt the log toward that.
    area_hint = "packages/auth" if "auth" in state.issue_title.lower() else "."
    try:
        log_proc = subprocess.run(
            ["git", "log", "--oneline", "-10", "--", area_hint],
            cwd=str(state.repo),
            capture_output=True,
            text=True,
            check=False,
            timeout=30,
        )
        if log_proc.stdout:
            parts.append("## Recent commits in affected area")
            parts.append(log_proc.stdout.strip())
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    # package.json devDependency versions — useful when error mentions a
    # library by name.
    pkg_path = state.repo / "package.json"
    if pkg_path.exists():
        try:
            txt = pkg_path.read_text()
            # Extract the devDependencies block crudely.
            m = re.search(r'"devDependencies"\s*:\s*\{([^}]+)\}', txt, re.DOTALL)
            if m:
                parts.append("## devDependencies")
                parts.append(m.group(0))
        except Exception:
            pass

    return "\n\n".join(parts) or "(no archaeology output)"


# ---------------------------------------------------------------------------
# Phase 2
# ---------------------------------------------------------------------------
def _deep_web_research(state: ChainState) -> list[search.SearchResult]:
    """Multiple targeted queries. Aggregates into a single deduplicated list."""
    queries: list[str] = []

    # Pull the last error line as one query.
    output = state.last_test_output[-3000:]
    err_line = ""
    for line in output.splitlines():
        if "Error" in line or "FAIL" in line or "Unexpected" in line:
            err_line = line.strip()[:160]
            break

    if err_line:
        queries.append(f'"{err_line}" github issue')
        queries.append(f'"{err_line}" stackoverflow')

    queries.append(f"{state.issue_title} typescript example")
    queries.append(f"{state.issue_title} site:github.com")

    # Library/version-flavored: scrape any node_modules version mentions.
    err_lower = err_line.lower()
    libs = ["vitest", "esbuild", "vite", "typescript"]
    for lib in libs:
        if lib in err_lower:
            queries.append(f"{lib} {err_line[:80]}")
            break

    # Run each query, dedup by URL.
    seen: set[str] = set()
    aggregated: list[search.SearchResult] = []
    for q in queries[:6]:  # cap at 6 queries to bound time
        results = search.search(q, max_results=3)
        for r in results:
            if r.url not in seen:
                seen.add(r.url)
                aggregated.append(r)
    return aggregated


# ---------------------------------------------------------------------------
# Phases 3 + 4: assumption challenge + alternative architecture
# ---------------------------------------------------------------------------
def _propose_alternative(
    state: ChainState,
    archaeology: str,
    web_findings: list[search.SearchResult],
) -> str:
    """Single deepseek-r1:32b call to challenge assumptions + propose
    alternative architecture. Returns the model's text response."""
    research_block = search.format_results_for_prompt(web_findings)
    approaches_block = (
        "\n".join(f"- {a}" for a in state.approaches_tried) or "(none recorded)"
    )

    prompt = (
        "You are a senior engineer running root-cause + rearchitect for a "
        "stuck story. Multiple model attempts have failed. Your job is to:\n"
        "  1. List every implicit assumption the failed attempts made.\n"
        "  2. Challenge each — under what conditions might it be wrong?\n"
        "  3. Propose 2-3 ALTERNATIVE approaches that SIDESTEP the problem "
        "     (don't try to fix the original approach — go around it).\n"
        "  4. Pick the simplest alternative WITH evidence (from the web "
        "     findings) of working, and describe it as a concrete patch.\n\n"
        f"## Issue\n{state.issue_id} — {state.issue_title}\n\n"
        f"## Description\n{state.issue_desc}\n\n"
        f"## Bound test command\n{state.test_command}\n\n"
        "## Most recent test failure\n"
        f"```\n{state.last_test_output[-2000:]}\n```\n\n"
        f"## Repo archaeology\n{archaeology}\n\n"
        f"## Web research\n{research_block}\n\n"
        f"## Approaches already tried (do NOT repeat)\n{approaches_block}\n\n"
        "Be specific. Name files and functions. Describe the patch in a way "
        "that a 24B model can apply directly."
    )

    call = advisor_invocation(prompt, timeout_sec=600, cwd=state.repo)
    result = invoke_pi(call)
    return result.stdout.strip() or "(no alternative proposal returned)"


# ---------------------------------------------------------------------------
# Phase 6: apply
# ---------------------------------------------------------------------------
def _apply_alternative(
    state: ChainState, proposal: str, max_pi_seconds: int
) -> None:
    """Invoke devstral with the alternative proposal as the nudge."""
    nudge = (
        "Deep Research has produced an ALTERNATIVE architecture proposal. "
        "Apply it directly. Do NOT continue the prior approaches.\n\n"
        "## Proposal\n"
        f"{proposal}\n\n"
        "Apply this proposal to the source files. Run the bound test "
        "command after editing. Confirm green before exiting. Do NOT "
        "modify test files."
    )
    state.approaches_tried.append("deep-research alternative architecture")

    call = hands_invocation(
        nudge,
        session=state.session_path,
        timeout_sec=max_pi_seconds,
        cwd=state.repo,
    )
    invoke_pi(call)


def _stash_artifacts(state: ChainState, art: ResearchArtifacts) -> Path:
    """Persist the deep-research artifacts so the next session continues
    from accumulated knowledge, not from zero. Per work-loop SKILL.md:443."""
    out_dir = state.repo / ".hermes" / "sessions"
    out_dir.mkdir(parents=True, exist_ok=True)
    target = out_dir / f"{state.issue_id}.deep-research.md"
    body = (
        f"# Deep Research artifacts for {state.issue_id}\n\n"
        f"## Title\n{state.issue_title}\n\n"
        f"## Archaeology\n{art.archaeology}\n\n"
        f"## Web findings\n{search.format_results_for_prompt(art.web_findings)}\n\n"
        f"## Alternative proposal\n{art.alternative_proposal}\n"
    )
    target.write_text(body)
    return target


def run_deep_research(
    state: ChainState,
    *,
    per_pi_seconds: int = 1800,
    max_cycles: int = 2,
) -> ChainOutcome:
    """Run Step 9b. Up to `max_cycles` cycles, each: archaeology + research +
    proposal + apply + verify. PASS exits. NO_PROGRESS twice in a row →
    write artifacts to bd notes and return GAVE_UP."""
    cycles_no_progress = 0
    last_artifacts: ResearchArtifacts | None = None
    for cycle in range(1, max_cycles + 1):
        print(f"[escalator/9b] Deep Research cycle {cycle}/{max_cycles}")

        archaeology = _archaeology(state)
        web_findings = _deep_web_research(state)
        proposal = _propose_alternative(state, archaeology, web_findings)
        last_artifacts = ResearchArtifacts(
            archaeology=archaeology,
            web_findings=web_findings,
            alternative_proposal=proposal,
        )

        _apply_alternative(state, proposal, per_pi_seconds)
        outcome = _verify(state, f"9b-cycle{cycle}")
        early = _maybe_short_circuit(outcome, state, f"9b-cycle{cycle}")
        if early is not None:
            return early

        cycles_no_progress += 1
        if cycles_no_progress >= 2:
            break

    # Persist artifacts for the next session.
    if last_artifacts is not None:
        artifact_path = _stash_artifacts(state, last_artifacts)
        print(f"[escalator/9b] artifacts saved to {artifact_path}")
    return ChainOutcome(
        result="GAVE_UP",
        phase_reached="9b-exhausted",
        state=state,
    )
