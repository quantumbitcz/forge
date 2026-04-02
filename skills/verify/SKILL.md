---
name: verify
description: Quick build + lint + test check for the current module without running the full pipeline
disable-model-invocation: false
---

# Quick Verify

Run build, lint, and test commands for the current module without a full pipeline run.

## What to do

1. Read `.claude/forge.local.md` for the `commands` section
   - If file doesn't exist: "No pipeline config found. Run `/forge-init` first."

2. Run commands sequentially, stop on first failure:

   **Build:**
   ```bash
   {commands.build}
   ```
   Report: PASS or FAIL with error output

   **Lint:**
   ```bash
   {commands.lint}
   ```
   Report: PASS or FAIL with error output

   **Test:**
   ```bash
   {commands.test}
   ```
   Report: PASS or FAIL with error output and test count

3. Summary:
   ```
   ## Verify Results
   - Build: PASS/FAIL
   - Lint: PASS/FAIL
   - Test: PASS/FAIL ({N} tests)
   ```

## Important
- Do NOT enter fix loops — this is a quick check, not a pipeline run
- Do NOT modify any files — just report results
- If a command is empty or missing in config, skip it with a note
