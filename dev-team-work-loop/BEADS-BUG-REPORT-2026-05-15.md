# beads-CLI bug report — `bd update --append-notes` silently drops writes when called in rapid succession

**File against:** https://github.com/gastownhall/beads/issues
**Severity:** High — silent data loss; audit trail incomplete
**Filed by:** azrlb (Bob)
**Date observed:** 2026-05-15

---

## TL;DR

`bd update <id> --append-notes "<text>"` reports `✓ Updated issue: ...` and exit code 0, but the note text is silently dropped when the command is invoked in rapid succession (e.g., a shell `for` loop, an `&&` chain, or any sequence faster than ~1 write/second). Labels added in the same call DO persist; only the note is lost. There is no error indication. `updated_at` does not bump on the lost writes either.

Concrete reproduction below: I ran 16 sequential updates; only 3 notes persisted. Ran 13 more on a different chain; only 2 persisted. Standalone single calls work correctly every time.

---

## Environment

| Item | Value |
|------|-------|
| `bd --version` | `bd version 1.0.4 (ce242a879)` |
| Dolt server | running, PID 1238445, port 3308 |
| OS | Linux 6.17.0-23-generic x86_64 (Ubuntu derivative) |
| Filesystem | ext4 on local NVMe |
| Dolt data dir | `.beads/dolt` (project-local, default) |
| Auto-commit policy | default (`off`) |
| Test repo size | 37 issues, 78KB jsonl |

---

## Steps to reproduce

In any beads-initialized project with at least 16 open issues:

```bash
# Create a probe script that updates 16 different issues in a loop, then verifies.
cat > /tmp/bd-probe.sh <<'PROBE'
#!/usr/bin/env bash
set -u
IDS=( $(bd ready --json | python3 -c "import json,sys; print(' '.join(i['id'] for i in json.load(sys.stdin)[:16]))") )
TS=$(date +%s)
echo "Writing probe note to ${#IDS[@]} issues..."
for id in "${IDS[@]}"; do
  bd update "$id" --append-notes "BD-WOBBLE-PROBE-$TS" 2>&1 | grep -E "Updated|Error" >/dev/null
done
echo
echo "Verifying which notes persisted..."
stuck=0
for id in "${IDS[@]}"; do
  notes=$(bd show "$id" --json | python3 -c "import json,sys; d=json.load(sys.stdin); i=d[0] if isinstance(d,list) else d; print(i.get('notes') or '')")
  if echo "$notes" | grep -q "BD-WOBBLE-PROBE-$TS"; then
    stuck=$((stuck + 1))
  else
    echo "  MISSING: $id"
  fi
done
echo
echo "Result: $stuck/${#IDS[@]} probe notes stuck."
echo "Expected: 16/16. Wobble confirmed if less."
PROBE
chmod +x /tmp/bd-probe.sh
/tmp/bd-probe.sh
```

---

## Expected behavior

All 16 issues should have the probe note appended. `updated_at` should bump on all 16.

## Actual behavior

Only a small number (varies — observed 3/16 and 2/13 in two separate runs) of notes persist. The other writes silently fail. `bd update` returns `✓ Updated issue: ...` and exit 0 for every call. `updated_at` does NOT bump on the lost writes — the original timestamp is preserved as if no write occurred.

### Concrete measurements

| Probe run | Pattern | Writes | Notes persisted | Labels persisted |
|-----------|---------|--------|----------------|------------------|
| Run A — `for` loop, 16 sequential `bd update --add-label X --append-notes Y` | for-loop | 16 | **3** | **16** |
| Run B — `&&` chain, 13 sequential `bd update --append-notes Y` | && chain | 13 | **2** | n/a (label not set in chain) |
| Run C — 3 standalone calls, no chaining | one at a time | 3 | **3** | **3** |

Single standalone calls always work. The wobble manifests only when calls happen in rapid succession.

---

## Hypothesis

The Dolt server appears to handle `--add-label` (additive INSERT) durably under load, but `--append-notes` (read-modify-write on an existing TEXT field) loses the read context when invocations overlap. A plausible mechanism:

1. Call N reads current notes value, computes `notes + new_chunk`.
2. Call N+1 starts before call N's write commits.
3. Call N+1 reads the *stale* notes value (without N's chunk), computes its own merge.
4. Both writes commit; the later one overwrites the earlier without conflict detection.
5. Either way, only the most-recent write's contribution survives.

The "✓ Updated" message is printed from the client's success branch (HTTP/SQL OK), not from a post-write verification.

A simple optimistic-concurrency check (compare-and-swap on a version column, or a SELECT-FOR-UPDATE on the notes field inside a single transaction) would surface this loudly instead of silently.

---

## Severity / impact

This affects any automation that uses beads for audit/progress tracking, including:

- AI dev-team work-loops that `--append-notes` per story (audit trail gaps)
- Overnight batch closes / status updates
- CI scripts that record progress per issue

Code-execution paths that don't touch notes are unaffected. Labels, status changes, and `bd close --reason` (single-call termination) appear durable.

The bug is silent — no error log, no exit code, no `bd doctor` warning. The only way to detect it is post-hoc verification (`bd show` against expected content).

---

## Suggested workarounds (current users)

1. **Use labels for routing, notes only for one-off audit entries.** Labels survive.
2. **Single-shot pattern only:** one `bd update --append-notes` per second, no batching. Verify each via `bd show --json` before continuing.
3. **Avoid `for` loops or `&&` chains with notes** until upstream fix lands.

## Suggested upstream fix

Add a post-write verification on the notes append path, or use `SELECT ... FOR UPDATE` inside a transaction for the read-modify-write. Either approach turns silent failure into either a transparent retry or an explicit error.

---

## Cross-project audit (for whoever investigates)

This project (LivingApp-Sidecar) is one of several in the same ecosystem using beads:

| Project | Path | bd prefix |
|---------|------|-----------|
| LivingApp-Sidecar | `/media/bob/C/AI_Projects/LivingApp-Sidecar` | `LivingApp-Sidecar-` |
| LivingApp-Platform | `/media/bob/C/AI_Projects/LivingApp-Platform` | `LivingApp-Platform-` |
| FlowInCash-Core | `/media/bob/C/AI_Projects/FlowInCash-Core` | `Core-` |
| Crispi-app | `/media/bob/C/AI_Projects/Crispi-app` | `Crispi-app-` |
| hermes-dev-team | `/media/bob/C/AI_Projects/hermes-dev-team` | various |

The probe script above is project-agnostic — it picks the top 16 issues from `bd ready` in the current directory. Running it in each sibling project will tell us whether the wobble is reproducible everywhere or specific to one Dolt instance.

Suggested for Hermes-driven audit: spawn one task per project running the probe, collect results, summarize whether the bug is environmental (one repo has a corrupted Dolt) or universal (every repo on the same bd version reproduces it).
