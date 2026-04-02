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

```bash
pi --version
# Get current version

npm outdated @mariozechner/pi-coding-agent --global 2>/dev/null
# Or check in the MCP server directory:
cd ~/.hermes/mcp-servers/pi-agent && npm outdated
```

Parse output for available updates.

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
cd ~/.hermes/mcp-servers/pi-agent && npm update @mariozechner/pi-coding-agent
```

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
   - Hermes: `cd ~/hermes-agent && git reflog` to find prior commit, `git reset --hard {prior}`
   - Pi: `cd ~/.hermes/mcp-servers/pi-agent && npm install @mariozechner/pi-coding-agent@{prior_version}`
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
