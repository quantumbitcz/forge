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
| `build.gradle.kts` + Kotlin source files (`*.kt`) | `kotlin-spring` |
| `build.gradle.kts` + Java source files (`*.java`) | `java-spring` |
| `package.json` + `vite.config.*` + react dependency | `react-vite` |
| `package.json` + `svelte.config.*` | `typescript-svelte` |
| `package.json` (no framework markers above) | `typescript-node` |
| `Cargo.toml` | `rust-axum` |
| `go.mod` | `go-stdlib` |
| `pyproject.toml` + fastapi dependency | `python-fastapi` |
| `Package.swift` + Vapor dependency | `swift-vapor` |
| `*.xcodeproj` | `swift-ios` |
| `Makefile` + `*.c` source files | `c-embedded` |

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
- **Linters**: ESLint, Detekt, ktlint, Clippy, golangci-lint, Ruff, SwiftLint, etc.
- **OpenAPI spec**: `openapi.yaml`, `openapi.json`, `swagger.yaml`, `swagger.json` (search recursively)

Present findings in a clear summary table:

```
Detected stack:     react-vite
Module:             modules/react-vite
Package manager:    pnpm
Test framework:     Vitest
Linters:            ESLint, Prettier
Docker:             docker-compose.yml (3 services)
CI/CD:              GitHub Actions (2 workflows)
OpenAPI:            docs/openapi.yaml
```

Ask the user: **"Does this look correct? Should I proceed with the `{module}` module?"**

Wait for confirmation before continuing. If the user corrects something, adjust accordingly.

---

### Phase 2: CONFIGURE

Once confirmed, generate the configuration files:

1. **Read the module template**: Read `${CLAUDE_PLUGIN_ROOT}/modules/{detected_module}/local-template.md` to get the template content.

2. **Fill in detected values**: Replace template placeholders with detected project-specific values:
   - Build command (e.g., `./gradlew build -x test`, `pnpm build`, `cargo build`)
   - Test command (e.g., `./gradlew test`, `pnpm test`, `cargo test`)
   - Lint command (if linters detected)
   - Format command (if formatter detected)
   - Adjust module paths if the project uses a monorepo structure

3. **Write config files**:
   - Copy filled template to `.claude/dev-pipeline.local.md`
   - If `${CLAUDE_PLUGIN_ROOT}/modules/{detected_module}/pipeline-config-template.md` exists, copy it to `.claude/pipeline-config.md`
   - Create `.claude/pipeline-log.md` with this content:
     ```
     # Pipeline Log

     Accumulated learnings from pipeline runs. Updated automatically by `pipeline-learner`.
     ```

4. **Create `.claude/` directory** if it does not exist. Never overwrite existing files without asking first — if any config file already exists, show a diff of what would change and ask for confirmation.

Show the user what files were created and their key settings. Ask: **"Config files written. Want me to validate the setup?"**

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

#### Post-Validation: Engine Dry Run

After successful validation, verify the check engine works with the detected module:

```bash
${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --dry-run
```

- If the dry-run **fails**: **WARN** — "Check engine dry-run failed. Hook-based checks may not work. Error: {output}". This is a warning, not a blocker — continue to the next phase.
- If the dry-run **passes**: Report — "Check engine verified — hooks will run on every file edit."

---

### Phase 4: HEALTH SCAN (optional)

Ask the user: **"Would you like me to run a full codebase health scan? This checks code quality, linting, and dependency vulnerabilities."**

If the user accepts:

1. **Layer 1 — Static analysis**: Run linter/check commands on all source files using the detected linters. If no linters are configured, note this as a recommendation.

2. **Layer 2 — Dependency audit**: Run the appropriate audit tool:
   - `npm audit` / `pnpm audit` / `yarn audit` (Node.js)
   - `cargo audit` (Rust — install if missing)
   - `pip-audit` (Python — install if missing)
   - `./gradlew dependencyCheckAnalyze` (JVM — if OWASP plugin present)
   - `govulncheck ./...` (Go — if installed)
   - Note if no audit tool is available

3. **Present findings** as a summary table:

   ```
   Health Scan Results:
   | Category          | Critical | Warning | Info |
   |-------------------|----------|---------|------|
   | Linting           | 0        | 12      | 34   |
   | Dependencies      | 1        | 3       | 0    |
   | Code conventions  | 0        | 5       | 8    |
   ```

4. **Offer remediation options**:
   - `[1]` Fix CRITICAL issues only
   - `[2]` Fix all WARNING and above
   - `[3]` Save report to `.pipeline/health-report.md` for later
   - `[4]` Skip — proceed without fixing

If the user chooses to fix issues, address them methodically: fix, re-run the specific check, confirm resolution. Do NOT run the full scan again after each fix.

---

### Phase 5: RELATED REPOS (optional)

Ask the user: **"Does this project work with related repositories (e.g., frontend, backend, infrastructure, API contracts)? I can configure cross-repo validation."**

If the user provides related repos:

1. **Verify each path** exists and is a valid git repository.
2. **Auto-detect role** for each repo:
   - Contains `package.json` + UI framework → `frontend`
   - Contains `build.gradle.kts` / `Cargo.toml` / `go.mod` / `pyproject.toml` → `backend`
   - Contains `terraform/` / `pulumi/` / `helm/` / `k8s/` → `infrastructure`
   - Contains OpenAPI spec → `contracts`
3. **Store in config**: Add a `related_repos` section to `.claude/dev-pipeline.local.md`:
   ```yaml
   related_repos:
     - path: "../frontend-app"
       role: frontend
       module: react-vite
     - path: "../api-contracts"
       role: contracts
       openapi: "openapi.yaml"
   ```
4. **Contract validation**: If an OpenAPI spec is found in a related contracts repo, add `contract_validation` config:
   ```yaml
   contract_validation:
     enabled: true
     spec_path: "../api-contracts/openapi.yaml"
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

### Phase 7: REPORT

Present a final summary:

```
Pipeline initialized successfully!

  Project:    my-awesome-app
  Module:     kotlin-spring
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
