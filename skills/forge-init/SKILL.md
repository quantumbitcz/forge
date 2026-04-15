---
name: forge-init
description: "Auto-configures a project for the forge pipeline. Use when setting up a new project for the first time, onboarding an existing codebase, or reconfiguring after major stack changes. Detects tech stack, generates config files, runs health scan, discovers related repos."
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent', 'AskUserQuestion']
ui: { ask: true }
---

# /forge-init — Zero-Config Project Setup

You are the pipeline initializer. Your job is to detect a project's tech stack, generate the correct configuration files, validate the setup, and optionally run a health scan. Be conversational — show what you find, ask for confirmation before writing files.

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel`. If fails: report "Not a git repository. Initialize with `git init` first." and STOP.
2. **System prerequisites:** Run `bash shared/check-prerequisites.sh`. If fails: show the error messages and STOP. The user must install the missing prerequisites before the forge can operate.
3. **Environment health check (informational):** Run `bash "${CLAUDE_PLUGIN_ROOT}/shared/check-environment.sh"`. Parse the JSON output and display a categorized dashboard:

   ```
   ## Environment Health

   ### Required
     ✅ bash 5.2.26         Shell runtime
     ✅ python3 3.12.4      State management, check engine
     ✅ git 2.45.1          Version control

   ### Recommended (improves pipeline quality)
     ✅ jq 1.7.1            JSON processing for state management
     ❌ docker              Required for Neo4j knowledge graph
     ❌ tree-sitter         L0 AST-based syntax validation
     ✅ gh 2.49.0           GitHub CLI for cross-repo discovery
     ✅ sqlite3 3.45.0      SQLite code graph
   ```

   Use `✅` for available tools (with version) and `❌` for missing tools. Only show optional tools if they were detected (language-specific probes).

   **MCP Integration Detection:** After displaying CLI tools, detect available MCP servers per `shared/mcp-detection.md`. For each MCP, check if its detection probe tool is available in your tool list. Display:

   ```
   ### MCP Integrations
     ✅ Context7            Library documentation lookups
     ❌ Playwright          Visual verification + a11y testing
     ❌ Linear              Issue tracking integration
     ❌ Figma               Design-to-code workflows
     ✅ Excalidraw          Architecture diagrams
   ```

   **Install suggestions:** If any recommended tools or useful MCPs are missing, show platform-specific install commands from the JSON output's `install` field:

   ```
   ### Suggested Installations

   For best pipeline experience:
     docker:       brew install --cask docker       # Neo4j knowledge graph
     tree-sitter:  brew install tree-sitter         # AST-based syntax validation

   For optional MCP integrations:
     Playwright:   Claude Code Settings → MCP → Add "Playwright"
     Linear:       Claude Code Settings → MCP → Add "Linear"
   ```

   This step is informational only — never block on missing optional tools. Continue immediately after displaying. If the script is missing or fails, skip this step silently.

## Instructions

Work through these phases in order. Do NOT skip ahead -- each phase builds on the previous one.

---

### Phase 1: DETECT

#### Pre-Validation

Before scanning for stack markers, verify the environment is ready:

1. **Git repository check**: Run `git rev-parse --show-toplevel`
   - If it fails: **ERROR** — "Not a git repository. Initialize with `git init` first." Abort.
2. **Config directory check**: Verify `.claude/` directory exists and is writable.
   - If it does not exist, it will be created in the CONFIGURE phase — this is fine, just note it.
   - If it exists but is not writable: **ERROR** — "`.claude/` directory is not writable. Check permissions." Abort.
3. **Existing config check**: Check whether `.claude/forge.local.md` already exists.
   - If it exists: **ASK via AskUserQuestion** with header "Config", question "Found existing `forge.local.md`. What should I do?", options: "Overwrite" (description: "Replace existing config with freshly detected settings") and "Keep existing" (description: "Abort initialization and preserve current configuration").
   - If the user chooses "Keep existing": abort with message "Keeping existing configuration."
   - If the user chooses "Overwrite": proceed, and the CONFIGURE phase will overwrite the file.

#### Greenfield Detection

Before scanning for stack markers, check whether the project is empty or has no source code:

1. **Check tracked files**: Run `git ls-files --cached --others --exclude-standard | head -5`
   - If the command returns empty (no tracked or untracked files, ignoring `.claude/` and `.forge/`): the project is **greenfield**.
   - If the only files present are configuration files (`.gitignore`, `.editorconfig`, `README.md`, `LICENSE`) with no source code: the project is **greenfield**.
2. **Check for any language markers**: Quickly scan for the existence of ANY build/manifest file (`package.json`, `build.gradle.kts`, `build.gradle`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `Package.swift`, `*.csproj`, `CMakeLists.txt`, `Makefile`).
   - If none found: the project is **greenfield**.

If the project is greenfield, **ASK via AskUserQuestion** with header "New Project", question "This looks like a new project with no code yet. Would you like to scaffold a project from scratch?", options:
- "Bootstrap" (description: "Select a tech stack and scaffold a production-grade project structure with build system, CI/CD, and tooling")
- "Select stack manually" (description: "Just configure the pipeline — I'll tell you what tech stack I plan to use")
- "Skip" (description: "Proceed with detection anyway — I have code that wasn't detected")

**If user chooses "Bootstrap":**
1. Ask the user directly: **"What would you like to build? Describe your project (e.g., 'Kotlin Spring Boot REST API with PostgreSQL', 'React Vite frontend with TypeScript')."**
2. After receiving the description, dispatch `fg-050-project-bootstrapper` via the Agent tool with the user's description. The bootstrapper handles all scaffolding, validation, and auto-runs `/forge-init` at the end. **Return the bootstrapper's output and stop** — do not continue to Phase 2.

**If user chooses "Select stack manually":**
1. Present the available frameworks grouped by language:

   | Language | Frameworks |
   |----------|-----------|
   | Kotlin/Java | `spring`, `jetpack-compose`, `kotlin-multiplatform` |
   | TypeScript | `react`, `nextjs`, `angular`, `vue`, `svelte`, `sveltekit`, `express`, `nestjs` |
   | Rust | `axum` |
   | Go | `gin`, `go-stdlib` |
   | Python | `fastapi`, `django` |
   | Swift | `vapor`, `swiftui` |
   | C# | `aspnet` |
   | C/C++ | `embedded` |
   | Infrastructure | `k8s` |

2. **ASK via AskUserQuestion** with header "Framework", question "Which framework will you use?", options: up to 4 most likely matches based on any context clues, plus "Other" (description: "I'll type the framework name").
3. Once the framework is selected, use it as the detected module and continue to Phase 1.5 (Code Quality Recommendations) and Phase 2 (CONFIGURE) normally. Skip the rest of Phase 1 detection since the user selected manually.

**If user chooses "Skip":** Continue with normal stack detection below.

#### Stack Detection

Scan the project root and immediate subdirectories for stack markers. Check for the **first match** in this priority order:

| Markers | Module |
|---------|--------|
| `build.gradle.kts` + `compose` dependency (Android/Compose) | `jetpack-compose` |
| `build.gradle.kts` + `kotlin("multiplatform")` or KMP plugin | `kotlin-multiplatform` |
| `build.gradle.kts` + `spring-boot` / `org.springframework` | `spring` |
| `build.gradle` + `spring-boot` / `org.springframework` | `spring` |
| `angular.json` | `angular` |
| `package.json` + `next.config.*` | `nextjs` |
| `package.json` + `svelte.config.*` + `@sveltejs/kit` dependency | `sveltekit` |
| `package.json` + `nest-cli.json` | `nestjs` |
| `package.json` + `vue` dependency | `vue` |
| `package.json` + `svelte` dependency (no `@sveltejs/kit`) | `svelte` |
| `package.json` + `vite.config.*` + react dependency | `react` |
| `package.json` (no framework markers above) | `express` |
| `Cargo.toml` + `axum` dependency | `axum` |
| `go.mod` + `gin-gonic/gin` dependency | `gin` |
| `go.mod` (no framework markers above) | `go-stdlib` |
| `manage.py` or `pyproject.toml` + django dependency | `django` |
| `pyproject.toml` + fastapi dependency | `fastapi` |
| `Package.swift` + Vapor dependency | `vapor` |
| `*.xcodeproj` | `swiftui` |
| `*.csproj` or `*.sln` | `aspnet` |
| `Makefile` + `*.c` source files | `embedded` |
| Helm charts / K8s manifests / Terraform dirs | `k8s` |

#### Ambiguity Resolution

If module detection is ambiguous — for example, both `build.gradle.kts` and `package.json` exist in the project root or subdirectories, matching multiple modules — do NOT guess. Instead:

1. **ASK via AskUserQuestion** with header "Framework", question "Detected multiple frameworks. Which is the primary module for pipeline configuration?", options: one per detected framework (label: framework name, description: matched markers that triggered the detection). Max 4 options.
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

**ASK via AskUserQuestion** with header "Confirm", question "Does this detected stack look correct? Should I proceed with the `{module}` module?", options: "Proceed" (description: "Stack detection looks correct, continue to configuration") and "Adjust" (description: "Something is wrong — I'll provide corrections").

Wait for confirmation before continuing. If the user chooses "Adjust", ask what needs to change and adjust accordingly.

**If detection returned unknown/null** (non-greenfield project with code but unrecognized stack): Present the available frameworks table (same as the "Select stack manually" flow in Greenfield Detection) and ask the user to select manually. Do NOT proceed with a null module — every project needs a resolved framework module for configuration generation.

#### Documentation Sources Prompt

After stack confirmation, if any documentation files were detected, ask:

> "Found {N} documentation files. Are there additional docs I should know about? (external wikis, Confluence spaces, Notion pages, shared drives) You can also add these later — the pipeline picks up new docs automatically on each run."

If the user provides URLs or paths:
- Store them for inclusion in the `documentation.external_sources` array during Phase 2 configuration.
- Accept any format: URLs, file paths, or just descriptions.

If the user says no or skips: proceed without additional sources.

---

### Phase 1.5 — Smart Code Quality Recommendations

**Input:** Framework's `code_quality_recommended` list from local-template.md + project's existing tool configs detected in Phase 1.

**Algorithm:**

1. **Load recommendations:** Read the framework's `code_quality_recommended` list from `local-template.md`
2. **Read frontmatter:** For each recommended tool, read its `modules/code-quality/{tool}.md` YAML frontmatter to extract: `exclusive_group`, `recommendation_score`, `detection_files`, `categories`
3. **Detect existing tools:** For each tool, check if ANY of its `detection_files` exist in the project root. Mark as "already configured" if found.
4. **Group by exclusive_group:** Partition tools into groups. Tools with `exclusive_group: none` (security scanners) go into a "complementary" bucket — no deduplication needed.
5. **Deduplicate per group:**
   a. If the project already has a tool from this group (detected via `detection_files`) → keep it, hide alternatives
   b. If no tool detected in the group → pre-select the one with highest `recommendation_score`
   c. Mark remaining tools in the group as "alternatives (not selected)"

6. **Present to user** via `AskUserQuestion`:

   ```
   Header: "Code Quality Tools"
   Question: "Recommended tools for your {framework} + {language} project:"
   Options:
     A) Accept recommendations:
        ✅ {tool1} — {description from overview} (recommended)
        ✅ {tool2} — {description} (recommended)
           ↳ Alternatives: {alt1}, {alt2} (same category: {exclusive_group})
        ✅ {tool3} — {description} (recommended)
        ...
     B) Customize selection (per-group choices)
     C) Skip code quality setup
   ```

7. **If user selects (B) — Customize:**
   For each exclusive group with multiple members, present via `AskUserQuestion`:

   For exclusive groups (radio — pick one):
   ```
   Header: "{Language} {Category}"
   Question: "Pick one (or none):"
   Options:
     A) {tool1} — {brief desc} (recommended, score: {N})
     B) {tool2} — {brief desc} (score: {N})
     C) {tool3} — {brief desc} (score: {N})
     D) None — skip this category
   ```

   For complementary groups (checkboxes — pick any):
   ```
   Header: "Security Scanning"
   Question: "Select any (all are complementary):"
   Options:
     A) ☑ {tool1} — {desc} (recommended)
     B) ☐ {tool2} — {desc}
     C) ☐ {tool3} — {desc}
   ```

8. **Write selections** to `forge.local.md` `code_quality:` list.
   - Simple string form: `code_quality: [detekt, ktlint, jacoco]`
   - Object form for tools with external rulesets: `code_quality: [{name: detekt, ruleset: "path/to/rules.xml"}]`

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
   - Copy filled template to `.claude/forge.local.md`
   - If `${CLAUDE_PLUGIN_ROOT}/modules/frameworks/{detected_module}/forge-config-template.md` exists, copy it to `.claude/forge-config.md`
   - Create `.claude/forge-log.md` with this content:
     ```
     # Forge Log

     Accumulated learnings from forge runs. Updated automatically by the retrospective agent.
     ```

4. **Code Quality Scaffolding**: For each accepted tool from Phase 1.5:
   - **Project setup:** Add build dependency, generate baseline config, wire into build commands
   - **CI/CD setup (if accepted):** Add pipeline steps for linting, coverage reports, threshold enforcement
   - Config patterns sourced from `modules/code-quality/{tool}.md` → Installation & Setup and CI Integration sections
   - Do NOT modify existing configs, force declined tools, or scaffold conflicting tools without resolution
   - Record accepted tools in the `code_quality` list in `forge.local.md` (simple string form `- jacoco` or object form with external ruleset `- tool: detekt\n  ruleset:\n    type: external\n    source: "..."`)

5. **Documentation config**: If the module's `local-template.md` includes a `documentation:` section (all modules now do), populate detected values:
   - Set `external_sources` from any URLs the user provided in the documentation prompt
   - The `auto_generate` defaults come from the template — no detection-based overrides needed

6. **Create `.claude/` directory** if it does not exist. Never overwrite existing files without asking first — if any config file already exists, show a diff of what would change and ask for confirmation.

7. **Ensure `.forge/` is gitignored**: Check if the project's `.gitignore` already contains a `.forge/` or `.forge` entry. If not, append it:
   ```
   # Forge pipeline state (local only, never committed)
   .forge/
   ```
   If `.gitignore` does not exist, create it with this entry. This prevents pipeline state (lock files, worktrees, checkpoints, tracking, reports) from being accidentally committed.

Show the user what files were created and their key settings. **ASK via AskUserQuestion** with header "Validate", question "Config files written. Want me to validate the setup?", options: "Validate" (description: "Run build, test, and engine checks to verify everything works (Recommended)"), "Skip" (description: "Skip validation — I'll test it myself later").

---

### Phase 2a — Git Conventions Detection

1. **Scan for existing hooks** in the project:
   - `.husky/` → Husky detected
   - `.git/hooks/commit-msg` (exists with content, not default sample) → Native git hook
   - `.pre-commit-config.yaml` → pre-commit framework
   - `lefthook.yml` → Lefthook
   - `commitlint.config.*` (js, json, yaml, yml, ts, cjs, mjs) → commitlint
   - `.czrc` or `.cz.json` → Commitizen

2. **If any convention tool detected:**
   - If commitlint: parse rules to extract allowed types and scopes
   - Write to `forge.local.md` `git:` section with `commit_format: project` and detected rules
   - Set `git.commit_enforcement: external`
   - Tell user: "Detected {tool}. Adopting your project's commit conventions."

3. **If NO convention tool detected:**
   - Ask user via `AskUserQuestion`:
     ```
     Header: "Git Conventions"
     Question: "No commit conventions detected. Would you like to set up Conventional Commits?"
     Options:
       A) Yes, set up Conventional Commits (recommended)
       B) No, I'll configure my own later
     ```
   - If (A): Write defaults to `forge.local.md` `git:` section with `commit_format: conventional`
   - If (B): Write `git:` section with `commit_format: none`

4. **Branch naming:**
   - Write `git.branch_template: "{type}/{ticket}-{slug}"` to `forge.local.md`
   - If a custom branch naming hook is detected, parse its pattern and use it instead

---

### Phase 2b — Kanban Tracking Setup

1. Check if `.forge/tracking/counter.json` already exists
2. If not, ask user via `AskUserQuestion`:
   ```
   Header: "Kanban Tracking"
   Question: "Set up file-based kanban tracking for this project?"
   Options:
     A) Yes, with default prefix "FG"
     B) Yes, with custom prefix
     C) No, skip tracking
   ```
3. If (A): Source `shared/tracking/tracking-ops.sh`, call `init_counter ".forge/tracking"`
4. If (B): Ask for prefix via `AskUserQuestion`, then `init_counter ".forge/tracking" "$prefix"`
5. If (C): Skip
6. If (A) or (B): Create directory structure: `mkdir -p .forge/tracking/{backlog,in-progress,review,done}`
7. If (A) or (B): Generate initial empty board: `generate_board ".forge/tracking"`

---

### Phase 2c: CROSS-REPO DISCOVERY

After generating the project config, run the discovery chain to find related projects automatically.

1. **Run discovery script:**
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/shared/discovery/discover-projects.sh" "$(pwd)" --depth 4
   ```

   This scans in order: in-project references (docker-compose.yml, .env files, CI workflow references), sibling directories (same parent, compatible stack markers), IDE project directories (all JetBrains IDEs, VS Code, Cursor, Windsurf, Zed, Xcode, Eclipse, NetBeans, Visual Studio — plus platform-specific paths for MacOS, Linux, and Windows including Documents, drive roots, and XDG dirs), and GitHub org repos (if `gh` CLI is authenticated).

