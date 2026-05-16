# Hermes Prompt Pattern

**How to create prompts that work with Hermes Agent pipelines.**

*Last updated: 2026-05-14*

---

## The Problem

BMAD agents create prompts for Hermes to execute overnight work. If the prompt
doesn't match how Hermes actually runs, the pipeline completes one task and
stops — leaving remaining work idle.

## The Rule

**NEVER use vague prompts like "pick up P0 work" or "process the next story."**

Hermes runs two execution modes:

1. **Single-story mode** — runs ONE story through the full vibe-loop pipeline
2. **Backlog-draining mode** — processes ALL ready issues in a loop

The prompt MUST match the intended mode.

---

## Template 1: Single-Story Execution

Use when: one specific story needs implementation.

```
cd /media/bob/C/AI_Projects/{project} && hermes chat -s dev-team/vibe-loop --yolo -q "
  Brownfield: Execute story {story_id}.
  Beads issue: {beads_id} (status: ready).
  Story spec: {path_to_story_file}.
  Start at {starting_phase}.
  Read AGENTS.md for project rules.
  Run all phases through quinn-review and e2e-validation.
  Halt only on Phase 12 (deploy) for secrets.
"
```

### Fields

| Field                  | Example                                                       | Notes                   |
| ---------------------- | ------------------------------------------------------------- | ----------------------- |
| `{project}`            | `LivingApp-Sidecar`                                           | Project directory name  |
| `{story_id}`           | `1-2-emit-audit-row`                                          | Story identifier        |
| `{beads_id}`           | `LivingApp-Sidecar-2wx`                                       | Beads issue ID          |
| `{path_to_story_file}` | `_bmad-output/implementation-artifacts/1-2-emit-audit-row.md` | Story spec location     |
| `{starting_phase}`     | `dev` or `tdd`                                                | Which phase to begin at |

---

## Template 2: Overnight Backlog-Draining

Use when: process ALL ready work in one session.

```
cd /media/bob/C/AI_Projects/{project} && hermes chat -s dev-team/vibe-loop --yolo -q "
  Brownfield: Process ALL ready beads issues for {project}.
  Steps:
  1. Run 'bd ready' to get all unblocked issues
  2. For EACH ready issue (P0 first, then P1, then P2):
     a. Read the story spec from _bmad-output/implementation-artifacts/
     b. Run the full vibe-loop pipeline on that story
     c. Close the beads issue when tests pass
     d. Commit and push
  3. Loop until 'bd ready' returns zero ready issues
  Read AGENTS.md for project rules.
  Halt only on Phase 12 (deploy) for secrets.
"
```

---

## Template 3: Kanban Dispatcher Mode

Use when: kanban board is populated and gateway is running.

```
cd /media/bob/C/AI_Projects/{project} && hermes chat -s dev-team/vibe-loop --yolo -q "
  Brownfield: Populate kanban from beads, then execute all ready work.
  Steps:
  1. Switch to correct kanban board: hermes kanban boards switch {board_slug}
  2. For each issue in 'bd ready':
     Create kanban task with --workspace 'dir:/media/bob/C/AI_Projects/{project}'
     and --idempotency-key '{beads_id}'
  3. Start the gateway dispatcher (if not running): hermes gateway start
  4. Let the dispatcher process all ready tasks
  5. Monitor until all tasks complete
  Read AGENTS.md for project rules.
"
```

---

## Landing Protocol (bd-gate enforced)

When closing a beads issue, you MUST follow the correct order for your
context. bd-gate intercepts terminal calls and blocks closes that don't match.

### Pattern A: Manual/Overnight Runs (CLAUDE.md)

Use for: hermes chat --yolo runs, single-story execution, overnight pipelines.

```
1. Make code + spec changes; verify tests pass
2. Update story spec to mark AC closed
3. git add <specific files>          (NEVER -A or .)
4. git commit -m 'feat({beads_id}): {title}'  (with Co-Authored-By)
5. ONLY NOW: bd close {beads_id} --reason '<one-line summary>'
6. git add .beads/issues.jsonl
7. git commit -m 'chore(beads): close {beads_id}'
8. git pull --rebase origin main
9. git push origin main
10. Verify 'git status' shows clean working tree + 'up to date with origin'
```

### Pattern B: Kanban Dispatcher (land-the-plane skill)

Use for: kanban gateway dispatcher, automated landing.

