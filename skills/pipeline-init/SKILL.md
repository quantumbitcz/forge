---
name: pipeline-init
description: Auto-configures a project for the dev-pipeline. Detects tech stack, generates config files, runs health scan, discovers related repos. Zero-config setup.
---

# /pipeline-init — Zero-Config Project Setup

You are the pipeline initializer. Your job is to detect a project's tech stack, generate the correct configuration files, validate the setup, and optionally run a health scan. Be conversational — show what you find, ask for confirmation before writing files.

## Instructions

Work through these phases in order. Do NOT skip ahead — each phase builds on the previous one.

---

### Phase 1: DETECT

#### Pre-Validation

Before scanning for stack markers, verify the environment is ready:

1. **Git repository check**: Run `git rev-parse --show-toplevel`
   - If it fails: **ERROR** — "Not a git repository. Initialize with `git init` first." Abort.
2. **Config directory check**: Verify `.claude/` directory exists and is writable.
   - If it does not exist, it will be created in the CONFIGURE phase — this is fine, just note it.
   - If it exists but is not writable: **ERROR** — "`.claude/` directory is not writable. Check permissions." Abort.
3. **Existing config check**: Check whether `.claude/dev-pipeline.local.md` already exists.
   - If it exists: **ASK** — "Found existing `dev-pipeline.local.md`. Overwrite? (y/n)"
   - If the user says no: abort with message "Keeping existing configuration."
   - If the user says yes: proceed, and the CONFIGURE phase will overwrite the file.

#### Stack Detection

Scan the project root and immediate subdirectories for stack markers. Check for the **first match** in this priority order:

| Markers | Module |
|---------|--------|
| `build.gradle.kts` + Kotlin source files (`*.kt`) | `spring` |
| `build.gradle.kts` + Java source files (`*.java`) | `spring` |
| `package.json` + `vite.config.*` + react dependency | `react` |
| `package.json` + `svelte.config.*` | `sveltekit` |
| `package.json` (no framework markers above) | `express` |
| `Cargo.toml` | `axum` |
| `go.mod` | `go-stdlib` |
| `pyproject.toml` + fastapi dependency | `fastapi` |
| `Package.swift` + Vapor dependency | `vapor` |
| `*.xcodeproj` | `swiftui` |
| `Makefile` + `*.c` source files | `embedded` |

#### Ambiguity Resolution

If module detection is ambiguous — for example, both `build.gradle.kts` and `package.json` exist in the project root or subdirectories, matching multiple modules — do NOT guess. Instead:

1. **ASK ONE question**: "Detected multiple frameworks: {list with matched modules}. Which is the primary module for pipeline configuration?"
2. Use the user's answer as the primary module for all config generation.
3. Note the other detected frameworks in the config's `related_modules` field for future multi-module support.

If detection is unambiguous (only one module matches), proceed without asking.

#### Supplementary Detection

Also detect and note the presence of:
- **Docker**: `docker-compose.yml`, `docker-compose.yaml`, `Dockerfile`
- **CI/CD**: `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`, `bitbucket-pipelines.yml`
- **Test framework**: JUnit, Jest, Vitest, pytest, go test, cargo test, XCTest, etc.
- **OpenAPI spec**: `openapi.yaml`, `openapi.json`, `swagger.yaml`, `swagger.json` (search recursively)

#### Code Quality Tool Detection

Scan for configured code quality tools by checking for config files:

**Linting/Analysis:** `.detekt.yml` → detekt, `.editorconfig` with `ktlint_*` → ktlint, `eslint.config.*` or `.eslintrc.*` or `eslintConfig` in `package.json` → eslint, `biome.json` or `biome.jsonc` → biome, `ruff.toml` or `[tool.ruff]` in `pyproject.toml` → ruff, `.golangci.yml` → golangci-lint, `clippy.toml` → clippy, `.swiftlint.yml` → swiftlint, `.credo.exs` → credo, `.rubocop.yml` → rubocop, `phpstan.neon` → phpstan, `analysis_options.yaml` → dart-analyzer, `.scalafmt.conf` → scalafmt, `.scalafix.conf` → scalafix, roslyn analyzer packages in `.csproj` → roslyn-analyzers, `checkstyle.xml` → checkstyle, `pmd.xml` or `ruleset.xml` → pmd, `spotbugs-exclude.xml` → spotbugs, `errorprone` in `build.gradle.kts` → errorprone, `.pylintrc` or `pylintrc` → pylint, `mypy.ini` or `.mypy.ini` → mypy