2. **Present discoveries to user:**
   Show what was found and ask for confirmation:
   ```
   ## Discovered Related Projects

   OK  project-fe (frontend, react) at ../project-fe  [via sibling-directory]
   OK  project-infra (infra, k8s) at ../project-infra  [via docker-compose.yml]
   ?   project-mobile — not found

   **ASK via AskUserQuestion** with header "Projects", question "Add these related projects to your config?", options: "Add all" (description: "Add all discovered projects to cross-repo config"), "Edit" (description: "Let me review and adjust the list before adding"), "Skip" (description: "Don't configure cross-repo — I'll do it later").
   ```

   - `OK` — path exists and is a valid git repository
   - `?` — referenced but not found on disk (show as informational only, do not add)

3. **If user chooses "Add all":** Add `related_projects:` section to `forge.local.md`:
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

6. **If discovery script is not found** (plugin not fully installed, first-time setup): skip this step silently with an INFO note — "Discovery script not available. You can add related projects manually to `forge.local.md`."

7. **Add discovery config** to `forge.local.md` when any related projects are written:
   ```yaml
   discovery:
     enabled: true
     scan_depth: 4
     confirmation_required: true
   ```

---

### Convention Validation

After generating `forge.local.md`, validate that all convention references resolve to existing module files:

```
bash "${CLAUDE_PLUGIN_ROOT}/shared/validate-conventions.sh" ".claude/forge.local.md" "${CLAUDE_PLUGIN_ROOT}"
```

