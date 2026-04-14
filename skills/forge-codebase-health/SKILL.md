---
name: forge-codebase-health
description: "Analyze full codebase against quality rules (read-only, no fixes). Runs check engine on all source files. Use when you want a quality baseline before starting work, after merging multiple PRs, or to audit convention compliance without making changes."
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep']
disable-model-invocation: false
---

# /forge-codebase-health -- Codebase Health Check

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.

Run the pipeline's check engine in full review mode across the entire project to assess codebase health against the plugin's convention rules.

## Instructions

1. **Discover source files:** Find all tracked source files:
   ```bash
   PROJECT_ROOT=$(git rev-parse --show-toplevel)
   SOURCE_FILES=$(git -C "$PROJECT_ROOT" ls-files --cached --others --exclude-standard | grep -E '\.(kt|kts|java|ts|tsx|js|jsx|py|go|rs|c|h|cs|csx|cpp|cc|cxx|hpp|swift|rb|php|dart|ex|exs|scala|sc)$')
   ```
   Count the files and report: "Found {count} source files to scan."

2. **Run the check engine:** Execute Layer 1 + Layer 2 checks on all discovered files:
   ```bash
   echo "$SOURCE_FILES" | while read -r f; do
     "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh" --review --project-root "$PROJECT_ROOT" --files-changed "$PROJECT_ROOT/$f"
   done
   ```
   If the engine script is not executable or not found: report "Check engine not available. Verify the forge plugin is installed." and stop.

3. **Parse findings:** The engine outputs pipe-delimited findings:
   ```
   file:line | CATEGORY | SEVERITY | message | fix_hint
   ```
   Collect all output lines. Count findings by severity (CRITICAL, WARNING, INFO) and by category prefix (ARCH-*, SEC-*, PERF-*, TEST-*, CONV-*, DOC-*, QUAL-*, FE-PERF-*, APPROACH-*, A11Y-*, DEP-*, COMPAT-*).

4. **Calculate quality score:** Use the scoring formula: `max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)`. Determine verdict: PASS (>= 80), CONCERNS (60-79), FAIL (< 60 or any CRITICAL).

5. **Present the report:**

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
   | Category           | CRITICAL | WARNING | INFO |
   |--------------------|----------|---------|------|
   | Architecture       | {n}      | {n}     | {n}  |
   | Security           | {n}      | {n}     | {n}  |
   | Performance        | {n}      | {n}     | {n}  |
   | Test Quality       | {n}      | {n}     | {n}  |
   | Conventions        | {n}      | {n}     | {n}  |
   | Documentation      | {n}      | {n}     | {n}  |
   | Code Quality       | {n}      | {n}     | {n}  |
   | Frontend Perf      | {n}      | {n}     | {n}  |
   | Approach           | {n}      | {n}     | {n}  |
   | Accessibility      | {n}      | {n}     | {n}  |
   | Dependencies       | {n}      | {n}     | {n}  |
   | Compatibility      | {n}      | {n}     | {n}  |

   ### Quality Score
   Score: {score}/100 ({verdict})

   ### Top Issues
   {list top 10 findings by severity, highest first}
   ```

   Map category prefixes to human-readable names:
   - `ARCH-*` -> Architecture
   - `SEC-*` -> Security
   - `PERF-*` -> Performance
   - `TEST-*` -> Test Quality
   - `CONV-*` -> Conventions
   - `DOC-*` -> Documentation
   - `QUAL-*` -> Code Quality
   - `FE-PERF-*` -> Frontend Perf
   - `APPROACH-*` -> Approach
   - `A11Y-*` -> Accessibility
   - `DEP-*` -> Dependencies
   - `COMPAT-*` -> Compatibility
   - `SCOUT-*` -> omit from table (no deduction, tracked separately)

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| Check engine not found or not executable | Report "Check engine not available. Verify the forge plugin is installed." and STOP |
| Check engine times out on a file | Skip the file, log WARNING, continue scanning remaining files |
| No source files found | Report "No source files found in the repository." and STOP |
| Engine produces unparseable output | Skip malformed lines, log WARNING, continue with valid findings |
| State corruption | This skill does not depend on state.json -- it runs independently |

## Important

- Do NOT fix issues -- only report them
- This runs Layer 1 (patterns) + Layer 2 (linters) across ALL files, which may take longer than hook-mode
- If you want to fix issues, run `/forge-deep-health` or offer remediation options
- Save the full report to `.forge/health-report.md` for reference

## See Also

- `/forge-deep-health` -- Iteratively fix all codebase quality issues (use when you want fixes, not just a report)
- `/forge-review` -- Review and fix only recently changed files
- `/forge-verify` -- Quick build + lint + test check without convention scanning
- `/forge-security-audit` -- Focused security vulnerability scanning
