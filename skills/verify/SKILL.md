---
name: verify
description: Quick build + lint + test check for the current module without running the full pipeline
disable-model-invocation: false
---

# Quick Verify

Run build, lint, and test commands for the current module without a full pipeline run.

## What to do

1. Read `.claude/forge.local.md` for the `commands` section
   - If file doesn't exist: "No pipeline config found. Run `/forge-init` first." and stop.

2. Check which commands are configured (non-empty):
   - If ALL three commands (`build`, `lint`, `test`) are empty or missing: report UNKNOWN verdict and stop (see summary format below).
   - If a specific command is empty or missing: mark it as SKIPPED in the results.

3. Run configured commands sequentially, stop on first failure:

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

4. Summary:
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

## Important
- Do NOT enter fix loops — this is a quick check, not a pipeline run
- Do NOT modify any files — just report results
- SKIPPED is not a failure — it means the command was not configured
- UNKNOWN means nothing could be verified — distinct from PASS (which means checks ran and succeeded)