**Formatting:** `.prettierrc.*` or `prettier` key in `package.json` → prettier, `[tool.black]` in `pyproject.toml` → black, `spotless` in `build.gradle.kts` → spotless, `rustfmt.toml` → rustfmt

**Coverage:** `jacoco` in build files → jacoco, `nyc` or `c8` config → istanbul, `[tool.coverage]` in `pyproject.toml` or `.coveragerc` → coverage-py, `coverlet` in `.csproj` → coverlet

**Security:** `dependencyCheck` in build files → owasp-dependency-check, `.snyk` → snyk, `.trivy.yaml` → trivy

Present detected tools in the summary table.

#### Documentation Detection

Scan for documentation files beyond OpenAPI:
- **Markdown docs**: Count `.md` files in `docs/`, `documentation/`, `wiki/`, `guides/` directories
- **ADRs**: Check for `adr/`, `docs/adr/`, `docs/decisions/` directories; count files matching `NNN-*.md` or `ADR-*.md`
- **Runbooks**: Check for files/dirs named `runbook`, `playbook`, `operations`
- **Changelogs**: Check for `CHANGELOG.md`, `CHANGES.md`, `HISTORY.md`
- **Architecture docs**: Check for files named `architecture.md`, `design.md`, `technical.md`
- **External references**: Scan top-level markdown files for URLs pointing to Confluence, Notion, or wiki platforms

Add to the summary table:

```
Documentation:      {N} files ({breakdown by type})
External docs:      {list or "none detected"}
```

Present findings in a clear summary table:

```
Detected stack:     react
Module:             modules/frameworks/react
Package manager:    pnpm
Test framework:     Vitest
Code quality:       ESLint (lint), Prettier (format), istanbul (coverage)
Docker:             docker-compose.yml (3 services)
CI/CD:              GitHub Actions (2 workflows)
OpenAPI:            docs/openapi.yaml
Documentation:      14 files (3 ADRs, 1 OpenAPI, 2 runbooks, 8 guides)
External docs:      Confluence (2 spaces referenced)
```

Ask the user: **"Does this look correct? Should I proceed with the `{module}` module?"**

Wait for confirmation before continuing. If the user corrects something, adjust accordingly.

#### Documentation Sources Prompt

After stack confirmation, if any documentation files were detected, ask:

> "Found {N} documentation files. Are there additional docs I should know about? (external wikis, Confluence spaces, Notion pages, shared drives) You can also add these later — the pipeline picks up new docs automatically on each run."

If the user provides URLs or paths:
- Store them for inclusion in the `documentation.external_sources` array during Phase 2 configuration.
- Accept any format: URLs, file paths, or just descriptions.

If the user says no or skips: proceed without additional sources.

---

### Phase 1.5: Code Quality Recommendations

#### Code Quality Recommendations

1. Compare detected tools against `code_quality_recommended` from framework's `local-template.md`
2. Present missing tools with descriptions, offer: `all / pick / skip`
3. For overlapping tools (prettier vs biome, eslint vs biome, owasp vs snyk vs trivy), present as alternatives
4. After selection, ask about external rulesets (default baseline / custom rules / shared config from external repo)
5. Ask about CI/CD integration: `Also configure these tools in your CI/CD pipeline? (yes / no)`

---

### Phase 2: CONFIGURE

Once confirmed, generate the configuration files:

1. **Read the module template**: Read `${CLAUDE_PLUGIN_ROOT}/modules/frameworks/{detected_module}/local-template.md` to get the template content.

2. **Fill in detected values**: Replace template placeholders with detected project-specific values:
   - Build command (e.g., `./gradlew build -x test`, `pnpm build`, `cargo build`)
   - Test command (e.g., `./gradlew test`, `pnpm test`, `cargo test`)
   - Lint command (if linters detected)
   - Format command (if formatter detected)
   - Adjust module paths if the project uses a monorepo structure

3. **Write config files**:
   - Copy filled template to `.claude/dev-pipeline.local.md`
   - If `${CLAUDE_PLUGIN_ROOT}/modules/frameworks/{detected_module}/pipeline-config-template.md` exists, copy it to `.claude/pipeline-config.md`
   - Create `.claude/pipeline-log.md` with this content:
     ```
     # Pipeline Log

     Accumulated learnings from pipeline runs. Updated automatically by the retrospective agent.
     ```

