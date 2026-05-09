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
5. **APPROVED** → opens a GitHub PR on a `gepa/<date>-<skill>` branch
   (no auto-merge — you click merge when comfortable)
6. **REJECTED** or **fixture-failed** → archives the candidate to
   `_evolved/rejected/` with reasoning

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

## What to do when you get a PR

1. Read the PR description — the audit's improvement bullets explain what changed
2. Skim the SKILL.md diff — anything that looks weakening or surprising? Reject.
3. If you have time: locally re-run the matching fixture against the PR branch
4. Merge if comfortable; close if not.

## What to do when nothing changed

If GEPA found no improvement (same SKILL hash both sides), you'll see
an entry in `_evolved/rejected/<date>-<skill>-no-change/`. That's
normal — the SKILL is already at a local optimum.
