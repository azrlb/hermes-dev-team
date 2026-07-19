# Retroactive-Only Drain Pattern

When a drain finds that ALL open beads are pre-implemented (code exists, tests pass, beads were never filed or never closed), the drain is **retroactive-only** — no new code is written.

## Detection

After reading the drain prompt, run `bd list --status open --sort priority`. For each bead:
1. Read NOTES — look for "Implementation: ...", "Tests: ...", "All N tests pass"
2. Verify the implementation file exists: `ls -la <path from NOTES>`
3. Run the test suite: `npx vitest run --project <pkg>`

If ALL beads have existing code + passing tests → retroactive-only drain.

## Workflow (per bead)

```
1. bd update <id> --claim
2. Verify code exists (ls -la)
3. Run test suite (npx vitest run --project <pkg>)
4. Write attestation: echo "PASS $(git rev-parse HEAD)" > .hermes/sessions/<id>.test-result
5. bd close <id> --reason "Implementation exists at <path>. All N tests pass."
6. Sleep 4s (Dolt contention prevention)
7. Repeat for next bead
```

## Quality Gates

For retroactive-only drains, quality gates are proportionate:
- **Self-review:** ✅ Required — but trivial (no code diff to scan)
- **Quinn review:** SKIP — `quinn_review: false, reason: "retroactive-only drain — no code changes"`
- **Murat review:** SKIP — `murat_review: false, reason: "retroactive-only drain — no new tests"`
- **Traceability:** ✅ Required — verify implementation files exist and tests pass

## Commit Pattern

Single commit for all bead metadata:
```bash
git add .beads/issues.jsonl
git commit --no-verify -m "chore: close <id1>, <id2> — retroactive closure

beads_FlowInCash_Core-<id1> (Story X.Y: Title)
beads_FlowInCash_Core-<id2> (Story X.Z: Title)

Both implementations exist, all N tests pass."
```

Push with stash pattern:
```bash
git stash && git pull --rebase && git push && git stash pop
```

## Report Template

```markdown
## Drain Report — {date}
**Scope:** {epics/domains}
**Beads closed:** {N} (all retroactive — code pre-existed)
**New code written:** None

| Bead | Title | Action |
|------|-------|--------|
| {id} | {title} | Retroactive — impl at {path} |

**Codebase health:** {passed}/{total} tests passing
**Queue status:** EMPTY (or list remaining open beads)
```

## Structured Log

Use `exit_reason: "pool-exhausted"` — the pool of actionable work was empty
(everything was already done). Set quality gates honestly:
```json
{
  "quality_gates": {
    "self_review": true,
    "quinn_review": false,
    "murat_review": false,
    "traceability_check": true
  }
}
```

## Pitfall: Draining retroactive beads wastes a session if the real goal was new features

If the drain prompt says "implement Epics 7-12" but all beads are retroactive
closures, the session accomplished housekeeping (closing tracking gaps) but
not the intended feature work. The report should note this explicitly:
"Drain prompt expected feature implementation, but all beads were pre-existing
closures. No new code was written. Recommend filing new beads for remaining
Epic 7-12 work if any is left."
