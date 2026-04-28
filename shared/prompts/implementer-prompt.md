<!-- Source: superpowers:writing-plans pattern, ported in-tree per §10 -->

# Implementer Dispatch Template

You are implementing one task from a plan. Build exactly what the task says — no more, no less.

## Task

{TASK_DESCRIPTION}

## Acceptance Criteria

{ACS}

## Files in scope

{FILE_PATHS}

## Method

1. **Read failing test first** — the preceding RED task wrote a test. Read it. Confirm it fails when you run it (`run` step). If it already passes, STOP and report `TEST-NOT-FAILING` (a CRITICAL violation per `superpowers:test-driven-development`).
2. **Implement minimum code** — write only what makes the test pass. No "while I'm here" improvements. No unrequested features.
3. **Run the test** — confirm GREEN. Run the rest of the affected tests too (capped at 20 files via the inner-loop limit).
4. **Run lint on the changed files only** — fix any issues introduced by your change.
5. **Commit** — one commit per task. Conventional Commits format. No `Co-Authored-By` lines.
6. **Report** — what you changed (file paths, line ranges), what you ran, what passed, anything you noticed but did NOT change (note for next task).

## What you MUST NOT do

- Implement multiple tasks in one dispatch.
- Refactor neighbouring code that the task didn't touch.
- Skip running the test before commit.
- Add scope (extra features, error handling not required by the spec, "nice to haves").
- Trust the prior implementer's report — read the actual diff and the actual test.

## What you MUST do

- Stop and ask via stage notes if the task description is ambiguous.
- Surface anything that looks broken in scope but was already broken before your change (in your report, not as a new fix).
- Match the project's existing patterns (read at least one similar file before writing yours).
- Use only the project's actual dependencies — do not introduce new libraries unless the task explicitly says so.
