# GEPA Monthly Skill Evolution

Automated monthly skill evolution for the dev-team SKILL.md files using
[hermes-agent-self-evolution](https://github.com/NousResearch/hermes-agent-self-evolution)
(DSPy + GEPA).

## What it does

Once a month (1st of each month, 03:00 local):

1. Picks one of four priority skills via rotation:
   - Month 1: `escalation-handler`
   - Month 2: `pi-dispatcher`
   - Month 3: `cross-check`
   - Month 4: `land-the-plane`
2. Runs GEPA on the chosen skill (5 iterations, ~13–15 min, ~$5–10)
3. Re-runs the relevant fixture (kanban-block-watcher / kanban-lander-head-moved)
   against the evolved candidate
4. Runs a Quinn-style audit (Sonnet 4.6) on the diff — checks for
   banned-phrase regressions, role-boundary drift, table-structure
   regressions, security-theater additions, semantic drift
5. **APPROVED** → commits the evolved SKILL.md directly to dev and
   pushes (fully automated — Sonnet 4.6 audit + fixture run are the gates)
6. **REJECTED** or **fixture-failed** → archives the candidate to
   `_evolved/rejected/` with reasoning, no commit

All artifacts (GEPA logs, audit prompts/responses, evolved candidates,
decisions) are durable in `_evolved/<date>-<skill>/`. Both directories
(`_evolved/` and `logs/`) are gitignored.

## Setup (one-time)

### 1. API key file

```bash
read -srp "Paste Nous API key: " KEY
printf 'export NOUS_API_KEY=%s\n' "$KEY" > ~/.gepa-env
chmod 600 ~/.gepa-env
unset KEY
```

### 2. hermes-agent-self-evolution clone + install

```bash
cd /media/bob/C/AI_Projects
git clone https://github.com/NousResearch/hermes-agent-self-evolution.git
cd hermes-agent-self-evolution
python3 -m venv .venv
.venv/bin/pip install -e ".[dev]"
```

### 3. Install the cron entry

```bash
(crontab -l 2>/dev/null; echo "0 3 1 * * /media/bob/C/AI_Projects/hermes-dev-team/scripts/gepa-monthly.sh >> /media/bob/C/AI_Projects/hermes-dev-team/logs/gepa-cron.log 2>&1") | crontab -
```

Verify:
```bash
crontab -l | grep gepa-monthly
```

## Manual invocation

Run on demand (overrides the rotation):

```bash
./scripts/gepa-monthly.sh escalation-handler
```

Without an argument, the script picks the rotation entry for the
current month.

## Disabling / pausing

Remove the cron entry:
```bash
crontab -e
# delete the line containing gepa-monthly.sh
```

Or rename the script so cron can't find it:
```bash
mv scripts/gepa-monthly.sh scripts/gepa-monthly.sh.disabled
```

## Cost cap

Each run is ~$5–10. Monthly cap with the default 5-iteration setting.
If you want to cap harder, edit `ITERATIONS` at the top of the script
(lower iterations = lower cost, less optimization signal).

## You don't need to do anything

The pipeline is fully autonomous. Sonnet 4.6 acts as the reviewer and
auto-commits to dev when the audit passes. You don't need to look at
GitHub, you don't need to merge anything.

If you ever want to see what happened:
- `logs/gepa-monthly.log` — high-level outcome of each run
- `_evolved/approved/<date>-<skill>/` — full provenance of shipped evolutions
- `_evolved/rejected/<date>-<skill>/` — full provenance of rejected proposals
- `git log --oneline --grep "GEPA-evolved"` — every shipped evolution
  appears as a commit by `gepa-bot`

## What "rejected" looks like

- `_evolved/rejected/<date>-<skill>-no-change/` — GEPA couldn't improve
  on the current SKILL (already at a local optimum). Normal and common.
- `_evolved/rejected/<date>-<skill>-fixture-fail/` — fixture broke under
  the candidate. Auto-rejected, never reaches the audit step.
- `_evolved/rejected/<date>-<skill>/` — Sonnet 4.6 audit said no.
  Reasoning in `decision.md` inside the directory.

## Audit gate strictness

The audit prompt is conservative because there's no human after it.
Sonnet 4.6 is told: "If any rule is even arguably violated, REJECT."
Most proposed evolutions will be REJECTED on minor wording drift —
that's the safe default. The few that pass are genuine improvements.

## If something goes wrong

If a shipped evolution turns out to break something:

```bash
cd /media/bob/C/AI_Projects/hermes-dev-team
git log --oneline -5            # find the gepa-bot commit
git revert <commit-sha>         # creates an inverse commit
git push origin dev             # un-ships the evolution
```

The original SKILL is restored. The next month's GEPA run will start
from the restored baseline.
