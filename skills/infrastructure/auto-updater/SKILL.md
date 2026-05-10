# Auto Updater

Checks for and installs updates to Hermes Agent and Pi Coding Agent. Keeps the platform current without Bob needing to remember.

## Trigger

- **Cron:** Weekly check (configurable via AUTO_UPDATE_CRON, default: Sunday 3 AM)
- **Telegram:** Bob sends `check updates` or `update hermes` or `update pi`
- **On-demand:** After detecting version-related errors

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `AUTO_UPDATE_CRON` | `0 3 * * 0` | When to check for updates (default: Sunday 3 AM) |
| `AUTO_UPDATE_ENABLED` | `check` | `check` = notify only, `install` = auto-install, `off` = disabled |
| `AUTO_UPDATE_HERMES` | `true` | Include Hermes in update checks |
| `AUTO_UPDATE_PI` | `true` | Include Pi in update checks |

## Steps

### 1. Check Hermes Updates

```bash
hermes --version
# Output includes "Update available: N commits behind" if outdated
```

Parse the output:
- If "Update available" → updates pending
- If no update message → already current
- Record current version for comparison

### 2. Check Pi Updates

**Use ONLY the canonical upstream package `@earendil-works/pi-coding-agent`.** The historical `@mariozechner/pi-coding-agent` is npm-deprecated and must NOT be installed or updated. See `dev-team-work-loop/CRON-AUTO-UPDATE-REWRITE.md` for the migration history.

```bash
# Get current installed Pi version
pi --version

# Verify the global pi binary is the canonical fork — NOT the deprecated one
ls -la "$(which pi)"
# The symlink target should include "@earendil-works/pi-coding-agent" in the path.
# If it includes "@mariozechner": ABORT this skill. Telegram a "MANUAL INTERVENTION
# NEEDED — global pi still on deprecated fork" alert and STOP. Do NOT auto-install
# anything to "correct" this — it requires deliberate cleanup per the dev-team
# migration plan.

# Get latest canonical version
npm view @earendil-works/pi-coding-agent version

# Also check the global MCP server install (if present)
[ -d ~/.hermes/mcp-servers/pi-agent ] && cd ~/.hermes/mcp-servers/pi-agent && npm outdated
```

Parse output for available updates. Refuse to act if the global pi binary still resolves to the deprecated fork.

### 3. Report

If AUTO_UPDATE_ENABLED = `check` (default):

**Telegram:**
```
🔄 Update Check — {date}

Hermes: v{current} → v{available} ({n} commits behind)
Pi: v{current} → v{available}

Reply "update hermes", "update pi", or "update all" to install.
```

If no updates: skip notification (don't spam Bob with "all current").

### 4. Install (if enabled or requested)

**Hermes update:**
```bash
hermes update
```
This pulls latest, reinstalls dependencies, restarts gateway automatically.

**Pi update:**
```bash
# Update the global pi binary (canonical fork only — never @mariozechner)
npm install -g @earendil-works/pi-coding-agent@latest

# Update the global MCP server install (if present)
[ -d ~/.hermes/mcp-servers/pi-agent ] && cd ~/.hermes/mcp-servers/pi-agent && npm update @earendil-works/pi-coding-agent
```

**NEVER install any package whose npm `deprecated` field is set.** Check before installing: `npm view <package> deprecated` — if it returns a non-empty deprecation message, ABORT and Telegram a "MANUAL INTERVENTION NEEDED — package marked deprecated upstream" alert.

**Post-update verification:**
```bash
hermes --version    # Confirm new version
pi --version        # Confirm new version
hermes skills list  # Verify skills still loaded
```

### 5. Post-Update Health Check

After any update:
1. Run health_check tool to verify all components still working
2. If health check fails → roll back:
   - Hermes: `cd /local-AI-Stack/home-hermes/hermes-agent && git reflog` to find prior commit, `git reset --hard {prior}` then re-run `pip install -e .` in the venv
   - Pi (global binary): `npm install -g @earendil-works/pi-coding-agent@{prior_version}` (NEVER roll back to the deprecated `@mariozechner` package — even on rollback)
   - Pi (global MCP server, if present): `cd ~/.hermes/mcp-servers/pi-agent && npm install @earendil-works/pi-coding-agent@{prior_version}`
3. Telegram: "⚠️ Update rolled back — health check failed after update. Prior version restored."

### 6. Notify

**On successful update:**
```
✅ Updates installed — {date}

Hermes: v{old} → v{new}
Pi: v{old} → v{new}

Health check: ✅ All components healthy
```

**On failed update:**
```
⚠️ Update failed — {date}

{component}: update failed — {error}
Rolled back to v{old}

Action needed: check manually or retry later.
```

## Audit Trail

Log every check and update:
```
action: update_check | update_install | update_rollback
target: hermes | pi
detail: { old_version, new_version, status, health_check_result }
```

## Safety

- Never auto-install during active work-loop (check bd list --status=in_progress first)
- Always verify health after update
- Rollback capability for both components
- Bob can disable via AUTO_UPDATE_ENABLED=off

## Dependencies

- Hermes CLI (`hermes update`, `hermes --version`)
- Pi CLI (`pi --version`)
- npm (for Pi package updates)
- health_check Pi tool (post-update verification)
- Telegram for notifications
- platform.db for audit logging