If any references are missing:
- Show all missing references to the user
- Suggest corrections (e.g., "Did you mean 'jooq' instead of 'jooql'?")
- Ask whether to fix and retry, or continue with degraded conventions
- Do NOT abort init — the user may want to proceed with partial conventions

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

4. **Save report** to `.forge/baseline-report.md` with all findings grouped by severity. This file is always written regardless of what the user chooses next.

   Map category prefixes: `ARCH-*` → Architecture, `SEC-*` → Security, `PERF-*` → Performance, `TEST-*` → Test Quality, `CONV-*` → Conventions, `DOC-*` → Documentation, `QUAL-*` → Code Quality, `FE-PERF-*` → Frontend Perf, `APPROACH-*` → Approach, `A11Y-*` → Accessibility, `DEP-*` → Dependencies, `COMPAT-*` → Compatibility. `SCOUT-*` findings have no deduction.

#### Step 2: Deeper Analysis (optional)

**ASK via AskUserQuestion** with header "Analysis", question "Want me to run a deeper analysis with linters and dependency audit?", options: "Run analysis" (description: "Use project linters and check for known vulnerabilities (Recommended)"), "Skip" (description: "Skip deeper analysis — convention scan is sufficient").

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

**ASK via AskUserQuestion** with header "Deep scan", question "Want me to run a deep AI-powered convention analysis? Checks logging, error handling, async patterns against best practices. Takes longer but catches issues pattern matching can't.", options: "Run deep scan" (description: "Analyze up to 20 representative files against full convention rules"), "Skip" (description: "Skip deep analysis — proceed to remediation").

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

