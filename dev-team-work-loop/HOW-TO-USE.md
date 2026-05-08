# How to Use the Local Kanban Dev-Team

**For:** Bob (local dev workflow on Mint-PC). Audience: non-developer.

This guide covers using the kanban-native dev-team to build features
autonomously on your laptop. The dev-team is the BUILD side of your
ecosystem — it turns feature ideas into committed, pushed code. The
LivingApp-Sidecar (RUN side, deployed to Railway with each app) is a
separate system; this guide doesn't cover it.

## Prereqs (one-time setup, already done)

- ✅ Hermes installed (`/home/bob/.local/bin/hermes`)
- ✅ Nous Portal authenticated via `hermes model` (your Super subscription)
- ✅ MiMo V2.5 Pro wired into the 6 dev-team profiles
- ✅ Quinn pointed at MiMo cloud
- ✅ Three docker-ollama containers running locally (only used by `dev-team/work-loop` legacy path)
- ✅ Dev-team SKILL.md role boundaries enforced (Slice 3)

If anything in the list above breaks: re-run `hermes model` to refresh
auth; or check `~/.hermes/profiles/*/config.yaml` for the model/provider
fields.

## The 3-step happy path

### Step 1: Plan a feature with vibe-plan

```bash
cd /path/to/your/project    # the repo you're adding the feature to
hermes chat --yolo -s dev-team/vibe-plan -q "Build feature X for my app"
```

Vibe-plan walks Phases 0–9 (analyst → brief → architecture → epics →
stories → TDD test files → bd issues → kanban story-roots). It runs
fully autonomously. Output:
- `docs/stories/*.md` — story specs
- TDD test files (e.g. `src/__tests__/*.test.ts`)
- bd issues (`bd list`)
- **kanban story-root tasks** (one per bd issue) — this is what the
  dev-team picks up

When vibe-plan exits, the kanban tasks are sitting in `ready` state
waiting for the dispatcher.

### Step 2: Run the kanban dispatcher

In another terminal:

```bash
# One-shot tick (good for first time)
hermes kanban dispatch

# Continuous loop (recommended for long sessions)
while true; do
  hermes kanban dispatch
  sleep 30
done
```

Or, if your hermes gateway is running, the dispatcher runs continuously
in the background — just leave it alone.

### Step 3: Watch progress

```bash
# Snapshot of all your kanban tasks
hermes kanban list --tenant <your-project-tenant>

# Live event stream
hermes kanban watch --kinds completed,blocked,crashed,timed_out

# Inspect one task in detail
hermes kanban show <task-id>
```

When all tasks are `done`, the bd issue is closed, the code is
committed with `fix(<bd-id>):` and pushed. You're done.

## What to do if it gets stuck

### A worker is `blocked`

Open the task and read the block reason:

```bash
hermes kanban show <task-id>
```

Look at the `Events` section. The block reason tells you what the
worker thought went wrong. Three common patterns:

**The reactive watcher should have caught it:** If you see `BLOCKER_TYPE=...` in the reason, the dev-orchestrator should pick up next tick. Wait 60s. If it still doesn't move, it's a real bug — kanban_block the orchestrator with details and `kanban kanban tail <task-id>` to see the full thread.

**bd-gate refused close:** The lander tried to close a bd issue but `.test-result` didn't match HEAD. Means cross-check failed upstream OR the lander didn't refresh `.test-result` after its amend. Check `.hermes/sessions/<bd-id>.test-result` against `git rev-parse HEAD`.

**You actually need to weigh in:** Some blocks are real human-in-the-loop. Read the reason, decide, then `hermes kanban unblock <task-id>` to resume.

### A worker `crashed` (PID died)

Most likely the LLM session crashed — Nous rate limit, network blip,
auth expired. The dispatcher will respawn it automatically up to 5
times, then auto-block.

If the crash repeats: check `auth.json` is current, then `hermes kanban reclaim <task-id>` to manually reset and try again.

### Tasks `timed_out`

Your task hit the `--max-runtime 90m` cap. Either the cloud is slow
today or the work is genuinely complex. Reclaim and re-run.

### Want to start fresh

```bash
# Archive everything in this tenant (keeps event history)
for tid in $(hermes kanban list --tenant <tenant> --json | jq -r '.[].id'); do
  hermes kanban archive "$tid"
done
```

## Cost control

Every cloud LLM call costs Nous credits. Estimate per story:
- Stack-detect: ~10K tokens, ~$0.04
- Health-check: ~30K tokens, ~$0.10
- Pi-coder (impl): ~150–300K tokens, ~$0.50–$1.20 (most expensive step)
- Cross-check: ~10K tokens, ~$0.04
- Lander + Quinn: ~30K tokens, ~$0.20

**Typical real story: $0.80–$1.50 in cloud cost.**

Budget alert: check `https://portal.nousresearch.com/manage-subscription`
once a week. Your $100 plan covers ~80–150 stories/month at typical
size. Upgrade if you're burning faster than that.

## Compaction setting

The dev-team profiles have `compression.threshold: 0.5` — context gets
compacted when it hits 50% full instead of the default 70%. This saves
credits by keeping prompts smaller. If a worker seems to be losing
context (forgetting earlier turns), bump to `0.7` in
`~/.hermes/profiles/<profile>/config.yaml`.

## When to NOT use the kanban dev-team

- **Tiny one-line edits.** Just `cd repo && pi --print --no-tools "fix the typo"` directly. The kanban overhead isn't worth it.
- **Exploration / "what would this look like?" prompts.** Use `hermes chat` interactively; don't kick off a full BMAD cycle.
- **Anything that touches your prod data.** The dev-team works on git repos. For prod ops, that's the LivingApp-Sidecar's job (deployed separately to Railway).

## Quick reference

| Command | What it does |
|---|---|
| `hermes chat -s dev-team/vibe-plan -q "..."` | Start a planning session |
| `hermes kanban list --tenant <t>` | Snapshot of tasks |
| `hermes kanban watch` | Live event stream |
| `hermes kanban show <id>` | Inspect one task |
| `hermes kanban unblock <id>` | Resume a blocked task |
| `hermes kanban reclaim <id>` | Reset a stuck task to ready |
| `hermes kanban archive <id>` | Move a task out of view |
| `hermes kanban dispatch` | Run one dispatcher tick |
| `bd list` | See all your bd issues |
| `bd show <id>` | Inspect one bd issue |

## Files that drive everything

- `~/.hermes/profiles/{dev-orchestrator,hermes-detector,hermes-health-check,pi-coder,hermes-verifier,hermes-lander}/config.yaml` — model/provider per profile
- `~/.hermes/auth.json` — your Nous OAuth (symlinked into each dev-team profile dir)
- `~/.hermes/config.yaml` — global Hermes config (compaction threshold, default model)
- `<repo>/skills/dev-team/*/SKILL.md` — what each worker is supposed to do

If something gets weird, those are the files to check first.
