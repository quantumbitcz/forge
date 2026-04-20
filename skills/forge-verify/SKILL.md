---
name: forge-verify
description: "[read-only] Pre-pipeline checks. --build runs configured build+lint+test. --config validates forge.local.md and forge-config.md against PREFLIGHT constraints. --all runs both. Defaults to --build. Never modifies files."
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep']
disable-model-invocation: false
---

# /forge-verify — Pre-Pipeline Checks

One skill, two checks. `--build` runs the configured build/lint/test commands; `--config` validates configuration files. Both are read-only.

## Subcommand dispatch

Follow `shared/skill-subcommand-pattern.md`. This skill uses flags (the two checks are peer checks with a natural combinator).

**Dispatch rules:**

1. Read `$ARGUMENTS`.
2. Parse flags: `--build`, `--config`, `--all`, `--json`, `--help`.
3. `--build`, `--config`, `--all` are mutually exclusive. If more than one is present: `Only one of --build, --config, --all may be specified.` exit 2.
4. If no mode flag: default is `--build`.
5. If `--help`: print usage and exit 0.
6. Dispatch:
   - `--build` → `### Subcommand: build`
   - `--config` → `### Subcommand: config`
   - `--all` → `### Subcommand: all` (config first, then build)

## Flags

- **--help**: print usage and exit 0
- **--json**: structured JSON output
- **--build**: run build + lint + test (default)
- **--config**: validate forge.local.md and forge-config.md
- **--all**: run --config first, then --build (fail-fast if config invalid)

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

### Subcommand: config

Validate the project's forge configuration files before a pipeline run. Catches misconfigurations that would fail at PREFLIGHT or cause runtime errors deep in the pipeline.

Delegates schema validation to `${CLAUDE_PLUGIN_ROOT}/shared/validate-config.sh`, which is read-only (no writes, no touch/mkdir/tee — only stderr reporting). The script exits 0 (PASS), 1 (ERROR), or 2 (WARNING-only).

Read-only — validates files, never modifies them. Does NOT execute build/test/lint commands (only checks their first-word executables exist).

#### Instructions

##### Step 1: Locate Config Files

1. Check for `.claude/forge.local.md`.
   - If missing: report "No project config found. Run `/forge-init` to set up." and stop.
2. Read `.claude/forge.local.md` — parse the YAML frontmatter (between `---` delimiters).
3. Check for `.claude/forge-config.md`.
   - If missing: WARNING: "No forge-config.md found. Pipeline will use defaults. Run `/forge-init` to generate."
4. If `.claude/forge-config.md` exists: read and parse its markdown tables for parameter values.

##### Step 2: Required Fields (forge.local.md)

Check that these required fields exist in the YAML frontmatter. Report PASS or ERROR for each:

**components section:**
- `components.language` — must be one of: kotlin, java, typescript, python, go, rust, swift, c, csharp, ruby, php, dart, elixir, scala, cpp, or `null` (for k8s).
- `components.framework` — must be one of: spring, react, fastapi, axum, swiftui, vapor, express, sveltekit, k8s, embedded, go-stdlib, aspnet, django, nextjs, gin, jetpack-compose, kotlin-multiplatform, angular, nestjs, vue, svelte, or `null`.
- `components.testing` — must be one of: kotest, junit5, vitest, jest, pytest, go-testing, xctest, rust-test, xunit-nunit, testcontainers, playwright, cypress, cucumber, k6, detox, rspec, phpunit, exunit, scalatest. WARNING if missing (not all frameworks require explicit testing config).
- `components.variant` (if present) — must match a file in `${CLAUDE_PLUGIN_ROOT}/modules/frameworks/{framework}/variants/{value}.md`. WARNING if file not found.

**commands section:**
- `commands.build` — ERROR if missing or empty.
- `commands.test` — ERROR if missing or empty.
- `commands.lint` — WARNING if missing (some projects have no linter).

**conventions_file:**
- ERROR if missing.

##### Step 3: Value Range Checks (forge-config.md)

