#!/usr/bin/env python3
"""Replace the abbreviated inline Phase 10c in both BMAD Pipeline crons
with a directive to follow the FULL Phase 10c from the dev-team vibe-loop
skill. Catches the gap that let yesterday's batch ship un-reviewed.

Idempotent: if a job has already been updated (the directive's marker
phrase appears in the prompt), it's skipped.
"""
from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

LIVE = Path.home() / ".hermes" / "cron" / "jobs.json"

# Jobs to update — the BMAD Pipeline crons that drive AI coding.
TARGETS = {
    "548f363200b8": "Crispi Family Plan BMAD Pipeline",
    "536e0749002d": "FlowInCash-Core Epic 10 BMAD Pipeline",
}

MARKER = "Follow the FULL Phase 10c procedure defined in"

NEW_PHASE_10C = """Phase 10c (Quinn Adversarial Review — MANDATORY HARD GATE):

Follow the FULL Phase 10c procedure defined in
/media/bob/C/AI_Projects/hermes-dev-team/skills/dev-team/vibe-loop/SKILL.md
under the section "### Phase 10c / quinn-review". DO NOT substitute an
abbreviated 3-category checklist. The full procedure is the gate.

Concretely, you MUST:

1. LOAD /media/bob/C/AI_Projects/hermes-dev-team/skills/dev-team/vibe-loop/references/ai-coder-antipatterns.md
   into the review context. Every reviewer below receives this file as
   part of its brief. This catalog tells reviewers what AI-coder failure
   patterns to grep for (non-timing-safe HMAC compares, builtins-vs-
   library exceptions, fake-passing tests, scope drift, real keys
   committed, etc.) — these are the bugs that pass naive test suites.

2. COLLECT the diff for this session's work AND the full source files
   touched (not just the diff). git diff main...HEAD --name-only, then
   read each file in full.

3. INVOKE the bmad-code-review skill (or run its three layers directly
   if the skill is unavailable):
   - Blind Hunter (diff + full source + anti-patterns — no project ctx)
   - Edge Case Hunter (diff + full source + anti-patterns + project read)
   - Acceptance Auditor (diff + full source + anti-patterns + story specs)

   Each reviewer must perform the COMMIT-CLAIM AUDIT documented in the
   SKILL.md — for every commit in the session's diff, compare the
   commit MESSAGE against the actual changes. Flag overclaim, scope
   drift, and "all tests pass" used as primary evidence.

4. SUBAGENT FAILURE HANDLING (mandatory escalation chain):
   If any review layer fails / times out / returns empty:
     a) Retry with parent model
     b) Retry with deepseek-r1:32b (local, port 8082)
     c) Run inline — orchestrator performs review itself
     d) HALT the pipeline if none of the above produces real findings
   ABSOLUTELY FORBIDDEN: simulating, fabricating, or generating
   placeholder findings. A fake review is worse than no review.

5. TRIAGE findings: Critical/High → P0, Medium → P1, Low → P2. File
   each as a beads issue with the `quinn-review` label.

6. RUN THE FIX LOOP: For each P0/P1 finding, claim → Pi fix → verify
   → land. Loop until all P0/P1 are closed. P2 stays open for future.

7. ANTI-PATTERNS CATALOG MAINTENANCE: If any finding does NOT match an
   existing entry in references/ai-coder-antipatterns.md, APPEND a new
   entry before closing this phase. Shape: name + pattern + why-wrong +
   right pattern + how Quinn checks. Cite the originating commit SHA.
   The catalog grows monotonically with real incidents — without this
   step the same bug recurs every cycle.

8. REPORT before proceeding to Phase 11:
   Quinn Adversarial Review — Complete
   Findings: {total} ({critical} / {high} / {medium} / {low})
   Fixed this session: {fixed}
   Deferred (P2): {deferred}
   New anti-patterns captured: {count}

This phase CANNOT be skipped. If you reach Phase 11 without a real
multi-layer Quinn review and a triage outcome, the pipeline has not
completed — return to this phase or HALT and escalate to Bob via
Telegram with the specific blocker."""


def replace_phase_10c(prompt: str) -> tuple[str, bool]:
    """Replace the Phase 10c section in `prompt`. Returns (new_prompt, changed)."""
    if MARKER in prompt:
        return prompt, False  # already updated

    # Match "Phase 10c" header line up to (not including) the next "Phase N"
    # header. Tolerates parenthesized or trailing text on the header line.
    pattern = re.compile(
        r"Phase\s+10c\s*(?:\([^)]*\))?\s*:?[^\n]*(?:\n(?!Phase\s+\d+[a-z]?\b).*)*",
        re.IGNORECASE,
    )
    m = pattern.search(prompt)
    if not m:
        return prompt, False
    new = prompt[: m.start()] + NEW_PHASE_10C + "\n\n" + prompt[m.end():].lstrip()
    return new, True


def main() -> int:
    data = json.loads(LIVE.read_text())
    changed_jobs: list[str] = []
    skipped_jobs: list[str] = []
    not_found: list[str] = []

    for job in data.get("jobs", []):
        if job["id"] not in TARGETS:
            continue
        prompt = job.get("prompt", "")
        new_prompt, changed = replace_phase_10c(prompt)
        if changed:
            job["prompt"] = new_prompt
            changed_jobs.append(f"{job['id']} ({job['name']})")
        elif MARKER in prompt:
            skipped_jobs.append(f"{job['id']} ({job['name']}) — already updated")
        else:
            not_found.append(f"{job['id']} ({job['name']}) — no Phase 10c block found")

    print("Quinn-strengthen sync plan:")
    print(f"  Changed:    {len(changed_jobs)}")
    for s in changed_jobs:
        print(f"    {s}")
    print(f"  Skipped:    {len(skipped_jobs)}")
    for s in skipped_jobs:
        print(f"    {s}")
    print(f"  Not found:  {len(not_found)}")
    for s in not_found:
        print(f"    {s}")

    if not changed_jobs:
        print("\nNo changes to apply.")
        return 0

    from datetime import datetime, timezone
    data["updated_at"] = datetime.now(timezone.utc).astimezone().isoformat()

    LIVE.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    os.chmod(LIVE, 0o600)
    print(f"\nWrote {LIVE}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
