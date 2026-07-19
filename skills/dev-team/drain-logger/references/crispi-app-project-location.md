# Crispi-app Project Location & Beads Config

## Project Path
`/media/bob/C/AI_Projects/Crispi-app`

## Running Beads Commands
Always `cd` to the project directory first:
```bash
cd /media/bob/C/AI_Projects/Crispi-app && bd list --all
```

## Key Files
- `AGENTS.md` — full stack config, testing rules, project conventions
- `beads_Crispi-app/` — local beads storage
- `.beads/` — beads config

## Testing
- **NEVER** `npm test` without `CI=true` (CRA/CRACO hangs in watch mode)
- Single file: `CI=true npx jest --testPathPattern <filename>`
- Full suite: `CI=true npm test`

## Other Crispi Projects
- `/media/bob/C/AI_Projects/Crispi-MicroApps` — separate micro-apps repo
- Kanban boards: `/local-AI-Stack/home-hermes/kanban/boards/crispi-app/`

## Common Pitfalls
- Don't confuse with `/home/bob/crispi-teasers/` (logo assets only)
- Don't confuse with `/home/bob/.beads-planning/` (different project's beads)
- The project uses `bd` (beads) NOT the kanban board for task tracking
