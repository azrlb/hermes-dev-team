# Growth Runner

Designs, runs, and measures A/B growth experiments using the Autoresearch pattern (Karpathy). Reads the consuming app's growth program, generates experiment hypotheses, implements them, measures results, and decides next steps based on statistical significance.

## Trigger

- **Cron:** Weekly experiment cycle (e.g. every Monday 09:00 UTC)
- **Telegram:** Bob sends `run experiment` → start next experiment from growth program
- **Telegram:** Bob sends `experiment status` → report on active experiment

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `GROWTH_ENABLED` | `false` | Master switch — no experiments run unless explicitly enabled |
| `EXPERIMENT_DURATION_DAYS` | `7` | Default duration before measuring results |
| `SIGNIFICANCE_THRESHOLD` | `0.05` | p-value threshold for statistical significance (two-tailed) |
| `MAX_ACTIVE_EXPERIMENTS` | `1` | Max concurrent experiments per consuming app |
| `GROWTH_PROGRAM_PATH` | `docs/growth-program.md` | Path within consuming app repo to growth program |

## Steps

### 1. Load Growth Program

Read the consuming app's growth program:
```
gateway_request({
  app: "{app_id}",
  action: "read_file",
  path: "{GROWTH_PROGRAM_PATH}"
})
```

Parse the growth program for:
- Current growth priorities (ordered by expected impact)
- Target metrics (conversion rates, engagement, retention)
- Past experiment results (to avoid re-running)
- Constraints (traffic volume, seasonality, audience segments)

If no growth program found, log warning and exit.

### 2. Check Active Experiments

Query `platform.db` experiments table:
```sql
SELECT * FROM experiments
WHERE app_id = '{app_id}' AND status IN ('RUNNING', 'MEASURING')
```

If an active experiment exists:
- If status is `RUNNING` and duration exceeded → advance to MEASURE (Step 5)
- If status is `RUNNING` and midpoint reached → send midpoint Telegram report
- If status is `MEASURING` → advance to ANALYZE (Step 6)
- Do NOT start a new experiment while one is active (guard rail)

### 3. DESIGN Experiment

Select the highest-priority untested hypothesis from the growth program.

Generate experiment spec:

| Field | Description |
|-------|-------------|
| `hypothesis` | "Changing X will improve Y by Z%" |
| `control` | Current behavior (no change) |
| `variant` | Proposed change description |
| `success_metric` | Primary metric to measure (e.g. `signup_conversion_rate`) |
| `secondary_metrics` | Additional metrics to watch for regressions |
| `sample_size` | Minimum users per arm (calculated from expected effect size + power 0.8) |
| `duration_days` | `EXPERIMENT_DURATION_DAYS` or longer if traffic is low |
| `revert_plan` | Exact steps to undo the variant if it loses |
| `app_id` | Consuming app identifier |

Store in `platform.db`:
```sql
INSERT INTO experiments (
  id, app_id, status, hypothesis, control_desc, variant_desc,
  success_metric, secondary_metrics, sample_size, duration_days,
  revert_plan, designed_at
) VALUES (...)
```

**Audit log:** `experiment.designed | {id} | {hypothesis}`

Telegram to Bob:
```
Experiment {id} designed for {app_id}:
Hypothesis: {hypothesis}
Metric: {success_metric}
Duration: {duration_days} days
Awaiting approval to implement.
```

**Wait for Bob's approval before proceeding.** Bob replies `approve {id}` or `reject {id}`.

### 4. IMPLEMENT Experiment

After Bob approves, implement the variant via `gateway_request`:
```
gateway_request({
  app: "{app_id}",
  action: "create_experiment",
  experiment_id: "{id}",
  variant: "{variant_desc}",
  traffic_split: 50
})
```

Update experiment status:
```sql
UPDATE experiments SET status = 'RUNNING', started_at = NOW() WHERE id = '{id}'
```

**Audit log:** `experiment.started | {id} | traffic_split=50%`

Telegram to Bob:
```
Experiment {id} is LIVE.
Control: {control_desc}
Variant: {variant_desc}
Measuring for {duration_days} days.
Next check: {midpoint_date}
```

### 5. MEASURE Results

Triggered when experiment duration is reached (or midpoint for interim check).

Fetch metrics via `gateway_request`:
```
gateway_request({
  app: "{app_id}",
  action: "get_experiment_metrics",
  experiment_id: "{id}",
  metrics: ["{success_metric}", ..."{secondary_metrics}"]
})
```

Expected response shape:
```json
{
  "control": { "users": 1200, "conversions": 84, "rate": 0.07 },
  "variant": { "users": 1180, "conversions": 102, "rate": 0.0864 }
}
```

