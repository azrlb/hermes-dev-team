#!/usr/bin/env python3
"""Merge this repo's cron/jobs.json into ~/.hermes/cron/jobs.json.

The repo holds the version-controlled definitions of dev-team-owned cron
jobs (auto-update-pi-hermes, friday-gold-panning, etc.). Hermes reads its
own ~/.hermes/cron/jobs.json which also contains live-only jobs Bob added
through `hermes cron create` (Morning AI News, Morning Priority Check-In)
and runtime state (last_run_at, last_status, etc.) that the scheduler
updates on every tick.

This script merges them: repo's definitions overwrite the matching ids in
the live file's "spec" fields (prompt, schedule, enabled, model, etc.),
but runtime fields and live-only ids are preserved. Idempotent.

Why a script instead of a symlink: Hermes re-writes ~/.hermes/cron/jobs.json
on every tick to update runtime fields. A symlink would push those updates
into the git-tracked repo file, producing constant noisy commits and
mixing scheduler state with version control.

Usage:
  scripts/sync-cron-jobs.py            # merge + write
  scripts/sync-cron-jobs.py --dry-run  # show what would change, don't write

Called automatically by install.sh.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_JOBS_JSON = Path(__file__).resolve().parent.parent / "cron" / "jobs.json"
LIVE_JOBS_JSON = Path.home() / ".hermes" / "cron" / "jobs.json"

# Fields the repo's definition OWNS — if present in the repo's job, they
# overwrite whatever's in the live file. Order matches Hermes's canonical
# job-record key order so merged jobs don't get re-keyed weirdly.
SPEC_FIELDS = (
    "id",
    "name",
    "prompt",
    "skills",
    "skill",
    "model",
    "provider",
    "base_url",
    "script",
    "no_agent",
    "context_from",
    "schedule",
    "schedule_display",
    "repeat",
    "enabled",
    "deliver",
    "origin",
)

# Fields the live scheduler OWNS — these are runtime state. If the repo's
# job specifies these (it shouldn't — they're meaningless until a run
# happens), ignore the repo value and keep what's live.
RUNTIME_FIELDS = (
    "state",
    "paused_at",
    "paused_reason",
    "created_at",
    "next_run_at",
    "last_run_at",
    "last_status",
    "last_error",
    "last_delivery_error",
    "enabled_toolsets",
    "workdir",
)


def load(path: Path) -> dict:
    with path.open("r") as f:
        return json.load(f)


def save(path: Path, data: dict) -> None:
    with path.open("w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    if str(path).startswith(str(Path.home() / ".hermes")):
        os.chmod(path, 0o600)


def merge_one(repo_job: dict, live_job: dict | None) -> dict:
    """Build the merged record for one job id.

    If live_job is None this is an insert: take repo's spec fields and
    fill runtime fields with sensible defaults.
    Otherwise an update: spec fields from repo, runtime fields from live.
    """
    out: dict = {}
    if live_job is None:
        # Insert: defaults for the runtime fields.
        defaults = {
            "state": "scheduled",
            "paused_at": None,
            "paused_reason": None,
            "created_at": datetime.now(timezone.utc).astimezone().isoformat(),
            "next_run_at": None,
            "last_run_at": None,
            "last_status": None,
            "last_error": None,
            "last_delivery_error": None,
            "enabled_toolsets": None,
            "workdir": None,
        }
        # Build in canonical key order: spec, then runtime.
        for k in SPEC_FIELDS:
            if k in repo_job:
                out[k] = repo_job[k]
        for k in RUNTIME_FIELDS:
            out[k] = defaults[k]
        return out

    # Update: spec fields from repo, runtime fields from live. Match the
    # live job's key order so the diff is minimal.
    for k in live_job.keys():
        if k in SPEC_FIELDS:
            out[k] = repo_job.get(k, live_job[k])
        else:
            out[k] = live_job[k]
    # If the repo introduced a new spec field the live record didn't have,
    # carry it through too.
    for k in SPEC_FIELDS:
        if k in repo_job and k not in out:
            out[k] = repo_job[k]
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would change; don't write.",
    )
    parser.add_argument(
        "--no-backup",
        action="store_true",
        help="Skip backing up the live file (default: backup to .bak-<timestamp>).",
    )
    args = parser.parse_args()

    if not REPO_JOBS_JSON.exists():
        print(f"ERROR: repo jobs file not found: {REPO_JOBS_JSON}", file=sys.stderr)
        return 1
    if not LIVE_JOBS_JSON.exists():
        print(f"ERROR: live jobs file not found: {LIVE_JOBS_JSON}", file=sys.stderr)
        print(f"Hermes may not be installed, or its config dir is elsewhere.", file=sys.stderr)
        return 1

    repo = load(REPO_JOBS_JSON)
    live = load(LIVE_JOBS_JSON)

    repo_by_id = {j["id"]: j for j in repo.get("jobs", [])}
    live_by_id = {j["id"]: j for j in live.get("jobs", [])}

    inserted: list[str] = []
    updated: list[str] = []
    unchanged: list[str] = []
    live_only: list[str] = [jid for jid in live_by_id if jid not in repo_by_id]

    new_jobs: list[dict] = []
    # Preserve the live file's existing job order, applying merges in place.
    for live_job in live.get("jobs", []):
        jid = live_job["id"]
        if jid in repo_by_id:
            merged = merge_one(repo_by_id[jid], live_job)
            if merged == live_job:
                unchanged.append(jid)
            else:
                updated.append(jid)
            new_jobs.append(merged)
        else:
            new_jobs.append(live_job)

    # Append repo jobs that weren't in live (preserves existing order;
    # new entries land at the end).
    for jid, repo_job in repo_by_id.items():
        if jid not in live_by_id:
            new_jobs.append(merge_one(repo_job, None))
            inserted.append(jid)

    new_live = dict(live)
    new_live["jobs"] = new_jobs
    new_live["updated_at"] = datetime.now(timezone.utc).astimezone().isoformat()

    print("Sync plan:")
    print(f"  Repo path: {REPO_JOBS_JSON}")
    print(f"  Live path: {LIVE_JOBS_JSON}")
    print(f"  Inserted: {len(inserted)} {inserted}")
    print(f"  Updated:  {len(updated)} {updated}")
    print(f"  Unchanged: {len(unchanged)} {unchanged}")
    print(f"  Live-only (preserved as-is): {len(live_only)} {live_only}")

    if args.dry_run:
        print("\n--dry-run set — not writing.")
        return 0

    if not inserted and not updated:
        print("\nNo changes to apply. Live file untouched.")
        return 0

    if not args.no_backup:
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup = LIVE_JOBS_JSON.with_suffix(f".json.bak-{ts}")
        shutil.copy(LIVE_JOBS_JSON, backup)
        print(f"\nBacked up live file -> {backup}")

    save(LIVE_JOBS_JSON, new_live)
    print(f"Wrote {LIVE_JOBS_JSON}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
