---
name: verify
description: "Quick build + lint + test check for the current module without running the full pipeline. Use when you want to confirm nothing is broken after manual code changes, before starting a pipeline run to check baseline health, or as a pre-commit sanity check."
disable-model-invocation: false
---

# /verify -- Quick Verify

Run build, lint, and test commands for the current module without a full pipeline run.

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "No pipeline config found. Run `/forge-init` first." and STOP.
3. **Commands configured:** Read `.claude/forge.local.md` for the `commands` section. If ALL three commands (`build`, `lint`, `test`) are empty or missing: report UNKNOWN verdict with message "No build, lint, or test commands configured. Cannot verify. Run `/forge-init` to configure commands or add them to `.claude/forge.local.md` under the `commands:` section." and STOP.

## Instructions

1. Check which commands are configured (non-empty):
   - If a specific command is empty or missing: mark it as SKIPPED in the results.

2. Run configured commands sequentially, stop on first failure:

   **Build** (if `commands.build` is configured):
   ```bash
   {commands.build}
   ```
   Report: PASS or FAIL with error output

   **Lint** (if `commands.lint` is configured):
   ```bash
   {commands.lint}
   ```
   Report: PASS or FAIL with error output

   **Test** (if `commands.test` is configured):
   ```bash
   {commands.test}
   ```
   Report: PASS or FAIL with error output and test count

3. Summary:
   ```
   ## Verify Results
   - Build: PASS/FAIL/SKIPPED
   - Lint: PASS/FAIL/SKIPPED
   - Test: PASS/FAIL/SKIPPED ({N} tests)
   - Verdict: PASS/FAIL/UNKNOWN
   ```

   **Verdict logic:**
   - **PASS**: All configured commands succeeded (SKIPPED commands don't count against).
   - **FAIL**: Any configured command failed.
   - **UNKNOWN**: Zero commands were configured. Report: "No build, lint, or test commands configured. Cannot verify. Run `/forge-init` to configure commands or add them to `.claude/forge.local.md` under the `commands:` section."

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| Build command fails | Report FAIL with error output. Do not proceed to lint or test |
| Lint command fails | Report FAIL with error output. Do not proceed to test |
| Test command fails | Report FAIL with error output and any test failure details |
| Command not found on PATH | Report "Command not found: {cmd}. Install it or update the command in `.claude/forge.local.md`." |
| Command times out | Report "Command timed out after {N} seconds. The build/test may be hanging." |
| forge.local.md unparseable | Report "Could not parse forge.local.md. Check YAML frontmatter syntax." and STOP |

## Important

- Do NOT enter fix loops -- this is a quick check, not a pipeline run
- Do NOT modify any files -- just report results
- SKIPPED is not a failure -- it means the command was not configured
- UNKNOWN means nothing could be verified -- distinct from PASS (which means checks ran and succeeded)

## See Also

- `/forge-review` -- Review and fix changed files using forge review agents
- `/codebase-health` -- Full codebase scan against convention rules (read-only)
- `/deep-health` -- Iteratively fix all codebase quality issues
- `/forge-run` -- Full pipeline including verification as part of the workflow