Store raw results:
```sql
UPDATE experiments SET
  control_users = {n}, control_conversions = {n},
  variant_users = {n}, variant_conversions = {n},
  measured_at = NOW(), status = 'MEASURING'
WHERE id = '{id}'
```

**Audit log:** `experiment.measured | {id} | control_rate={x} variant_rate={y}`

### 6. ANALYZE Statistical Significance

Run a two-proportion z-test (or chi-square for categorical outcomes):

```
p_control = control_conversions / control_users
p_variant = variant_conversions / variant_users
p_pooled  = (control_conversions + variant_conversions) / (control_users + variant_users)
SE        = sqrt(p_pooled * (1 - p_pooled) * (1/control_users + 1/variant_users))
z         = (p_variant - p_control) / SE
p_value   = 2 * (1 - normalCDF(abs(z)))
```

Determine result:
- **lift** = `(p_variant - p_control) / p_control * 100`
- **significant** = `p_value < SIGNIFICANCE_THRESHOLD`
- **direction** = `positive` if `p_variant > p_control`, else `negative`

Check secondary metrics for regressions (any secondary metric declining > 5% is flagged).

Update experiment:
```sql
UPDATE experiments SET
  p_value = {p}, lift_pct = {lift}, significant = {bool},
  direction = '{dir}', secondary_regressions = '{flags}',
  analyzed_at = NOW(), status = 'ANALYZED'
WHERE id = '{id}'
```

**Audit log:** `experiment.analyzed | {id} | p={p_value} lift={lift}% significant={bool}`

### 7. DECIDE Next Action

| Condition | Action |
|-----------|--------|
| Significant + positive lift + no secondary regressions | Recommend permanent implementation to Bob |
| Significant + negative lift | Auto-revert variant immediately |
| Not significant + duration < 2x original | Extend experiment by `EXPERIMENT_DURATION_DAYS` |
| Not significant + duration >= 2x original | Auto-revert, mark as inconclusive |
| Any secondary regression flagged | Alert Bob, pause experiment, await decision |

**On recommend (positive result):**

Telegram to Bob:
```
Experiment {id} WINNER:
{hypothesis}
Lift: +{lift}% (p={p_value})
Control: {control_rate} | Variant: {variant_rate}
Recommend: implement permanently.
[Approve] [Revert] [Extend]
```

Wait for Bob's decision. If approved:
```
gateway_request({
  app: "{app_id}",
  action: "promote_experiment",
  experiment_id: "{id}"
})
```

```sql
UPDATE experiments SET status = 'PROMOTED', decided_at = NOW() WHERE id = '{id}'
```

**Audit log:** `experiment.promoted | {id} | approved_by=Bob`

**On auto-revert (negative or inconclusive):**
```
gateway_request({
  app: "{app_id}",
  action: "revert_experiment",
  experiment_id: "{id}"
})
```

```sql
UPDATE experiments SET status = 'REVERTED', decided_at = NOW() WHERE id = '{id}'
```

**Audit log:** `experiment.reverted | {id} | reason={negative|inconclusive}`

Telegram to Bob:
```
Experiment {id} REVERTED.
Result: {reason}
Lift: {lift}% (p={p_value})
No changes applied.
```

**On extend:**
```sql
UPDATE experiments SET
  duration_days = duration_days + {EXPERIMENT_DURATION_DAYS},
  status = 'RUNNING'
WHERE id = '{id}'
```

**Audit log:** `experiment.extended | {id} | new_duration={n} days`

## Guard Rails

- **Max 1 active experiment per app.** Prevents confounding variables.
- **Every experiment must have a revert plan** defined at design time.
- **Bob approves before implementation** and before permanent promotion.
- **Auto-revert on negative results.** No human delay needed to stop a losing experiment.
- **Secondary metric regression check.** Winning primary metric doesn't override damage elsewhere.
- **Duration cap at 2x original.** Inconclusive experiments don't run forever.
- **`GROWTH_ENABLED` defaults to false.** Must be explicitly turned on per deployment.

## Error Handling

- If `gateway_request` fails to fetch metrics: retry once after 1 hour, then alert Bob via Telegram
- If `platform.db` is unreachable: log error, do not start new experiments, alert via Telegram
- If experiment implementation fails: mark as `FAILED`, revert, alert Bob
- If statistical calculation produces NaN (e.g. zero users): mark as `FAILED`, alert Bob
- Never leave an experiment in a transitional state without an audit log entry

## Dependencies

- **gateway_request**: Read app files, create/promote/revert experiments, fetch analytics metrics
- **platform.db**: `experiments` table for experiment state and results
- **Telegram**: All approvals, reports, and alerts routed through telegram-dispatch skill
- **App growth program**: `{app_repo}/{GROWTH_PROGRAM_PATH}` — source of experiment hypotheses
- **App analytics API**: Accessed via gateway_request for conversion, engagement, and retention metrics
