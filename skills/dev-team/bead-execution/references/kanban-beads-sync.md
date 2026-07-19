# Kanban-Beads Sync Reference

## Overview

The kanban-beads sync script (`~/.hermes/scripts/kanban-beads-sync.py`) keeps
kanban boards in sync with bead databases. It runs every 6 hours via cron.

## Two-Way Sync (Updated 2026-07-04)

The script now does TWO-WAY sync:
1. **Beads → Kanban**: Marks kanban tasks as "done" when beads close
2. **Kanban ← Beads**: Creates new kanban tasks for open beads

## Auto-Discovery

The script auto-discovers all projects with beads by scanning:
```
/media/bob/C/AI_Projects/*/.beads/issues.jsonl
```

No manual configuration per project — it finds them automatically.

## Board Naming Convention

Kanban boards live at:
```
~/.hermes/kanban/boards/<project-name>/kanban.db
```

The script maps project directory names to board names by lowercasing:
- `FlowInCash` → `flowincash`
- `Crispi-app` → `crispi-app`
- `FlowInCash-Core` → `flowincash-core`

**PITFALL**: If the board directory name doesn't match the project name,
the sync skips that project. Check `ls ~/.hermes/kanban/boards/` to verify.

## Creating New Boards

If a project doesn't have a kanban board:

```python
import sqlite3
from pathlib import Path

db_path = Path.home() / '.hermes/kanban/boards/<project-name>/kanban.db'
db_path.parent.mkdir(parents=True, exist_ok=True)

conn = sqlite3.connect(str(db_path))
c = conn.cursor()
c.execute('''
    CREATE TABLE IF NOT EXISTS tasks (
        id TEXT PRIMARY KEY,
        title TEXT,
        status TEXT DEFAULT 'todo',
        priority INTEGER DEFAULT 3,
        created_at INTEGER,
        completed_at INTEGER,
        bead_id TEXT
    )
''')
conn.commit()
conn.close()
```

## Switching Active Board

The dashboard shows the board listed in:
```
~/.hermes/kanban/current
```

To switch: `echo "flowincash" > ~/.hermes/kanban/current`

## Current Boards

| Board | Project | Status |
|-------|---------|--------|
| flowincash | FlowInCash Main | 59 open tasks |
| crispi-app | Crispi | 28 tasks (all done) |
| flowincash-core | FlowInCash-Core | All done (paused) |
| flowincash-practice | FlowInCash Practice | 52 open tasks |
| livingapp-sidecar | LivingApp Sidecar | 2 open tasks |
| crispi-microapps | Crispi MicroApps | 9 open tasks |

## Handling Empty Backlogs

When all beads in a project are closed:
- The sync marks all kanban tasks as "done"
- New drains exit gracefully (no tokens wasted)
- No need to reduce drain count

## Priority Labels

Beads are labeled in the kanban by priority:
- P0 → `[URGENT]`
- P1 → `[HIGH]`
- P2 → `[MEDIUM]`
- P3 → `[LOW]`