If `forge-config.md` exists, validate these parameters against PREFLIGHT constraints. Use defaults if a parameter is not set.

**Scoring:**
- `critical_weight`: must be >= 10. Default: 20.
- `warning_weight`: must be >= 1. Default: 5.
- `info_weight`: must be >= 0 and < `warning_weight`. Default: 2.
- `pass_threshold`: must be >= 60. Default: 80.
- `concerns_threshold`: must be >= 40. Default: 60.
- `pass_threshold` - `concerns_threshold`: must be >= 10.
- `oscillation_tolerance`: must be 0-20. Default: 5.
- `total_retries_max`: must be 5-30. Default: 10.

**Convergence:**
- `max_iterations`: must be 3-20. Default: 8.
- `plateau_threshold`: must be 0-10. Default: 2.
- `plateau_patience`: must be 1-5. Default: 2.
- `target_score`: must be >= `pass_threshold` and <= 100. Default: 90.

**Sprint (if configured):**
- `sprint.poll_interval_seconds`: must be 10-120. Default: 30.
- `sprint.dependency_timeout_minutes`: must be 5-180. Default: 60.

**Tracking:**
- `tracking.archive_after_days`: must be 30-365 or 0 (disabled). Default: 90.

**Shipping (if configured):**
- `shipping.min_score`: must be >= `pass_threshold` and <= 100. Default: 90.
- `shipping.evidence_max_age_minutes`: must be 5-60. Default: 30.

**Scope/Routing:**
- `decomposition_threshold`: must be 2-10. Default: 3.
- `routing.vague_threshold`: must be one of: low, medium, high. Default: medium.

##### Step 4: File Reference Checks

For each conventions file reference in `forge.local.md`, verify the target file exists:

- `conventions_file` — resolve `${CLAUDE_PLUGIN_ROOT}` to the plugin root. ERROR if file not found.
- `conventions_variant` — resolve variables (`${components.variant}`). WARNING if file not found (variant may be optional).
- `conventions_testing` — resolve variables (`${components.testing}`). WARNING if file not found.
- `conventions_web` — resolve variables. WARNING if file not found (not all frameworks have web variants).
- `conventions_persistence` — resolve variables. WARNING if file not found (not all frameworks have persistence variants).
- `language_file` — resolve variables. ERROR if file not found.
- `preempt_file` — check existence of `.claude/forge-log.md`. WARNING if not found.
- `config_file` — check existence of `.claude/forge-config.md`. WARNING if not found.

**Resolution:** Replace `${CLAUDE_PLUGIN_ROOT}` with the actual plugin root path (look for the forge plugin in `.claude/plugins/` or the current directory if running from within the plugin). Replace `${components.X}` with the actual value from the `components` section.

##### Step 5: Command Executability

For each command in the `commands` section, run a quick check (do NOT execute the command itself):

- **build:** Check that the first word of the command is an executable on PATH or a local script.
  - e.g., for `./gradlew build -x test`: check that `./gradlew` exists and is executable.
  - e.g., for `npm run build`: check that `npm` is on PATH.
- **test:** Same check.
- **lint:** Same check (if configured).
- **format:** Same check (if configured).

Report PASS or WARNING for each. Do NOT run the actual commands.

##### Step 6: Cross-Reference Checks

**Agent references:**
- If `quality_gate` section exists, check that each `agent:` reference matches an existing agent file in the plugin's `agents/` directory. WARNING for unknown agents (may be from other plugins).

**Code quality tools:**
- If `code_quality` list is non-empty, check that each tool has a corresponding module file at `modules/code-quality/{tool}.md`. WARNING for unknown tools.

**Framework-component compatibility:**
- If `components.framework` is `k8s`, then `components.language` should be `null`. WARNING if not.
- If `components.framework` is `go-stdlib`, then `components.language` should be `go`. WARNING if not.
- If `components.framework` is `embedded`, then `components.language` should be `c` or `cpp`. WARNING if not.

