# Dynamic SQL Migration Runner Pattern

When a project has SQL migration files in a directory but the runner script
has a hardcoded list, replace it with a dynamic directory scan.

## Problem

Migration runner scripts often have a hardcoded array of migration files:
```bash
MIGRATIONS=("001_foo.sql" "002_bar.sql" "003_baz.sql")
```

This breaks when new migrations are added — someone must manually update the array.
Common symptom: migrations exist in the directory but aren't applied because the
array tops out at an old number.

## Solution — Dynamic Directory Scan

```bash
#!/bin/bash
set -euo pipefail

MIGRATIONS_DIR="${MIGRATIONS_DIR:-database/migrations}"

# Discover .sql files, sorted by filename (numeric prefix ensures order)
mapfile -t MIGRATIONS < <(find "$MIGRATIONS_DIR" -maxdepth 1 -name "*.sql" -type f | sort)

for migration_file in "${MIGRATIONS[@]}"; do
    migration_name=$(basename "$migration_file")
    echo "▶️  Running: $migration_name"
    psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$migration_file"
    echo "✅ Done: $migration_name"
done
```

## Key Features

1. **Dynamic discovery** — no hardcoded list, new migrations are picked up automatically
2. **Sorted by filename** — numeric prefixes (`001_`, `002_`, ...) ensure correct order
3. **Idempotent SQL** — migrations use `CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`
4. **Dry-run mode** — `--dry-run` lists migrations without executing
5. **Specific migration filter** — `./run-migrations.sh 049 050` runs only those migrations
6. **Fail-fast** — stops on first failure (`set -euo pipefail` + `ON_ERROR_STOP=1`)

## npm Script Integration

Add to `package.json`:
```json
{
  "scripts": {
    "db:migrate": "bash scripts/run-migrations.sh",
    "db:migrate:dry": "bash scripts/run-migrations.sh --dry-run"
  }
}
```

## Real Example

FlowInCash had a `run-migrations.sh` with a hardcoded array topping out at 010,
but 43 migration files existed (004 through 051). The fix replaced the array
with `find ... | sort`, and added `db:migrate` / `db:migrate:dry` npm scripts.

## Pitfalls

- **Non-numeric prefixes** sort after numbers in ASCII. Put numeric-prefixed files
  first, or use a sort that handles natural ordering (`sort -V` on GNU coreutils).
- **Schema-specific migrations** (e.g., `ALTER TABLE business.qbo_connections`) may
  need the schema to exist first. Ensure the schema creation migration runs before
  any schema-qualified DDL.
- **Dry-run should skip DB connection validation** — users want to see what would
  run without needing env vars set.
