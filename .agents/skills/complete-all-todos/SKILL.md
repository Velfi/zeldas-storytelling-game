---
name: complete-all-todos
description: Coordinate subagents to implement and verify every actionable work item described under ./docs/todo. Use when the user asks to complete, finish, execute, or work through all todo documents in that directory, especially when independent items can run in parallel across the repository.
---

# Complete All Todos

Complete the entire `./docs/todo` backlog by inventorying it, assigning bounded non-overlapping work to subagents, integrating results, and verifying the repository as a whole.

## Workflow

1. Read the repository's `AGENTS.md` instructions and relevant project documentation before delegating.
2. Resolve `./docs/todo` relative to the workspace root. Recursively inspect all files, including unchecked checkboxes and prose requirements.
3. If the directory is absent or contains no actionable work, report that fact and stop. Do not invent todos.
4. Build a checklist of concrete deliverables, acceptance criteria, likely files, dependencies, and verification commands. Treat ambiguous entries conservatively; inspect the codebase before deciding they are blocked.
5. Check the worktree and preserve unrelated user changes. Identify todo items that may touch the same files or APIs.
6. Group independent items into bounded assignments. Keep coupled items together and order prerequisite work before dependents.
7. Create subagents for assignments when slots are available. Give each agent:
   - the exact todo source and acceptance criteria;
   - explicit ownership boundaries;
   - relevant repository instructions;
   - a requirement to implement, test, and report changed files and remaining risks;
   - a warning not to overwrite or revert other agents' or the user's changes.
8. Continue useful coordinator work while agents run: inspect cross-cutting interfaces, prepare integration checks, or handle a tightly coupled item locally.
9. Review each result and diff. Reconcile overlaps deliberately. If work is incomplete or verification failed, send a focused follow-up to the same agent when practical.
10. Reuse freed agent slots for remaining assignments until every actionable item is implemented or genuinely blocked.
11. Run targeted tests for each item, then the broadest relevant repository checks. Diagnose and fix integration failures rather than treating agent completion messages as proof.
12. Re-read every todo document against the final tree. Update checkbox or status markers only when their stated acceptance criteria are satisfied. Preserve historical/contextual prose.
13. Finish only when all actionable todos are complete. If an item requires missing authority, credentials, external coordination, or a material product decision, report the exact blocker, evidence, and completed remainder.

## Coordination Rules

- Respect the runtime's agent concurrency limit; do not create more active agents than available slots.
- Prefer one agent per independent subsystem or coherent file set, not one agent per checkbox.
- Never assign two active agents overlapping write ownership without explicitly making one read-only.
- Share newly discovered interface constraints promptly with affected agents.
- Do not ask subagents to commit, push, delete broad paths, or perform external side effects unless the user explicitly requested those actions.
- Do not mark a todo complete merely because code was written. Require appropriate tests, builds, inspections, or artifact validation.
- Do not stop after the first delegation wave. Continue scheduling, integration, and verification until the backlog reaches a terminal state.

## Completion Report

Summarize completed todo items, important files changed, verification performed, and any genuine blockers. Keep the report tied to the todo documents rather than listing every internal coordination step.