5. **Append** deep analysis findings to `.forge/baseline-report.md`.

If declined, skip silently.

#### Remediation

After all completed tiers, if any findings were reported, **ASK via AskUserQuestion** with header "Remediate", question "How should I handle the findings from the baseline audit?", options:
- "Fix CRITICAL only" (description: "Auto-fix only CRITICAL severity issues — safest option")
- "Fix WARNING+" (description: "Auto-fix all WARNING and CRITICAL issues")
- "Save report" (description: "Already saved to .forge/baseline-report.md — review later")
- "Skip" (description: "Proceed without fixing anything")

If the user chooses to fix: address issues methodically — fix each issue, re-run the specific check on the affected file, confirm resolution. Do NOT re-run the full scan after each fix.

---

### Phase 5: MANUAL RELATED REPOS (optional — only if Phase 2c found nothing)

**Skip this phase entirely if Phase 2c already configured `related_projects:` in the config.** This phase only fires as a manual fallback.

Ask the user: **"Does this project work with related repositories (e.g., frontend, backend, infrastructure, API contracts)? I can configure cross-repo validation."**

If the user provides related repos:

1. **Verify each path** exists and is a valid git repository.
2. **Auto-detect role** for each repo using the same stack-marker logic from Phase 1.
3. **Store in config**: Add entries to the `related_projects:` section in `.claude/forge.local.md` (same format as Phase 2c):
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