##### Step 7: Report

Present results in this format:

```
## Config Validation Report

**forge.local.md:** .claude/forge.local.md
**forge-config.md:** {found/not found}

### Required Fields
| Field | Status | Value |
|-------|--------|-------|
| components.language | PASS/ERROR | {value} |
| components.framework | PASS/ERROR | {value} |
| components.testing | PASS/WARNING | {value} |
| commands.build | PASS/ERROR | {value} |
| commands.test | PASS/ERROR | {value} |
| commands.lint | PASS/WARNING | {value} |
| conventions_file | PASS/ERROR | {value} |

### Value Ranges (forge-config.md)
| Parameter | Value | Range | Status |
|-----------|-------|-------|--------|
| total_retries_max | {n} | 5-30 | PASS/ERROR |
| ... | ... | ... | ... |

### File References
| Reference | Target | Status |
|-----------|--------|--------|
| conventions_file | {resolved_path} | PASS/ERROR |
| ... | ... | ... |

### Command Executability
| Command | Executable | Status |
|---------|-----------|--------|
| build | {cmd} | PASS/WARNING |
| test | {cmd} | PASS/WARNING |
| lint | {cmd} | PASS/WARNING |

### Cross-References
- {check}: {status}

### Summary
- {errors} errors, {warnings} warnings
- {recommendation}
```

**Recommendations:**
- 0 errors: "Configuration is valid. Ready for `/forge-run`."
- Errors in required fields: "Fix the required field errors before running the pipeline."
- Errors in file references: "Referenced convention files are missing. Re-run `/forge-init` or fix paths manually."
- Errors in value ranges: "Parameter values are out of PREFLIGHT constraints. Fix in `.claude/forge-config.md`."

#### Validation Engine

Delegates to `${CLAUDE_PLUGIN_ROOT}/shared/validate-config.sh` for:
- Component enum validation with fuzzy matching
- Framework+language compatibility checks
- PREFLIGHT constraint bounds checking
- File existence validation for variant/testing/persistence bindings

The script exits 0 (PASS), 1 (ERROR), or 2 (WARNING only).

### Subcommand: all

Run `config` first. If config validation reports ERROR (non-zero exit from `validate-config.sh` or any required-field ERROR): report "Config validation failed — skipping build check. Fix config errors first." and exit 1. **Do not run build** — running build commands against a broken config produces misleading results.

If config validation passes (or reports only WARNINGs): proceed to run `build`. Combine both reports into a single output.

## Error Handling

| Condition | Action |
|---|---|
| Shared prerequisites fail | Report specific error and STOP |
| Both --build and --config specified | "Only one of --build, --config, --all may be specified." exit 2 |
| Build command fails | Report FAIL with error output. Do not proceed to lint/test |
| Lint command fails | Report FAIL with error output. Do not proceed to test |
| Test command fails | Report FAIL with error output and test failure details |
| Command not found on PATH | "Command not found: {cmd}. Install it or update `.claude/forge.local.md`." |
| Command times out | "Command timed out after {N} seconds. The build/test may be hanging." |
| forge.local.md YAML parse failure (config) | "Could not parse YAML frontmatter in forge.local.md. Check syntax." STOP |
| validate-config.sh exits 1 (config) | Report ERRORs, exit 1 |
| validate-config.sh exits 2 (config WARN only) | Report WARNINGs, exit 0 |
| Plugin root not found (config) | "Could not locate forge plugin root. File reference checks skipped." |

## Important

- NEVER enter fix loops — this is a quick check, not a pipeline run.
- NEVER modify files — not even `.forge/` state.
- SKIPPED is not a failure — it means the command was not configured.
- UNKNOWN means nothing could be verified (distinct from PASS).

## See Also

- `/forge-review --scope=changed` — Review and fix changed files
- `/forge-review --scope=all` — Full codebase audit (read-only)
- `/forge-run` — Full pipeline including verification
- `/forge-recover diagnose` — Diagnose runtime pipeline issues (complementary to config validation)
