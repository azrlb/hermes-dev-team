# Adding a New Hermes-Sidecar Skill (5-File Pattern)

When implementing a bead that requires a new hermes-sidecar skill, you MUST
update 5 files. Missing any of them causes test failures in `test_skill_loader`
or `test_skill_base` (hardcoded counts/names).

## The 5 Files

| # | File | What to do |
|---|------|-----------|
| 1 | `hermes-sidecar/skills/<name>.py` | Create the skill class extending `HermesSkill` |
| 2 | `hermes-sidecar/config/hermes_skills.yaml` | Register: name, module, class, trigger, schedule, tier, gateway_endpoints |
| 3 | `hermes-sidecar/tests/test_<name>.py` | Write tests (import, metadata, execute scenarios, gateway errors) |
| 4 | `hermes-sidecar/tests/test_skill_loader.py` | Update `test_manifest_loads_all_skills` count (N→N+1), add name to `test_manifest_skill_names` expected set, update `test_cfo_tier_gets_all_skills` count |
| 5 | `hermes-sidecar/tests/test_skill_base.py` | Add import, add to `ALL_SKILLS` list |

## Verification

After adding a skill, ALWAYS run the full sidecar test suite:
```bash
cd hermes-sidecar && .venv/bin/python -m pytest tests/
```
Do NOT just run the new test file — the loader/base tests will fail with
count mismatches if steps 4-5 are skipped.

## Pitfall: Hardcoded Counts

`test_skill_loader.py` has three tests with hardcoded skill counts:
- `test_manifest_loads_all_skills`: `assert len(entries) == N`
- `test_cfo_tier_gets_all_skills`: `assert len(skills) == N`
- `test_manifest_skill_names`: hardcoded set of skill name strings

`test_skill_base.py` has a hardcoded `ALL_SKILLS` list used by 6 parametrized
test functions. Adding a skill without updating this list causes the parametrized
tests to miss the new skill (no failure, but incomplete coverage).

## Example (2026-07-06)

Added `EarlyPayrollAlertSkill`. Created skill + 21 tests (all passed), but
`test_skill_loader.py` had `assert len(entries) == 10` and `test_skill_base.py`
had a hardcoded `ALL_SKILLS` list — 3 failures until both were updated to
expect 11 skills.

## Pitfall: Module-Level State Leaks Between Python Async Tests

When a skill uses a module-level dict for tracking (e.g., `_alert_tracker`,
`_early_alert_tracker`), that state PERSISTS between test functions in the
same pytest run. Test A sends an alert → tracker records it → Test B runs
with the same user_id → tracker says "already sent" → Test B gets wrong result.

**Fix — autouse fixture that clears the tracker:**
```python
from skills.early_payroll_alert import _early_alert_tracker

@pytest.fixture(autouse=True)
def _clear_early_tracker():
    """Clear the module-level alert tracker between tests."""
    _early_alert_tracker.clear()
    yield
    _early_alert_tracker.clear()
```

**Detection:** Test fails with `no_early_payroll_risk` when it expects
`early_payroll_alert_sent`, but only when run as part of the full suite
(not in isolation). The state leak is invisible in single-test runs.

**Why this matters:** Module-level state is common in hermes-sidecar skills
(in-memory alert trackers, dedup caches). Every skill with module-level
mutable state needs this pattern.

## Pitfall: Telegram None-Type Changes Expected Test Action

When testing a skill with `telegram_bot=None`, the `send_message` call is
skipped (guarded by `if context.telegram_bot is not None`). This means
`alerts_sent` stays 0 and the function returns a different action than expected.

**Wrong test:**
```python
async def test_no_telegram_bot():
    ctx = SkillContext(..., telegram_bot=None)
    result = await Skill().execute(ctx)
    assert "early_payroll_alert_sent" in result.actions_taken  # FAILS
```

**Correct test:**
```python
async def test_no_telegram_bot():
    ctx = SkillContext(..., telegram_bot=None)
    result = await Skill().execute(ctx)
    # No telegram bot → alerts_sent stays 0, returns no_risk
    assert "no_early_payroll_risk" in result.actions_taken
```

**Why this matters:** The skill's return action depends on whether messages
were actually sent, not just whether risk was detected. Tests must match
the code path for the specific mock configuration.

## Pitfall: Wiring Orphan Engines Into New Skills

When a bead says "X engine is an orphan" or "X has zero callers", the
existing engine code is USABLE but UNWIRED. The implementation pattern is:

1. **Read the orphan engine** — understand its API (method signatures, return types)
2. **Create a new skill** that calls the engine — the skill is the "wire"
3. **Fetch the data the engine needs** via gateway endpoints
4. **Pass the engine's output** to downstream logic (alerts, forecasts, etc.)

**Real example:** `PaymentProbabilityEngine` existed at
`hermes-sidecar/skills/receivables/payment_probability.py` with zero callers.
The new `EarlyPayrollAlertSkill` calls `engine.calculate_probability(invoice, history)`
and uses the output to predict pay-dates for rolling forecast.

**Detection:** `grep -rn "class_name" --include="*.py"` returns only the
class definition and its tests — no imports from other modules. The engine
is complete but孤立.

## Skill Base Class Pattern

All skills extend `HermesSkill` from `skills.base`:
```python
from skills.base import HermesSkill, SkillContext, SkillResult

class MySkill(HermesSkill):
    @property
    def name(self) -> str:
        return "my-skill"

    @property
    def description(self) -> str:
        return "What this skill does"

    @property
    def trigger_type(self) -> str:
        return "cron"  # or "event"

    @property
    def required_endpoints(self) -> list[str]:
        return ["endpoint1", "endpoint2"]

    async def execute(self, context: SkillContext) -> SkillResult:
        # Fetch data via context.gateway_client.request("GET", "/api/hermes/...", context.user_id)
        # Send messages via context.telegram_bot.send_message(context.user_id, message)
        return SkillResult(success=True, actions_taken=["action_name"], data={})
```

## Manifest Entry Pattern

```yaml
- name: my-skill
  module: skills.my_skill
  class: MySkill
  trigger: cron
  schedule: daily_morning  # or every_6_hours, weekly_monday_morning, etc.
  tier: [cfo]  # or [business, cfo]
  gateway_endpoints: [endpoint1, endpoint2]
```