- If `.claude/plugins/forge` exists as a git submodule (check `.gitmodules`), offer to remove it:
  - Explain: "The plugin is now installed via the marketplace. The old submodule can be removed."
  - If confirmed: run `git submodule deinit .claude/plugins/forge`, `git rm .claude/plugins/forge`, clean `.gitmodules`
  - If declined: skip, but warn about potential conflicts

- If `.forge/` directory exists with stale state, offer to clean it.

If nothing to clean up, skip this phase silently.

---

### Phase 6b: GRAPH INITIALIZATION (optional)

## Graph Initialization (Optional)

If `graph.enabled` is `true` in the generated `forge.local.md` (this is the default — enabled by default per CLAUDE.md):

1. **Check Docker availability**: Run `docker info` to verify Docker is running.
   - If Docker is NOT available: skip graph init with a note — "Docker is not running. Graph features will be disabled. Start Docker and run `/forge-graph-init` later to enable."
   - If Docker IS available: **always proceed** — the Neo4j image will be pulled automatically if not already present. Do NOT skip just because the image is missing.

2. **Invoke `/forge-graph-init`** to start the Neo4j container (pulling the image if needed), import the plugin seed, and build the project codebase graph.

3. If graph-init fails due to a **non-Docker issue** (port conflict, disk space, timeout, etc.), warn the user but continue — graph is optional. Suggest: "Run `/forge-graph-init` later to retry."

