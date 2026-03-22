---
name: codebase-health
description: Run the check engine in full review mode and report all findings across all layers
disable-model-invocation: false
---

# Codebase Health Check

Run the pipeline's check engine outside of a pipeline run to assess codebase health.

## What to do

1. Find the check engine script (it's in the plugin directory):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --review
   ```

2. If the engine script is not executable or not found:
   - Report: "Check engine not available. Verify the dev-pipeline plugin is installed."

3. Parse the engine output and report:
   ```
   ## Codebase Health Report

   **Module:** {detected module}
   **Files checked:** {count}

   ### Findings by Layer
   - Layer 1 (Fast patterns): {count} findings
   - Layer 2 (Linter): {count} findings
   - Layer 3 (Agent): not yet implemented

   ### Findings by Severity
   - CRITICAL: {count}
   - WARNING: {count}
   - INFO: {count}

   ### Quality Score
   Score: {100 - 20*C - 5*W - 2*I}/100

   ### Top Issues
   {list top 10 findings by severity}
   ```

## Important
- Do NOT fix issues — only report them
- This runs ALL layers, which may take longer than the hook-mode check
- If you want to fix issues, run `/pipeline-run` instead
