---
name: skill-creation-trigger
description: "Post-task check: should this workflow become a skill? Run after complex tasks."
version: 1.0.0
metadata:
  hermes:
    tags: [meta, skills, workflow, learning]
---

# Skill Creation Trigger

A post-task checklist to decide whether to capture a workflow 
as a skill. Run this after any task with 5+ tool calls, after 
fixing a tricky bug, or after the user corrects your approach.

## THINK BEFORE ACTING (MANDATORY)

Before ANY fix, action, or change — pause and answer these questions:

1. **What is the ROOT CAUSE?** (not just the symptom)
2. **What is the MATH?** (display sizes, scale factors, dimensions, costs)
3. **What is the CONTEXT?** (where does this output appear? what is the display environment?)
4. **Have I VERIFIED?** (check the output BEFORE showing it to the user)

If you cannot answer all four, STOP and investigate before acting. Speed is not the goal — getting it RIGHT the first time is. Every quick fix that fails wastes the user time and trust.


## When to Use

- After completing a complex task (5+ tool calls)
- After the user says "we should remember this"
- After discovering a non-obvious solution
- After fixing a bug that took multiple attempts
- At the end of a session where new patterns emerged

## Decision Checklist

Ask yourself these questions. If ANY answer is YES, create a skill:

### 1. Repetition Check
- Have I done this exact type of task before in a past session?
- Would I do this again in the next 30 days?
- Does this involve steps I had to re-derive from memory?

### 2. Pitfall Check
- Did I hit non-obvious errors that took research to solve?
- Did the user correct my approach? What was the right way?
- Are there gotchas that would trip up a future session?

### 3. Complexity Check
- Did this require 5+ tool calls with reasoning between them?
- Did I need to coordinate multiple tools/files/systems?
- Would explaining this to another agent take 5+ paragraphs?

### 4. Knowledge Check
- Did I learn something about our specific projects/environments?
- Did I discover a tool quirk or workaround?
- Is there project-specific knowledge (not general programming)?

## How to Create the Skill

If the answer is YES to any of the above:

1. **Name it** — lowercase, hyphenated, action-oriented
   Good: `beads-decomposition`, `railway-deploy-checklist`
   Bad: `workflow-1`, `misc-notes`, `things-I-learned`

2. **Write the SKILL.md** with these sections:
   - When to Use (trigger conditions)
   - Steps (numbered, specific commands)
   - Pitfalls (what went wrong and how to avoid it)
   - Verification (how to confirm it worked)

3. **Use skill_manage(action='create')** to save it

4. **Tell the user** what you created and why

## Anti-Patterns (Do NOT Create Skills For)

- One-off tasks you'll never repeat (migrating a single file)
- General programming knowledge (how to write a for loop)
- Temporary debugging state ("test file at /tmp/foo")
- Tasks already covered by an existing skill (check first!)

## Integration with Daily Work

This skill should be loaded at the END of complex tasks. 
The agent checks the decision checklist and either:
- Creates a new skill (if warranted)
- Updates an existing skill (if it was missing steps/pitfalls)
- Does nothing (if the task was straightforward)

The goal is to accumulate knowledge over time so that 
future sessions don't rediscover what past sessions learned.