4. Set `integrations.neo4j.available` based on the result.

5. If graph initialization completes successfully, dispatch `fg-130-docs-discoverer` to populate `Doc*` nodes alongside the `Project*` nodes built by `build-project-graph.sh`. This seeds the graph with documentation structure from the first init, enabling documentation-aware queries from the first pipeline run.

---

### Phase 6c — MCP Provisioning

For each MCP listed in `forge.local.md` `mcps:` section where `auto_install: true`:

1. Check if already configured (search `.mcp.json` in project root).
2. If not configured:
   a. Check prerequisites (e.g., Docker for Neo4j).
   b. If prerequisites met: search internet for latest package version, install, write `.mcp.json`, verify.
   c. If prerequisites missing: ask user via `AskUserQuestion` to skip or install the prerequisite.
3. Report provisioned MCPs in the init summary.

Follow `shared/mcp-provisioning.md` for the detailed flow.

---

### Phase 6d — Project-Local Plugin Generation

Generate a project-local Claude Code plugin at `.claude/plugins/project-tools/` tailored to the detected project.

**Skip if:** `.claude/plugins/project-tools/plugin.json` already exists — ask user whether to regenerate or skip.

#### Step 1: Create plugin manifest

Write `.claude/plugins/project-tools/plugin.json`:
```json
{
  "name": "project-tools",
  "version": "1.0.0",
  "description": "Project-specific automations generated by /forge-init"
}
```