4. **Code Quality Scaffolding**: For each accepted tool from Phase 1.5:
   - **Project setup:** Add build dependency, generate baseline config, wire into build commands
   - **CI/CD setup (if accepted):** Add pipeline steps for linting, coverage reports, threshold enforcement
   - Config patterns sourced from `modules/code-quality/{tool}.md` → Installation & Setup and CI Integration sections
   - Do NOT modify existing configs, force declined tools, or scaffold conflicting tools without resolution
   - Record accepted tools in the `code_quality` list in `dev-pipeline.local.md` (simple string form `- jacoco` or object form with external ruleset `- tool: detekt\n  ruleset:\n    type: external\n    source: "..."`)

5. **Documentation config**: If the module's `local-template.md` includes a `documentation:` section (all modules now do), populate detected values:
   - Set `external_sources` from any URLs the user provided in the documentation prompt
   - The `auto_generate` defaults come from the template — no detection-based overrides needed

6. **Create `.claude/` directory** if it does not exist. Never overwrite existing files without asking first — if any config file already exists, show a diff of what would change and ask for confirmation.

Show the user what files were created and their key settings. Ask: **"Config files written. Want me to validate the setup?"**

---

### Phase 2b: CROSS-REPO DISCOVERY

After generating the project config, run the discovery chain to find related projects automatically.