```
1. Write test attestation: echo "PASS $(git rev-parse HEAD)" > .hermes/sessions/{beads_id}.test-result
2. Commit with fix prefix: git commit -m "fix({beads_id}): {title}"
3. Close beads issue: bd close {beads_id}
4. Amend to absorb beads state: git add .beads/ && git commit --amend --no-edit
5. Refresh test attestation (HEAD changed after amend)
6. Push: git push --force-with-lease (lease required because amend rewrote SHA)
```

Source-changed pre-check: diff must touch at least one `src/*` file.
Metadata-only commits (only `.beads/`, `.hermes/`, `dist/`) are rejected.

---

## Critical Rules

1. **ALWAYS `cd` to the project directory first** — Hermes uses cwd to find AGENTS.md, .beads/, _bmad-output/
2. **ALWAYS specify the beads issue ID** — so Hermes can claim and close it
3. **ALWAYS specify the story spec path** — so Hermes knows what to implement
4. **NEVER say "pick up P0 work"** — vague, causes single-task completion
5. **NEVER say "process the next story"** — only processes ONE story
6. **Use `--yolo` for overnight runs** — no human gates between phases
7. **Use `--yolo` + `-q` for autonomous execution** — one-shot query mode
8. **NEVER use `git add -A` or `git add .`** — stage files explicitly
9. **Write `.test-result` BEFORE `bd close`** — bd-gate requires it
10. **Refresh `.test-result` AFTER amend** — HEAD changes, attestation must match

---

## How to Check What's Ready

Before creating a prompt, check the current state:

```bash
cd /media/bob/C/AI_Projects/{project}
bd ready              # Shows all unblocked issues
bd show {issue_id}    # Shows issue details with full description
hermes kanban ls      # Shows kanban board state
```

---

## Anti-Patterns

| Bad Prompt               | Why It Fails                                     | Fix                                         |
| ------------------------ | ------------------------------------------------ | ------------------------------------------- |
| "Pick up P0 work"        | Vague — Hermes finds one P0, completes it, stops | List specific issue IDs OR use Template 2   |
| "Process the next story" | Only processes ONE story                         | Use "Process ALL ready issues"              |
| "Continue the pipeline"  | Unclear where to start                           | Specify starting phase and story            |
| No `cd` to project dir   | Hermes can't find AGENTS.md, .beads/             | Always prefix with `cd /path/to/project &&` |
| No beads issue ID        | Hermes can't claim/close the issue               | Always include the beads ID                 |
| No story spec path       | Hermes doesn't know what to build                | Always include the path                     |

---

## Project Quick Reference

| Project            | Directory                                     | Board Slug         | Beads Prefix        |
| ------------------ | --------------------------------------------- | ------------------ | ------------------- |
| FlowInCash-Core    | `/media/bob/C/AI_Projects/FlowInCash-Core`    | flowincash-core    | Core-               |
| LivingApp-Sidecar  | `/media/bob/C/AI_Projects/LivingApp-Sidecar`  | livingapp-sidecar  | LivingApp-Sidecar-  |
| Crispi-app         | `/media/bob/C/AI_Projects/Crispi-app`         | crispi-app         | Crispi-app-         |
| LivingApp-Platform | `/media/bob/C/AI_Projects/LivingApp-Platform` | livingapp-platform | LivingApp-Platform- |

---

## Example: Sidecar Overnight Run

**What the BMAD architect should write:**

```
cd /media/bob/C/AI_Projects/LivingApp-Sidecar && hermes chat -s dev-team/vibe-loop --yolo -q "
  Brownfield: Process ALL ready beads issues for LivingApp-Sidecar.
  Steps:
  1. Run 'bd ready' to get all unblocked issues
  2. For EACH ready issue:
     a. Read the story spec from _bmad-output/implementation-artifacts/
     b. Run the full vibe-loop pipeline on that story
     c. Close the beads issue when tests pass
     d. Commit and push
  3. Loop until 'bd ready' returns zero ready issues
  Read AGENTS.md for project rules.
  Halt only on Phase 12 (deploy) for secrets.
"
```

**What the architect wrote instead (BROKEN):**

```
cd /media/bob/C/AI_Projects/LivingApp-Sidecar && hermes chat -s dev-team/vibe-loop --yolo -q "Pick up P0 work"
```

This completed ONE task (6dt) and stopped, leaving 24 issues idle for a day.

---

## Where This Lives

This pattern is enforced via BMAD agent persistent memories:

- Canonical file: `/media/bob/C/AI_Projects/hermes-dev-team/_bmad/custom/hermes-prompt-pattern.md`
- Referenced by: All BMAD agent customize.yaml files across all projects
- Any BMAD agent handing off work to Hermes will read this pattern

---

*Owner: Bob Banks*
*Enforced by: Hermes Agent global prompt pattern*