#### Step 2: Generate hooks (conditional)

**Only if** `git.commit_enforcement` is NOT `external` (no existing hooks detected in Phase 2a):

Create `.claude/plugins/project-tools/hooks/hooks.json`:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/commit-msg-guard.sh",
            "timeout": 3
          }
        ]
      }
    ]
  }
}
```

Create `.claude/plugins/project-tools/hooks/commit-msg-guard.sh`:
```bash
#!/usr/bin/env bash
# Validates commit messages match project conventions.
# Generated by /forge-init — customized from forge.local.md git: section.
MSG_FILE="$1"
MSG=$(head -1 "$MSG_FILE")
PATTERN="^(feat|fix|test|refactor|docs|chore|perf|ci)(\(.+\))?: .{1,72}$"
if ! echo "$MSG" | grep -qE "$PATTERN"; then
  echo "ERROR: Commit message doesn't match conventional commits format"
  echo "Expected: type(scope): description"
  echo "Got: $MSG"
  exit 1
fi
```

Create `.claude/plugins/project-tools/hooks/branch-name-guard.sh`:
```bash
#!/usr/bin/env bash
# Validates branch names match project conventions.
# Generated by /forge-init — customized from forge.local.md git: section.
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
PATTERN="^(feat|fix|refactor|chore)/[A-Z]+-[0-9]+-[a-z0-9-]+$"
if ! echo "$BRANCH" | grep -qE "$PATTERN"; then
  echo "WARNING: Branch '$BRANCH' doesn't match naming convention"
  echo "Expected: {type}/{TICKET-ID}-{slug}"
fi
```

Make both scripts executable: `chmod +x`.

The commit types in the PATTERN should be customized from `forge.local.md` `git.commit_types` if available.

#### Step 3: Generate wrapper skills

Detect build/test/lint/deploy tools and generate minimal wrapper skills:

| Detection | Skill | Command |
|-----------|-------|---------|
| `build.gradle.kts` or `build.gradle` | `/build` | `./gradlew build` |
| Gradle + test task | `/run-tests` | `./gradlew test` |
| `package.json` + vitest/jest | `/run-tests` | `npm run test` |
| `Makefile` | `/build` | `make build` |
| `pyproject.toml` + pytest | `/run-tests` | `pytest` |
| `Cargo.toml` | `/build`, `/run-tests` | `cargo build`, `cargo test` |
| `Dockerfile` + `docker-compose.yml` | `/forge-deploy` | `docker compose up --build` |
| detekt/eslint/ruff/biome config | `/lint` | Appropriate lint command |

Each generated skill is a minimal SKILL.md:
```markdown
---
name: {skill-name}
description: {Brief description} (generated by /forge-init)
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent', 'AskUserQuestion']
---

{Description of what this does}

