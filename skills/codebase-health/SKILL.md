---
name: codebase-health
description: Run the check engine across all project source files and report convention violations, quality issues, and security findings
disable-model-invocation: false
---

# Codebase Health Check

Run the pipeline's check engine in full review mode across the entire project to assess codebase health against the plugin's convention rules.

## What to do

1. **Verify git repository:** Run `git rev-parse --show-toplevel` to get the project root. If not a git repo: report "Not a git repository." and stop.

2. **Discover source files:** Find all tracked source files:
   ```bash
   PROJECT_ROOT=$(git rev-parse --show-toplevel)
   SOURCE_FILES=$(git -C "$PROJECT_ROOT" ls-files --cached --others --exclude-standard | grep -E '\.(kt|kts|java|ts|tsx|js|jsx|py|go|rs|c|h|cs|csx|cpp|cc|cxx|hpp|swift|rb|php|dart|ex|exs|scala|sc)$')
   ```
   Count the files and report: "Found {count} source files to scan."

3. **Run the check engine:** Execute Layer 1 + Layer 2 checks on all discovered files:
   ```bash
   echo "$SOURCE_FILES" | while read -r f; do
     "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh" --review --project-root "$PROJECT_ROOT" --files-changed "$PROJECT_ROOT/$f"
   done
   ```
   If the engine script is not executable or not found: report "Check engine not available. Verify the dev-pipeline plugin is installed." and stop.

4. **Parse findings:** The engine outputs pipe-delimited findings:
   ```
   file:line | CATEGORY | SEVERITY | message | fix_hint
   ```
   Collect all output lines. Count findings by severity (CRITICAL, WARNING, INFO) and by category prefix (SEC-*, CONV-*, QUAL-*, PERF-*, ARCH-*, DESIGN-*).

5. **Calculate quality score:** Use the scoring formula: `100 - 20*CRITICAL - 5*WARNING - 2*INFO`. Determine verdict: PASS (>= 80), CONCERNS (60-79), FAIL (< 60 or any CRITICAL).

6. **Present the report:**

   ```
   ## Codebase Health Report

   **Project:** {project name from directory}
   **Files scanned:** {count}
   **Languages:** {language breakdown, e.g. "kotlin (98), typescript (44)"}

   ### Findings by Severity
   - CRITICAL: {count}
   - WARNING: {count}
   - INFO: {count}

   ### Findings by Category
   | Category        | CRITICAL | WARNING | INFO |
   |-----------------|----------|---------|------|
   | Security        | {n}      | {n}     | {n}  |
   | Conventions     | {n}      | {n}     | {n}  |
   | Code Quality    | {n}      | {n}     | {n}  |
   | Performance     | {n}      | {n}     | {n}  |
   | Architecture    | {n}      | {n}     | {n}  |

   ### Quality Score
   Score: {score}/100 ({verdict})

   ### Top Issues
   {list top 10 findings by severity, highest first}
   ```

   Map category prefixes to human-readable names:
   - `SEC-*` → Security
   - `CONV-*` → Conventions
   - `QUAL-*` → Code Quality
   - `PERF-*` → Performance
   - `ARCH-*`, `DESIGN-*` → Architecture

## Important
- Do NOT fix issues — only report them
- This runs Layer 1 (patterns) + Layer 2 (linters) across ALL files, which may take longer than hook-mode
- If you want to fix issues, run `/pipeline-run` or offer remediation options
- Save the full report to `.pipeline/health-report.md` for reference