1. **Run discovery script:**
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/shared/discovery/discover-projects.sh" "$(pwd)" --depth 4
   ```

   This scans in order: in-project references (docker-compose.yml, .env files, CI workflow references), sibling directories (same parent, compatible stack markers), IDE project directories (all JetBrains IDEs, VS Code, Cursor, Windsurf, Zed, Xcode, Eclipse, NetBeans, Visual Studio — plus platform-specific paths for macOS, Linux, and Windows including Documents, drive roots, and XDG dirs), and GitHub org repos (if `gh` CLI is authenticated).

2. **Present discoveries to user:**
   Show what was found and ask for confirmation:
   ```
   ## Discovered Related Projects

   OK  project-fe (frontend, react) at ../project-fe  [via sibling-directory]
   OK  project-infra (infra, k8s) at ../project-infra  [via docker-compose.yml]
   ?   project-mobile — not found

   Add these to your config? (y/n/edit)
   ```

   - `OK` — path exists and is a valid git repository
   - `?` — referenced but not found on disk (show as informational only, do not add)

3. **If user confirms (y):** Add `related_projects:` section to `dev-pipeline.local.md`:
   ```yaml
   related_projects:
     frontend:
       path: "/absolute/path/to/project-fe"
       repo: "github.com/org/project-fe"
       framework: react
       detected_via: "sibling-directory"
     infra:
       path: "/absolute/path/to/project-infra"
       repo: "github.com/org/project-infra"
       framework: k8s
       detected_via: "docker-compose.yml"
   ```

   Always use absolute paths in config. Detect the `framework` for each related project using the same stack-marker logic from Phase 1.

4. **If user wants to edit (edit):** Present each discovered project as an editable entry. Allow the user to:
   - Change the path for any entry
   - Remove entries they don't want
   - Add additional entries not found by discovery
   Write the final confirmed set to config.

5. **If user declines (n):** Skip silently. The pipeline works without related projects. Do not add `related_projects:` to config.

6. **If discovery script is not found** (plugin not fully installed, first-time setup): skip this step silently with an INFO note — "Discovery script not available. You can add related projects manually to `dev-pipeline.local.md`."

7. **Add discovery config** to `dev-pipeline.local.md` when any related projects are written:
   ```yaml
   discovery:
     enabled: true
     scan_depth: 4
     confirmation_required: true
   ```

---

### Phase 3: VALIDATE

Run the following checks to confirm the setup works. Execute BOTH build and test commands explicitly — do not skip either.

1. **Build check**: Run the exact `commands.build` value from the generated config (e.g., `./gradlew build -x test`, `pnpm build`).
   - If it **fails**: report the exact error — "Build command failed: `{command}`. Error: {output}. Fix the build before running the pipeline."
   - Ask whether to continue or fix first. A failing build is a hard blocker for the pipeline.

2. **Test check**: Run the exact `commands.test` value from the generated config (e.g., `./gradlew test`, `pnpm test`).
   - If it **fails**: report the exact error — "Test command failed: `{command}`. Error: {output}. This might be OK for a new project with no tests yet — the pipeline will generate tests."
   - A failing test command is NOT a hard blocker — note the failure and continue if the user agrees.

3. **Engine check**: Run `${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --verify` if the script exists. Report result.

If any check fails:
- Show the error output
- Suggest a fix if obvious
- Ask whether to continue or fix first

Report results:

```
Validation Results:
  Build:   PASS (12.3s)
  Tests:   PASS (47 passed, 0 failed, 2 skipped)
  Engine:  PASS
```

#### Post-Validation: Engine Verify

After successful validation, verify the check engine works with the detected module:

```bash
${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --verify --project-root "${PROJECT_ROOT}" --files-changed "."
```

- If the verify **fails**: **WARN** — "Check engine verify failed. Hook-based checks may not work. Error: {output}". This is a warning, not a blocker — continue to the next phase.
- If the verify **passes**: Report — "Check engine verified — hooks will run on every file edit."

---

### Phase 4: BASELINE AUDIT

Run a three-tier audit to check the codebase against the plugin's convention rules. Step 1 is mandatory; Steps 2 and 3 are prompted.

#### Step 1: Convention Scan (mandatory)

This step always runs — no user prompt. It takes under 5 seconds.

1. **Discover source files:**
   ```bash
   PROJECT_ROOT=$(git rev-parse --show-toplevel)
   SOURCE_FILES=$(git -C "$PROJECT_ROOT" ls-files --cached --others --exclude-standard | grep -E '\.(kt|kts|java|ts|tsx|js|jsx|py|go|rs|c|h|cs|csx|cpp|cc|cxx|hpp|swift|rb|php|dart|ex|exs|scala|sc)$')
   FILE_COUNT=$(echo "$SOURCE_FILES" | wc -l | tr -d ' ')
   ```

2. **Run Layer 1 + Layer 2 checks** on all discovered files:
   ```bash
   echo "$SOURCE_FILES" | while read -r f; do
     "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh" --review --project-root "$PROJECT_ROOT" --files-changed "$PROJECT_ROOT/$f"
   done
   ```

3. **Parse and present findings.** Count by severity and category. Calculate quality score: `max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)`.

   Display:
   ```
   Convention Scan Results:
     Files scanned:    {count}
     Languages:        {breakdown}

     | Category        | CRITICAL | WARNING | INFO |
     |-----------------|----------|---------|------|
     | Security        | {n}      | {n}     | {n}  |
     | Conventions     | {n}      | {n}     | {n}  |
     | Code Quality    | {n}      | {n}     | {n}  |
     | Performance     | {n}      | {n}     | {n}  |
     | Architecture    | {n}      | {n}     | {n}  |

     Quality Score: {score}/100 ({PASS|CONCERNS|FAIL})
   ```

   If any CRITICAL findings exist, list them immediately:
   ```
   CRITICAL findings (must fix before pipeline runs):
     1. src/config/AppConfig.kt:15 | SEC-CRED | Possible hardcoded credential detected.
   ```

4. **Save report** to `.pipeline/baseline-report.md` with all findings grouped by severity. This file is always written regardless of what the user chooses next.

   Map category prefixes: `ARCH-*` → Architecture, `SEC-*` → Security, `PERF-*` → Performance, `TEST-*` → Test Quality, `CONV-*` → Conventions, `DOC-*` → Documentation, `QUAL-*` → Code Quality, `FE-PERF-*` → Frontend Perf, `APPROACH-*` → Approach, `A11Y-*` → Accessibility, `DEPS-*` → Dependencies, `COMPAT-*` → Compatibility. `SCOUT-*` findings have no deduction.

#### Step 2: Deeper Analysis (optional)

Ask: **"Want me to also run linters and dependency audit? This uses your project's configured linters and checks for known vulnerabilities."**

If the user accepts:

1. **Linter run**: Run linter/check commands on all source files using the detected linters from Phase 1. If no linters are configured, note this as a recommendation.

2. **Dependency audit**: Run the appropriate audit tool:
   - `npm audit` / `pnpm audit` / `yarn audit` (Node.js)
   - `cargo audit` (Rust — install if missing)
   - `pip-audit` (Python — install if missing)
   - `./gradlew dependencyCheckAnalyze` (JVM — if OWASP plugin present)
   - `govulncheck ./...` (Go — if installed)
   - Note if no audit tool is available

3. **Append findings** to the report and update the summary table.

If declined, skip silently.

#### Step 3: Deep Convention Analysis (optional)

Ask: **"Want me to run a deep convention analysis? This uses AI to check your code against all language and framework best practices (logging patterns, error handling, async conventions). It takes longer but catches issues that pattern matching can't."**

If the user accepts:

1. **Load conventions:** Read the detected language module from `${CLAUDE_PLUGIN_ROOT}/modules/languages/{detected_language}.md` and the framework module from `${CLAUDE_PLUGIN_ROOT}/modules/frameworks/{detected_module}/conventions.md`.

2. **Select representative files:** Choose up to 20 source files, prioritizing:
   - Application entry points (main, Application, index)
   - Service/use-case classes
   - Configuration files
   - Core domain models
   - API controllers/handlers

3. **Analyze each file** against the loaded conventions. Check for:
   - Correct logging library usage (e.g., kotlin-logging vs raw SLF4J)
   - Structured logging patterns (lambda syntax, parameterized messages, structured fields)
   - Context propagation (MDC in coroutines, child loggers, metadata)
   - Error handling alignment with language conventions
   - Framework-specific convention adherence
   - Async/concurrency patterns

4. **Report findings** with `DEEP-*` category prefix:
   ```
   Deep Convention Analysis:
     Files analyzed:   {n} of {total} (representative sample)

     Findings:
     1. src/service/OrderService.kt:3 | DEEP-LOG | WARNING |
        Using SLF4J LoggerFactory directly — use kotlin-logging (KotlinLogging.logger {})
     2. src/api/UserController.kt:15 | DEEP-CONV | INFO |
        MDC not cleared in finally block — risk of context bleed
   ```

5. **Append** deep analysis findings to `.pipeline/baseline-report.md`.

If declined, skip silently.

#### Remediation

After all completed tiers, if any findings were reported, offer:

```
  [1] Fix CRITICAL issues only
  [2] Fix all WARNING and above
  [3] Save report only (already saved to .pipeline/baseline-report.md)
  [4] Skip — proceed without fixing
```

If the user chooses to fix ([1] or [2]): address issues methodically — fix each issue, re-run the specific check on the affected file, confirm resolution. Do NOT re-run the full scan after each fix.

---

### Phase 5: MANUAL RELATED REPOS (optional — only if Phase 2b found nothing)

**Skip this phase entirely if Phase 2b already configured `related_projects:` in the config.** This phase only fires as a manual fallback.

Ask the user: **"Does this project work with related repositories (e.g., frontend, backend, infrastructure, API contracts)? I can configure cross-repo validation."**

If the user provides related repos:

1. **Verify each path** exists and is a valid git repository.
2. **Auto-detect role** for each repo using the same stack-marker logic from Phase 1.
3. **Store in config**: Add entries to the `related_projects:` section in `.claude/dev-pipeline.local.md` (same format as Phase 2b):
   ```yaml
   related_projects:
     frontend:
       path: "/absolute/path/to/frontend-app"
       repo: "github.com/org/frontend-app"
       framework: react
       detected_via: "manual"
   ```
4. **Contract validation**: If an OpenAPI spec is found in a related project, add `contract_validation` config:
   ```yaml
   contract_validation:
     enabled: true
     spec_path: "/absolute/path/to/api-contracts/openapi.yaml"
     check_on: [VERIFY, REVIEW]
   ```

---

### Phase 6: CLEANUP

Check for legacy setup artifacts:

- If `.claude/plugins/dev-pipeline` exists as a git submodule (check `.gitmodules`), offer to remove it:
  - Explain: "The plugin is now installed via the marketplace. The old submodule can be removed."
  - If confirmed: run `git submodule deinit .claude/plugins/dev-pipeline`, `git rm .claude/plugins/dev-pipeline`, clean `.gitmodules`
  - If declined: skip, but warn about potential conflicts

- If `.pipeline/` directory exists with stale state, offer to clean it.

If nothing to clean up, skip this phase silently.

---

### Phase 6b: GRAPH INITIALIZATION (optional)

## Graph Initialization (Optional)

If `graph.enabled` is `true` in the generated `dev-pipeline.local.md`:
1. Invoke `/graph-init` to start Neo4j container, seed plugin graph, and build project graph
2. If graph-init fails (Docker not available, port conflict, etc.), warn the user but continue — graph is optional
3. Set `integrations.neo4j.available` based on the result
4. If graph initialization is enabled and completes successfully, dispatch `pl-130-docs-discoverer` to populate `Doc*` nodes alongside the `Project*` nodes built by `build-project-graph.sh`. This seeds the graph with documentation structure from the first init, enabling documentation-aware queries from the first pipeline run.

---

### Phase 7: REPORT

Present a final summary:

```
Pipeline initialized successfully!

  Project:    my-awesome-app
  Module:     spring
  Config:     .claude/dev-pipeline.local.md
              .claude/pipeline-config.md
              .claude/pipeline-log.md

  Available commands:
    /pipeline-run <description>   — Run full pipeline for a feature
    /pipeline-run --from=<stage>  — Resume from a specific stage

  Quick start:
    /pipeline-run Add user registration endpoint

  Health: All checks passed (build, tests, engine)
```

If any phase was skipped or had issues, note them clearly so the user knows the state.