\`\`\`bash
{detected_command}
\`\`\`

Report results. If the command fails, show the failure summary.
```

Skills are written to `.claude/plugins/project-tools/skills/{name}/SKILL.md`.

#### Step 4: Generate commit-reviewer agent (optional)

Write `.claude/plugins/project-tools/agents/commit-reviewer.md`:
```markdown
---
name: commit-reviewer
description: Reviews staged changes before commit for convention compliance (generated by /forge-init)
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent', 'AskUserQuestion']
tools: ['Read', 'Grep', 'Glob', 'Bash']
---

# Commit Reviewer

Review staged changes (`git diff --cached`) for:
1. Convention compliance (naming, patterns, structure)
2. Obvious issues (debug code, TODO comments, console.log)
3. Missing test coverage for new functions

Report findings as a brief list. Do not block — advisory only.
```

#### Step 5: Offer implementation tasks

After generating the plugin, check if accepted tools need build config implementation:

Ask user via `AskUserQuestion`:
```
Header: "Setup Tasks"
Question: "The following tools need implementation to integrate into your project:"
{list of tools needing build config changes, e.g., "dokka — needs Gradle plugin", "jacoco — needs coverage thresholds"}

Options:
  A) Run /forge-run to implement all setup tasks now
  B) Add to backlog (creates tickets in .forge/tracking/backlog/)
  C) Skip — configure manually later
```

If (A): Create kanban tickets for each task, dispatch `/forge-run` with bundled requirement (runs in worktree).
If (B): Create kanban tickets for future runs.

### A2A Agent Card (v1.19+)

Generate `.forge/agent-card.json` for cross-repo A2A communication:

```json
{
  "name": "forge-pipeline",
  "description": "Autonomous 10-stage development pipeline",
  "url": "local://forge",
  "capabilities": { "streaming": false, "stateTransitionHistory": true },
  "skills": [
    { "id": "implement-feature" },
    { "id": "fix-bug" },
    { "id": "review-code" }
  ],
  "project_id": "<detected from git remote>"
}
```

See `shared/a2a-protocol.md` for the full agent card schema.

### End of Phase 6d

---

### Phase 7: REPORT

Present a final summary:

```
Pipeline initialized successfully!

  Project:    my-awesome-app
  Module:     spring
  Config:     .claude/forge.local.md
              .claude/forge-config.md
              .claude/forge-log.md

  Available commands:
    /forge-run <description>   — Run full pipeline for a feature
    /forge-run --from=<stage>  — Resume from a specific stage

  Quick start:
    /forge-run Add user registration endpoint

  Health: All checks passed (build, tests, engine)
```

If any phase was skipped or had issues, note them clearly so the user knows the state.

## Error Handling

| Condition | Action |
|-----------|--------|
| Not a git repository | Report "Not a git repository. Initialize with `git init` first." and STOP |
| .claude/ not writable | Report "`.claude/` directory is not writable. Check permissions." and STOP |
| Prerequisites check fails (bash/python3) | Show missing prerequisites and abort. User must install them |
| Stack detection ambiguous | Present detected frameworks and ask user to choose primary module |
| Stack detection fails entirely | Present available frameworks table for manual selection |
| Build command fails during validation | Report error. Ask whether to continue or fix first (hard blocker) |
| Test command fails during validation | Report error. Note this may be OK for new projects. Ask to continue |
| Config file already exists | Ask user: Overwrite or Keep existing |
| Docker unavailable for graph init | Skip graph init with note. Suggest running `/forge-graph-init` later |
| Discovery script not found | Skip cross-repo discovery silently with INFO note |
| Convention validation fails | Show missing references, suggest corrections, ask to fix or continue |

## See Also

- `/forge-config-validate` -- Validate configuration after init (catches misconfigurations before pipeline runs)
- `/forge-run` -- Run the full pipeline after initialization is complete
- `/forge-bootstrap` -- Scaffold a new project from scratch (dispatched by init for greenfield projects)
- `/forge-codebase-health` -- Run a full codebase scan after initialization to establish a quality baseline
