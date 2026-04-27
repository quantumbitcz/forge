---
name: forge-verify
description: "[read-only] Pre-pipeline checks. --build runs configured build+lint+test. --all runs --build then delegates to /forge-status --json for the config-validation section. Defaults to --build. Never modifies files. Use when you want a fast sanity check before committing, opening a PR, or kicking off a full pipeline run."
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep']
disable-model-invocation: false
---

# /forge-verify — Pre-Pipeline Checks

One skill, two checks. `--build` runs the configured build/lint/test commands; `--all` adds the config-validation section pulled from `/forge-status --json`. Both are read-only.

## Subcommand dispatch

Follow `shared/skill-subcommand-pattern.md`. This skill uses flags (the two checks are peer checks with a natural combinator).

**Dispatch rules:**

1. Read `$ARGUMENTS`.
2. Parse flags: `--build`, `--all`, `--json`, `--help`.
3. `--build`, `--all` are mutually exclusive. If more than one is present: `Only one of --build, --all may be specified.` exit 2.
4. If no mode flag: default is `--build`.
5. If `--help`: print usage and exit 0.
6. Dispatch:
   - `--build` → `### Subcommand: build`
   - `--all` → `### Subcommand: all` (build first, then embed `/forge-status --json` config_validation)

## Flags

- **--help**: print usage and exit 0
- **--json**: structured JSON output
- **--build**: run build + lint + test (default)
- **--all**: run --build, then embed `/forge-status --json` config_validation block in the combined report

## Exit codes

See `shared/skill-contract.md` §3.

## Shared prerequisites

Before any subcommand:

1. **Git repository:** `git rev-parse --show-toplevel 2>/dev/null`. If fails: "Not a git repository. Navigate to a project directory." STOP.
2. **Forge initialized:** `.claude/forge.local.md` exists. If not: "No pipeline config found. Run `/forge-init` first." STOP.

---

### Subcommand: build

Run build, lint, and test commands for the current module without a full pipeline run.

Read-only — does NOT modify any file.

#### Additional prerequisite

**Commands configured:** Read `.claude/forge.local.md` for the `commands` section. If ALL three commands (`build`, `lint`, `test`) are empty or missing: report UNKNOWN verdict with message "No build, lint, or test commands configured. Run `/forge-init` or add them to `.claude/forge.local.md`." and STOP.

#### Instructions

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

### Subcommand: all

Run `### Subcommand: build` first to produce the build/lint/test report. Then shell out `/forge-status --json` and parse the resulting JSON. Embed its top-level `config_validation` object as the config section of the combined report.

Read-only — does not modify any file. Config validation is owned by `/forge-status` (since Phase 2); this subcommand only consumes the JSON snapshot.

If `/forge-status --json` exits non-zero or returns no `config_validation` block, surface the error inline ("config validation snapshot unavailable: <reason>") and continue with the build report. Verdict logic for the combined report:

- **PASS**: build PASS + config_validation has zero FAIL constraints.
- **FAIL**: build FAIL or any config_validation constraint reports FAIL.
- **UNKNOWN**: build UNKNOWN and config snapshot unavailable.

## Error Handling

| Condition | Action |
|---|---|
| Shared prerequisites fail | Report specific error and STOP |
| Both --build and --all specified | "Only one of --build, --all may be specified." exit 2 |
| Build command fails | Report FAIL with error output. Do not proceed to lint/test |
| Lint command fails | Report FAIL with error output. Do not proceed to test |
| Test command fails | Report FAIL with error output and test failure details |
| Command not found on PATH | "Command not found: {cmd}. Install it or update `.claude/forge.local.md`." |
| Command times out | "Command timed out after {N} seconds. The build/test may be hanging." |
| `/forge-status --json` unavailable (--all) | Report "config validation snapshot unavailable: <reason>". Continue with build report. |

## Important

- NEVER enter fix loops — this is a quick check, not a pipeline run.
- NEVER modify files — not even `.forge/` state.
- SKIPPED is not a failure — it means the command was not configured.
- UNKNOWN means nothing could be verified (distinct from PASS).

## See Also

- `/forge-review --scope=changed` — Review and fix changed files
- `/forge-review --scope=all` — Full codebase audit (read-only)
- `/forge-run` — Full pipeline including verification
- `/forge-status` — Owns config validation snapshot (consumed by `--all`)
- `/forge-recover diagnose` — Diagnose runtime pipeline issues (complementary to config validation)
