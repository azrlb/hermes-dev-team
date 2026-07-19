# Beads (bd) CLI Reference

Quick reference for the `bd` commands used in bead management.

## Creating Beads

```bash
# Basic creation
bd create "Title" --type feature --priority 2 --description "Description"

# Create as child of an epic
bd create "Title" \
  --type feature \
  --priority 2 \
  --parent beads_FlowInCash_Core-lxm \
  --labels "epic:Core-lxm,story:1.0,fr:FR1" \
  --description "Full description..." \
  --silent  # outputs only the bead ID

# Key flags
--type       bug|feature|task|epic|chore|decision
--priority   0-4 or P0-P4 (0=highest)
--parent     Parent bead ID for hierarchical children
--labels     Comma-separated labels
--notes      Additional notes (goes into the notes field)
--deps       Dependencies: 'type:id' or just 'id'
--acceptance Acceptance criteria string
--silent     Output only the bead ID (for scripting)
--dry-run    Preview without creating
```

## Updating Beads

```bash
# Update notes (most common)
bd update beads_FlowInCash_Core-0eu --notes "New notes here"

# Update title
bd update beads_FlowInCash_Core-0eu --title "New title"

# Update description
bd update beads_FlowInCash_Core-0eu --description "New description"

# Claim work (sets assignee + status=in_progress)
bd update beads_FlowInCash_Core-0eu --claim

# Add labels
bd update beads_FlowInCash_Core-0eu --add-label "new-label"

# Multiple updates at once
bd update beads_FlowInCash_Core-0eu \
  --notes "Updated notes" \
  --title "Updated title" \
  --add-label "phase-1"
```

## Querying Beads

```bash
# List open beads
bd list --status=open

# List all beads as JSON
bd list --status=all --json

# Show a specific bead
bd show beads_FlowInCash_Core-0eu

# Show as JSON (for scripting)
bd show beads_FlowInCash_Core-0eu --json

# Find ready work
bd ready

# Search by label
bd list --status=open --json | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data if isinstance(data, list) else data.get('beads', data.get('items', []))
for i in items:
    if 'epic:Core-lxm' in i.get('labels', []):
        print(f\"{i.get('id','?')} | {i.get('title','?')[:60]}\")
"
```

## Closing Beads

```bash
# Close a bead (with attestation)
bd close beads_FlowInCash_Core-0eu

# Close with test result
bd close beads_FlowInCash_Core-0eu --result "PASS"
```

## Dolt Sync

```bash
# Commit beads changes to Dolt
bd dolt commit

# Pull from remote
bd dolt pull

# Push to remote
bd dolt push
```

## Common Python Queries

```bash
# Count open/closed
bd list --status=all --json | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data if isinstance(data, list) else data.get('beads', data.get('items', []))
open_c = sum(1 for i in items if i.get('status') == 'open')
closed_c = sum(1 for i in items if i.get('status') == 'closed')
print(f'Total: {len(items)} | Open: {open_c} | Closed: {closed_c}')
"

# Find beads with stale notes
bd list --status=open --json | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data if isinstance(data, list) else data.get('beads', data.get('items', []))
for i in items:
    notes = i.get('notes','') or ''
    if 'DO NOT' in notes or 'deferred' in notes.lower():
        print(f\"{i.get('id','?')} | STALE NOTES: {notes[:100]}\")
"

# List children of an epic
bd list --status=open 2>&1 | grep -A20 "epic-id"
```

## Notes on `bd create --parent`

Using `--parent` creates a sub-issue that appears indented under the epic
in `bd list` output:
```
├── ○ beads_FlowInCash_Core-lxm.1 ● P2 Story 1.0
├── ○ beads_FlowInCash_Core-lxm.2 ● P3 Story 1.1
└── ○ beads_FlowInCash_Core-lxm.3 ● P3 Story 1.2
```

The bead ID becomes `<parent-id>.<sequence>` (e.g. `beads_FlowInCash_Core-lxm.1`).

Alternative: create as top-level bead and reference it in the epic's description.
Both approaches work; sub-issues give a nicer tree view.
