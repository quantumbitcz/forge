# Module Restructuring, Cross-Repo Coordination & Pipeline Enhancement

**Date:** 2026-03-23
**Status:** Draft — pending user approval
**Scope:** Tier 1 implementation

---

## 1. Problem Statement

The current module system has several architectural limitations:

1. **Language and framework conventions are coupled.** Each module (e.g., `kotlin-spring`) mixes language idioms (null safety, coroutines) with framework patterns (Spring DI, transactions). This means adding a new combination (e.g., Kotlin+Ktor) requires duplicating all Kotlin conventions.

2. **Testing conventions are incomplete.** Only 2 of 12 modules (kotlin-spring, react-vite) have dedicated testing sections with framework-specific guidance. The other 10 rely on generic TDD rules from the implementer agent.

3. **No cross-repo awareness.** The pipeline operates on a single repository. Projects with separate frontend, backend, infrastructure, and mobile repos cannot coordinate changes (e.g., updating FE types when a BE API changes).

4. **No feature shaping phase.** The pipeline assumes requirements are well-defined at invocation. Vague requirements ("I want notifications") go straight to planning without collaborative refinement.

5. **Critical thinking is not systemic.** The "challenge yourself" mindset exists in 3 agents as individual paragraphs but is absent from review agents, the orchestrator, and the test gate. There's no enforcement mechanism.

6. **Limited framework coverage.** Missing major ecosystems: C#/.NET, Django, Next.js, Go+Gin, Jetpack Compose, Kotlin Multiplatform.

7. **No monorepo support.** A single repo containing backend + frontend + infra has no way to define multiple convention stacks.

---

## 2. Module Architecture: Three-Layer Composable System

### 2.1 Directory Structure

```
modules/
├── languages/                    # Language idioms (null safety, memory, ownership)
│   ├── kotlin.md
│   ├── java.md
│   ├── typescript.md
│   ├── python.md
│   ├── go.md
│   ├── rust.md
│   ├── swift.md
│   ├── c.md
│   └── csharp.md
│   # dart.md deferred to Tier 2 (with Flutter framework)
│
├── frameworks/                   # Framework patterns + config files
│   ├── spring/
│   │   ├── conventions.md        # Shared Spring patterns (DI, transactions, security)
│   │   ├── variants/
│   │   │   ├── kotlin.md         # Kotlin+Spring specifics (sealed interfaces, typed IDs)
│   │   │   └── java.md           # Java+Spring specifics (records, Optional, streams)
│   │   ├── testing/
│   │   │   ├── kotest.md         # Kotest ShouldSpec, matchers, containers
│   │   │   └── junit5-assertj.md # JUnit5 + AssertJ + Mockito patterns
│   │   ├── local-template.md
│   │   ├── pipeline-config-template.md
│   │   ├── rules-override.json
│   │   └── known-deprecations.json
│   ├── react/
│   │   ├── conventions.md
│   │   ├── variants/
│   │   │   └── typescript.md
│   │   ├── testing/
│   │   │   ├── vitest.md
│   │   │   └── jest.md
│   │   ├── ...config files...
│   ├── nextjs/                   # NEW — Tier 1
│   ├── aspnet/                   # NEW — Tier 1
│   ├── django/                   # NEW — Tier 1
│   ├── gin/                      # NEW — Tier 1
│   ├── jetpack-compose/          # NEW — Tier 1
│   ├── kotlin-multiplatform/     # NEW — Tier 1
│   ├── fastapi/                  # Migrated from python-fastapi
│   ├── axum/                     # Migrated from rust-axum
│   ├── swiftui/                  # Migrated from swift-ios
│   ├── vapor/                    # Migrated from swift-vapor
│   ├── express/                  # Migrated from typescript-node
│   ├── sveltekit/                # Migrated from typescript-svelte
│   ├── k8s/                      # Migrated from infra-k8s
│   └── embedded/                 # Migrated from c-embedded
│
└── testing/                      # Cross-cutting test framework conventions
    ├── kotest.md
    ├── junit5.md
    ├── vitest.md
    ├── jest.md
    ├── pytest.md
    ├── go-testing.md
    ├── xctest.md
    ├── rust-test.md
    ├── xunit-nunit.md            # .NET testing
    # flutter-test.md deferred to Tier 2 (with Flutter framework)
    ├── testcontainers.md         # Shared DB/infra container patterns
    └── playwright.md             # Shared E2E across all frontend frameworks
```

### 2.2 Convention Composition

When an agent receives a task for a component, the orchestrator resolves a convention stack and loads all layers:

1. `languages/{language}.md` — language idioms
2. `frameworks/{framework}/conventions.md` — framework patterns
3. `frameworks/{framework}/variants/{language}.md` — language+framework specifics
4. `testing/{testing}.md` — test framework conventions
5. `testing/testcontainers.md` — if persistence layer involved
6. `testing/playwright.md` — if E2E configured

**Conflict resolution order:** variant > framework-testing > framework > language > testing (most specific wins).

**Framework-less projects** (e.g., Go stdlib, plain Python CLI): when `framework` is `null` or `stdlib`, layers 2-3 are skipped. The stack becomes: language → testing only. The orchestrator validates this at PREFLIGHT and logs INFO: "No framework layer — using language + testing conventions only."

**Testing file relationship:** `testing/kotest.md` (top-level) contains generic test framework patterns (matchers, lifecycle, assertions). `frameworks/spring/testing/kotest.md` contains Spring-specific kotest patterns (`@SpringBootTest`, Testcontainers integration, `@DynamicPropertySource`). Both are loaded when the stack includes spring+kotest: the generic file as layer 4, the framework-specific file as layer 2.5 (between framework and variant in priority). Framework-level testing files **extend** generic testing, they do not replace it.

### 2.3 Monorepo Multi-Stack Configuration

`dev-pipeline.local.md` supports multiple components:

```yaml
components:
  backend:
    path: "backend/"
    language: kotlin
    framework: spring
    variant: kotlin
    testing: kotest
    commands:
      build: "./gradlew :backend:build -x test"
      test: "./gradlew :backend:test"
      lint: "./gradlew :backend:lintKotlin detekt"
    scaffolder:
      patterns:
        domain_model: "backend/core/domain/{area}/{Entity}.kt"

  frontend:
    path: "frontend/"
    language: typescript
    framework: react
    testing: vitest
    e2e: playwright
    commands:
      build: "cd frontend && pnpm build"
      test: "cd frontend && pnpm test"
      lint: "cd frontend && pnpm lint"

  infra:
    path: "infra/"
    framework: k8s
    commands:
      lint: "helm lint infra/charts/*"
```

Single-repo projects use one component with `path: "."`.

### 2.4 Orchestrator Resolution Logic

During PREFLIGHT:

1. Read all `components` from config
2. For each component, resolve the convention stack paths
3. Validate all referenced files exist
4. Compute convention fingerprints per component (for mid-run drift detection)
5. Version detection per component (read manifest files in component path)
6. Load deprecation rules per component's framework

During IMPLEMENT:
- Each task is scoped to a component
- Agent receives only that component's convention stack
- Check engine applies the correct `rules-override.json` based on which component's files were edited

### 2.5 Migration from Existing 12 Modules

| Current Module | Language | Framework | Variant | Testing |
|----------------|----------|-----------|---------|---------|
| kotlin-spring | kotlin | spring | kotlin | kotest |
| java-spring | java | spring | java | junit5 |
| react-vite | typescript | react | typescript | vitest |
| typescript-svelte | typescript | sveltekit | typescript | vitest |
| typescript-node | typescript | express | typescript | vitest |
| python-fastapi | python | fastapi | python | pytest |
| go-stdlib | go | (none/stdlib) | — | go-testing |
| rust-axum | rust | axum | rust | rust-test |
| swift-ios | swift | swiftui | swift | xctest |
| swift-vapor | swift | vapor | swift | xctest |
| c-embedded | c | embedded | c | (minimal) |
| infra-k8s | — | k8s | — | (helm lint) |

No backward compatibility needed — the old `modules/` directory is replaced entirely.

**Consumer migration:** Existing projects with `dev-pipeline.local.md` files referencing old paths (e.g., `conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/kotlin-spring/conventions.md"`) will break. The `/pipeline-init` skill detects old-format single-module configs and offers to migrate them to the new `components:` format. PREFLIGHT also checks: if `module:` key exists (old format) instead of `components:`, it logs ERROR with migration instructions.

### 2.6 Required Files Per Framework

Every framework directory must contain:

| File | Purpose |
|------|---------|
| `conventions.md` | Framework patterns, architecture, naming, error handling, security, performance, Dos/Don'ts |
| `local-template.md` | Project config template (components, commands, scaffolder, quality gate) |
| `pipeline-config-template.md` | Mutable runtime params (retry budgets, review cycles, risk thresholds) |
| `rules-override.json` | Architecture boundaries, check engine rule overrides |
| `known-deprecations.json` | Version-aware deprecated APIs (schema v2) |

Optional:
| `variants/{language}.md` | Language-specific overrides for this framework |
| `testing/{framework-test}.md` | Framework-specific test patterns extending generic `testing/*.md` |
| `scripts/check-*.sh` | Framework-specific verification scripts |

### 2.7 Linter Adapters for New Frameworks

New check engine adapters required in `shared/checks/layer-2-linter/adapters/`:

| Framework | Adapter | Notes |
|-----------|---------|-------|
| ASP.NET | `dotnet-format.sh` | Uses `dotnet format --verify-no-changes` + Roslyn analyzers |
| Django | (reuse `ruff.sh`) | Same Python linting as FastAPI |
| Next.js | (reuse `eslint.sh`) | `next lint` wraps eslint — existing adapter works |
| Gin | `golangci-lint.sh` | Extends go-vet with golangci-lint for comprehensive Go linting |
| Jetpack Compose | `android-lint.sh` | Android Lint + detekt (reuse detekt adapter for Kotlin rules) |
| Kotlin Multiplatform | (reuse `detekt.sh`) | Detekt works across KMP source sets |

### 2.8 Learnings File Convention

Learnings files move to per-framework naming: `shared/learnings/{framework}.md` (e.g., `spring.md`, `react.md`, `gin.md`). For monorepo projects with multiple frameworks, learnings accumulate in each framework's file independently. Migration: rename existing files (e.g., `kotlin-spring.md` → `spring.md`, `react-vite.md` → `react.md`).

---

## 3. Cross-Repo Discovery & Coordination

### 3.1 Discovery Chain

Executed during `/pipeline-init` (and optionally re-run during PREFLIGHT). Stops when all expected component types are found.

**Step 1 — In-project references** (fastest, most reliable):
- `README.md`, `CONTRIBUTING.md` — mentions of related repos, URLs
- `docker-compose.yml` — service names, build contexts, image references
- `.github/workflows/*.yml` — checkout actions for other repos, deploy references
- `.env`, `.env.example` — `API_URL`, `FRONTEND_URL`, `INFRA_REPO` variables
- `package.json` / `build.gradle.kts` — workspace references, composite build includes
- API spec files (`openapi.yml`) — server URLs, cross-repo annotations
- `CLAUDE.md` — project description often mentions other repos
- `Makefile` / `Taskfile` — targets referencing other directories

**Step 2 — Sibling directory scan:**
From the current repo path, scan sibling directories for:
- Same name prefix (e.g., `projectname-fe`, `projectname-infra`, `projectname-mobile`)
- Same org in `.git/config` remote URL
- Presence of framework indicators: `package.json` (frontend), `helm/` or `k8s/` (infra), `build.gradle` with Android plugin (mobile), `.xcodeproj` (iOS)

**Step 3 — IDE project directories:**
Scan known default project locations:
- `~/IdeaProjects/` — IntelliJ / Android Studio
- `~/Projects/` — common convention
- `~/Developer/` — Xcode
- `~/workspace/` — Eclipse
- `~/repos/` — common convention
- VS Code recent workspaces: `~/.config/Code/User/globalStorage/state.vscdb`
- IntelliJ recent projects: `~/.config/JetBrains/*/options/recentProjects.xml`

**Step 4 — Git remote org scan:**
Extract org from current repo's remote URL. Use `gh repo list {org}` to find related repos by name pattern or description keywords (frontend, infra, mobile, deploy, api).

**Step 5 — Ask the user:**
Only if steps 1-4 didn't find everything. Present what was found and ask for remaining paths.

### 3.2 Storage

Discovery results stored in `dev-pipeline.local.md`:

```yaml
related_projects:
  frontend:
    path: "/absolute/path/to/project-fe"
    repo: "github.com/org/project-fe"
    framework: react
    detected_via: "sibling-directory"
    api_contract: "src/api/openapi.yml"

  infra:
    path: "/absolute/path/to/project-infra"
    repo: "github.com/org/project-infra"
    framework: k8s
    detected_via: "docker-compose.yml"

  mobile:
    path: "/absolute/path/to/project-mobile"
    repo: "github.com/org/project-mobile"
    framework: jetpack-compose
    detected_via: "user-provided"
```

### 3.3 Discovery Configuration

```yaml
discovery:
  enabled: true                    # false for CI environments
  scan_depth: 4                    # 1=in-project only, 2=+siblings, 3=+IDE dirs, 4=+GitHub org
  confirmation_required: true      # always show discovered paths before storing
```

Default: full scan (depth 4) with confirmation. Steps 3-4 (IDE directories, GitHub org scan) are only executed when `scan_depth >= 3` and `scan_depth >= 4` respectively. All discovered paths are presented to the user before being stored, regardless of `confirmation_required` setting in interactive mode.

### 3.4 Cross-Repo Worktree Management

When implementation requires changes in related projects:

**Worktree creation:** Each related project gets its own worktree at `{related_project_path}/.pipeline/worktree`. Branch naming: `feat/{feature-name}-cross-{timestamp}`. Same collision detection as main worktree (epoch suffix fallback).

**State tracking:** `state.json` gains a `cross_repo` field:

```json
{
  "cross_repo": {
    "frontend": {
      "path": "/abs/path/project-fe/.pipeline/worktree",
      "branch": "feat/add-api-types-cross-1711187200",
      "status": "implementing",
      "files_changed": ["src/api/types.ts", "src/hooks/useApi.ts"]
    },
    "infra": {
      "path": "/abs/path/project-infra/.pipeline/worktree",
      "branch": "feat/add-service-deploy-cross-1711187200",
      "status": "complete",
      "files_changed": ["charts/app/values.yaml"]
    }
  }
}
```

**Partial failure handling:** If main repo implementation succeeds but a cross-repo fails:
1. Main repo changes are preserved (not rolled back)
2. Failed cross-repo worktree is left in place for manual inspection
3. Stage notes document the partial failure with details
4. PR for main repo is created with a note: "Cross-repo changes for {project} failed — manual intervention needed"
5. `/pipeline-rollback` handles multi-repo cleanup: offers to rollback each repo independently or all at once

**Lock management:** Each related project gets its own `.pipeline/.lock`. The orchestrator acquires locks in alphabetical order (by project name) to prevent deadlocks. Stale lock detection applies per-project (same 24h + PID check).

### 3.5 Cross-Repo Coordination During Pipeline Runs

| Stage | Behavior |
|-------|----------|
| PLAN | Planner checks if tasks affect API contracts. Creates cross-repo tasks (e.g., "update FE types") |
| VALIDATE | `pl-250-contract-validator` diffs API specs between repos automatically |
| IMPLEMENT | Implementer reads related project files. For cross-repo changes, creates a worktree in each affected repo |
| REVIEW | Infra reviewer checks if K8s manifests match service changes. Frontend reviewer checks if FE types match BE API |
| SHIP | `pl-600-pr-builder` creates linked PRs in each affected repo. Main PR references related PRs |

---

## 4. Systemic Critical Thinking Philosophy

### 4.1 Shared Document: `shared/agent-philosophy.md`

Referenced by every agent's system prompt. Core principles:

**Principle 1 — Never settle for the first solution.**
Before committing to an approach, consider at least 2 alternatives. Document why the chosen approach beats the alternatives. If you cannot articulate why alternative X is worse, you have not thought hard enough.

**Principle 2 — Challenge assumptions at every layer.**
- Shaper: "Is this the right feature? What problem are we really solving?"
- Planner: "Is there a simpler way? Could configuration replace code?"
- Implementer: "Is this the most idiomatic solution? Would a senior dev in this ecosystem do it this way?"
- Reviewer: "Am I finding real issues or rubber-stamping? What would I miss?"
- Test gate: "Are these tests catching bugs, or just inflating coverage?"

**Principle 3 — Think from the user's perspective.**
Every decision should answer: "How does this affect the person using/maintaining this code in 6 months?" Performance, readability, debuggability matter more than cleverness.

**Principle 4 — Seek disconfirming evidence.**
After reaching a conclusion, actively look for reasons you might be wrong. Review agents: after scoring PASS, ask "what did I miss?" Implementer: after tests pass, ask "what scenario would break this?"

**Principle 5 — Escalate uncertainty, don't hide it.**
If unsure between two approaches, say so with trade-offs. If a finding is borderline CRITICAL vs WARNING, explain the ambiguity. If a convention is unclear, flag it rather than guessing.

### 4.2 Enforcement in Planning & Brainstorming

**During SHAPE (pl-010-shaper):**
- Actively challenge whether the feature is the right solution to the user's underlying problem
- Explore whether existing features cover part of the requirement
- Push for MVP scope: "Do you need X for v1, or would Y ship faster?"

**During PLAN (pl-200-planner):**
- Required **Challenge Brief** section in stage notes:
  - What is the user actually trying to achieve? (intent vs literal request)
  - Are there existing features/patterns that already solve part of this?
  - Could this be achieved with configuration instead of code?
  - 2-3 fundamentally different approaches with trade-offs
  - What would a staff engineer push back on?
- Planner ranks approaches by: simplicity, maintainability, framework idiomaticness, future flexibility
- Only then decomposes into stories/tasks

**During VALIDATE (pl-210-validator):**
- New Perspective 6: **Approach Quality**
  - Is the Challenge Brief present and genuine?
  - Did the planner consider meaningfully different approaches?
  - Is the chosen approach justified with concrete reasoning?
  - Would a simpler approach satisfy 80% of the requirement with 20% of the complexity?
  - Are well-known ecosystem solutions being reinvented?
- Missing or shallow Challenge Brief for non-trivial tasks → REVISE

### 4.3 Enforcement Mechanisms

| Mechanism | Location | Effect |
|-----------|----------|--------|
| Challenge Brief | Required in planner stage notes | Validator rejects if missing for non-trivial tasks |
| Self-review checkpoint | Implementer, after GREEN phase | 30-second fresh eyes pass, documented in stage notes |
| Devil's advocate pass | Quality gate, after all batches | Final "what are we missing?" scan before scoring |
| Retrospective tracking | pl-700-retrospective | Tracks "times a better approach was found in review" — frequent occurrence triggers PREEMPT |
| APPROACH-* findings | New finding category | Review agents flag suboptimal approaches (INFO -2) |

### 4.4 New Finding Category

```
APPROACH-*  | Solution quality (suboptimal pattern, unnecessary complexity, missed simplification)
```

Scored as INFO (-2) by default. If the same APPROACH finding recurs 3+ times across runs, the retrospective escalates it to a convention rule.

---

## 5. Feature Shaping: `/pipeline-shape` Skill & `pl-010-shaper` Agent

### 5.1 Purpose

A collaborative pre-pipeline phase that turns vague ideas into structured specs with epics, stories, and acceptance criteria.

### 5.2 Entry Points

**Explicit:** User invokes `/pipeline-shape "feature description"`

**Auto-trigger:** `/pipeline-run` evaluates whether the requirement is well-specified by checking for: (a) specific technical scope, (b) identifiable components to change, (c) testable acceptance criteria. If fewer than 2 of 3 are present, it suggests: "This requirement could benefit from shaping. Run `/pipeline-shape` first, or proceed as-is with `--no-shape`?" User can accept or override.

### 5.2.1 SHAPE as Pre-Pipeline Phase

SHAPE is **not a pipeline stage** — it is a pre-pipeline skill that runs independently, like `/pipeline-init`. It does not appear in the stage contract, does not write stage notes, and does not affect `story_state`. It produces a spec file that `/pipeline-run --spec` consumes. This avoids renumbering the existing 10 stages (0-9).

### 5.3 Agent: `pl-010-shaper`

Interactive dialogue agent that:

1. **Understands intent** — "What problem are you solving? Who is the user?"
2. **Explores scope** — asks clarifying questions one at a time, prefers multiple choice
3. **Identifies components** — "This touches the backend API, frontend UI, and notifications"
4. **Challenges scope** — "Do you need X for v1, or would Y ship faster?" Applies critical thinking principles
5. **Structures output** — produces spec document

### 5.4 Output Format

```markdown
# Feature: {Feature Name}

## Epic: {Epic description}

### Story 1: {Story title}
**As a** {role}
**I want to** {action}
**So that** {benefit}

**Acceptance Criteria:**
- [ ] {criterion 1}
- [ ] {criterion 2}

**Components affected:** {backend, frontend, mobile, infra}

### Story 2: ...

## Technical Notes
- {Architecture considerations}
- {Cross-repo impacts}

## Out of Scope (deferred)
- {Explicitly excluded items}
```

### 5.5 Integration

- Spec saved to `.pipeline/specs/{feature-name}.md`
- `/pipeline-run --spec .pipeline/specs/{feature-name}.md` feeds the spec to the planner
- If Linear MCP available: creates Epic with Stories in Linear, `/pipeline-run` references the Epic ID
- Planner receives the shaped spec instead of raw user text, significantly improving plan quality

---

## 6. Tier 1 New Frameworks

### 6.1 C# / ASP.NET Core (`frameworks/aspnet/`)

- **Language:** `languages/csharp.md` — nullable reference types, records, pattern matching, async/await, LINQ
- **Architecture:** Clean Architecture (Controllers -> Services -> Repositories), Minimal APIs for simple endpoints
- **DI:** Built-in `IServiceCollection`, scoped/transient/singleton lifetimes
- **ORM:** Entity Framework Core — migrations, DbContext, LINQ queries, no raw SQL
- **Auth:** ASP.NET Identity + JWT Bearer, `[Authorize]`, policy-based authorization
- **Variant:** `variants/csharp.md`
- **Testing:** `testing/xunit-nunit.md` — xUnit preferred, FluentAssertions, NSubstitute, TestContainers for .NET
- **Deprecations:** `Startup.cs` -> top-level `Program.cs`, `Newtonsoft.Json` -> `System.Text.Json`, `IWebHostBuilder` -> `WebApplicationBuilder`
- **Commands:** `dotnet build`, `dotnet test`, `dotnet format`

### 6.2 Python + Django (`frameworks/django/`)

- **Language:** `languages/python.md` (shared with FastAPI)
- **Architecture:** MTV (Model-Template-View), Django REST Framework for APIs, apps as bounded contexts
- **ORM:** Django ORM — model definitions, migrations, QuerySet API, `select_related`/`prefetch_related`
- **Auth:** Django auth + DRF permissions, `IsAuthenticated`, custom permission classes
- **Variant:** `variants/python.md`
- **Testing:** `testing/pytest.md` (shared) — pytest-django, `@pytest.mark.django_db`, factory_boy, `APIClient`
- **Deprecations:** `url()` -> `path()`, `django.conf.urls` -> `django.urls`, class-based view patterns
- **Commands:** `python manage.py test`, `ruff check`, `mypy`

### 6.3 TypeScript + Next.js (`frameworks/nextjs/`)

- **Language:** `languages/typescript.md` (shared)
- **Architecture:** App Router (default), Server Components vs Client Components, Route Handlers for API
- **State:** Server Components for data fetching, `use()` for client hydration, no unnecessary `"use client"`
- **Rendering:** SSR/SSG/ISR via route segment config, streaming with Suspense
- **Variant:** `variants/typescript.md`
- **Testing:** `testing/vitest.md` (shared) + `testing/playwright.md` for E2E
- **Deprecations:** Pages Router -> App Router, `getServerSideProps` -> server components, `next/image` legacy loader
- **Commands:** `pnpm build`, `pnpm test`, `pnpm lint` (next lint)

### 6.4 Go + Gin (`frameworks/gin/`)

- **Language:** `languages/go.md` (shared with go-stdlib)
- **Architecture:** Handler -> Service -> Repository, middleware chains, `gin.Context` patterns
- **Patterns:** Functional options for config, interface-driven DI (no framework)
- **Error handling:** Custom error types with HTTP status mapping, `gin.Error()` middleware, no panic in handlers
- **Variant:** `variants/go.md`
- **Testing:** `testing/go-testing.md` (shared) — `testing.T`, testify, httptest, table-driven
- **Deprecations:** `gin.Default()` without custom recovery, `c.JSON` without error check
- **Commands:** `go build ./...`, `go test ./...`, `golangci-lint run`

### 6.5 Kotlin + Jetpack Compose (`frameworks/jetpack-compose/`)

- **Language:** `languages/kotlin.md` (shared with Spring)
- **Architecture:** MVVM — Composables -> ViewModels -> Repositories -> DataSources. Unidirectional data flow
- **State:** `remember`, `mutableStateOf`, `StateFlow` in ViewModel, no `LiveData` in new code
- **Navigation:** Navigation Compose, type-safe routes, deep linking
- **DI:** Hilt (`@HiltViewModel`, `@Inject constructor`)
- **Variant:** `variants/kotlin.md`
- **Testing:** `testing/junit5.md` + Compose testing (`composeTestRule`, semantics assertions, Robolectric)
- **Deprecations:** `LiveData` -> `StateFlow`, XML layouts -> Compose, `AsyncTask` -> coroutines
- **Commands:** `./gradlew assembleDebug`, `./gradlew testDebugUnitTest`, `./gradlew lint`

### 6.6 Kotlin Multiplatform (`frameworks/kotlin-multiplatform/`)

- **Language:** `languages/kotlin.md` (shared)
- **Architecture:** Shared module (`commonMain`) + platform modules (`androidMain`, `iosMain`, `jsMain`). Expect/actual declarations
- **Patterns:** `expect`/`actual` for platform specifics, Koin or Kodein for DI, Ktor Client for networking
- **State:** Kotlin Flows in shared code, platform-specific collection (`StateFlow` on Android, `@Published` bridge on iOS)
- **Variant:** `variants/kotlin.md` with KMP additions for expect/actual, source set conventions
- **Testing:** `testing/kotest.md` for `commonTest`, platform test runners for platform-specific code
- **Deprecations:** `kotlin-multiplatform` plugin renaming, `commonMain` dependency patterns, `kotlinx.serialization` updates
- **Commands:** `./gradlew build`, `./gradlew allTests`, `./gradlew iosSimulatorArm64Test`
- **Convention:** Business logic and data models in `commonMain`, UI in platform modules. No `expect`/`actual` for anything solvable with interfaces + DI

---

## 7. Pipeline Gap Review Process

### 7.1 Pass 1 — Convention Completeness Audit

Every framework conventions file must cover these mandatory sections:

| Section | Required? | Scope |
|---------|-----------|-------|
| Architecture | Yes | Layer diagram, dependency rules, allowed imports |
| Naming | Yes | Artifact type -> naming pattern table |
| Code Quality | Yes | Function size, nesting, file size limits |
| Error Handling | Yes | Domain exceptions -> HTTP/response status mapping |
| Testing | Yes (except infra) | Framework, patterns, what to test, what NOT to test |
| TDD Flow | Yes (except infra) | scaffold -> RED -> GREEN -> refactor |
| Smart Test Rules | Yes (except infra) | No duplicates, no framework tests, behavior focus |
| Security | Yes | Auth patterns, input validation, secrets handling |
| Performance | Yes | N+1, caching, connection pooling, lazy loading |
| Dos/Don'ts | Yes | 10-20 items, language+framework specific |
| Async/Concurrency | If applicable | Async patterns, thread safety, race conditions |
| Database/Persistence | If applicable | ORM patterns, migrations, query optimization |
| API Design | If applicable | REST conventions, versioning, pagination |
| Accessibility | If frontend | Keyboard nav, ARIA, color contrast, screen readers |
| State Management | If frontend | Where state lives, when to use what |

Score: sections present / sections required. Target: 100%.

### 7.2 Pass 2 — Agent Coverage Audit

Verify every pipeline stage handles all component types:

| Agent | Backend | Frontend | Mobile | Infra | Cross-repo |
|-------|---------|----------|--------|-------|------------|
| pl-010-shaper | Features | Features | Features | Infra changes | Identifies repos |
| pl-100-orchestrator | Backend stack | Frontend stack | Mobile stack | Infra stack | Multi-repo coord |
| pl-200-planner | Backend tasks | Frontend tasks | Mobile tasks | Infra tasks | Cross-repo tasks |
| pl-210-validator | All 6 perspectives | All 6 perspectives | All 6 perspectives | Infra-specific | Contract validation |
| pl-300-implementer | TDD + backend | TDD + frontend | TDD + mobile | IaC patterns | Multi-worktree |
| pl-400-quality-gate | Backend reviewers | Frontend reviewers | Mobile reviewers | Infra reviewers | Contract reviewer |
| pl-500-test-gate | Backend suite | Frontend suite | Mobile suite | Helm lint | Cross-repo specs |
| pl-600-pr-builder | Single PR | Single PR | Single PR | Single PR | Linked PRs |

Every cell must have a concrete mechanism. Empty cells are gaps.

### 7.3 Pass 3 — End-to-End Scenario Testing

10 scenarios for walkthrough validation:

1. Simple backend feature — new CRUD endpoint in Spring+Kotlin
2. Full-stack feature — backend API + frontend UI in monorepo
3. Cross-repo feature — BE API change requiring FE type updates in separate repo
4. Mobile feature — Jetpack Compose screen with ViewModel + API call
5. Infrastructure change — new K8s deployment for a microservice
6. KMP shared module — business logic in commonMain consumed by Android + iOS
7. Vague requirement through shaping — user says "I want notifications"
8. Monorepo with 3 components — BE + FE + infra in one repo
9. Migration — upgrade Spring Boot version with breaking changes
10. Legacy codebase with no tests — test bootstrapper, then feature

### 7.4 Fix Loop

After each fix round:
1. Re-run convention completeness audit (automated: check section headers)
2. Re-run agent coverage audit (read agent files)
3. Re-run scenario walkthroughs for affected scenarios
4. Run `./tests/run-all.sh` for structural integrity
5. If new gaps found -> fix -> repeat
6. Stop when: all conventions 100%, all agent cells filled, all 10 scenarios pass, tests green

---

## 8. Implementation Scope Summary

| Area | What Changes |
|------|-------------|
| **Module structure** | Replace `modules/` with `languages/`, `frameworks/`, `testing/` three-layer system |
| **Config format** | `dev-pipeline.local.md` gains `components:` (multi-stack) and `related_projects:` |
| **New agent** | `pl-010-shaper` — interactive feature brainstorming |
| **New skill** | `/pipeline-shape` — entry point for shaping |
| **New shared doc** | `shared/agent-philosophy.md` — systemic critical thinking |
| **Orchestrator** | Multi-component resolution, convention stack composition, cross-repo coordination |
| **Pipeline-init** | 5-step cross-repo discovery chain |
| **Planner** | Challenge Brief requirement, approach quality tracking |
| **Validator** | New Perspective 6: Approach Quality |
| **All agents** | Reference `agent-philosophy.md`, APPROACH-* finding category |
| **PR builder** | Linked PRs across repos |
| **Contract validator** | Auto-diff API specs across repos |
| **Stage contract** | Multi-component VERIFY/REVIEW, per-component state tracking |
| **Scoring** | New APPROACH-* category (INFO, -2) |
| **Check engine** | Component-aware rule routing |
| **New frameworks** | ASP.NET, Django, Next.js, Gin, Jetpack Compose, Kotlin Multiplatform |
| **Migrated frameworks** | All 12 existing modules decomposed into new structure |
| **Testing conventions** | 12 testing framework files, testcontainers shared doc, playwright shared doc |
| **Language conventions** | 10 language files extracted from existing modules |
| **Gap review** | 3-pass audit after implementation |

### 8.1 State Schema Changes (semver reset to v1.0.0)

**New version:** 1.0.0 (semver reset — aligns with plugin v1.0.0). Previous schema versions (1.1, 1.2, 1.3) are superseded. No migration from old schemas — this is a clean break.

**New/modified fields:**

```json
{
  "version": "1.0.0",
  "components": {
    "backend": {
      "story_state": "IMPLEMENTING",
      "conventions_hash": "ab12cd34",
      "detected_versions": { "language_version": "2.0.0", "framework_version": "3.3.0" }
    },
    "frontend": {
      "story_state": "EXPLORING",
      "conventions_hash": "ef56gh78",
      "detected_versions": { "language_version": "5.4.0", "framework_version": "18.2.0" }
    }
  },
  "cross_repo": {
    "frontend": {
      "path": "...",
      "branch": "...",
      "status": "implementing|complete|failed",
      "files_changed": []
    }
  },
  "active_component": "backend"
}
```

**Key changes from previous schema:**
- `story_state` moves inside `components.{name}` (per-component state tracking)
- Top-level `story_state` remains as the "overall" state (highest active stage across all components)
- `conventions_hash` and `detected_versions` move inside components
- New `cross_repo` field for related project worktree tracking
- New `active_component` field indicating which component the orchestrator is currently processing
- `conventions_section_hashes` replaced by per-component `conventions_hash` (section-level hashing remains but is computed from the composed convention stack, not a single file)

**No migration from old schemas.** This is a clean break aligned with the module restructuring. Old `.pipeline/state.json` files are incompatible — `/pipeline-reset` clears them.

### 8.2 Test Suite Migration

The existing 233 tests validate the old `modules/*` structure. After restructuring:

**Structural tests (25):** Update path checks from `modules/*/conventions.md` to `modules/frameworks/*/conventions.md`. Add checks for `modules/languages/*.md` and `modules/testing/*.md`. Update module count assertions.

**Contract tests (87):** Update agent frontmatter references if any mention module paths. Update module-completeness checks for the new 5-file-per-framework requirement. Add contract tests for the new convention composition logic.

**Unit tests (82):** Check engine tests may need updated fixture paths if module detection logic changes. Linter adapter tests for new adapters (dotnet-format, golangci-lint, android-lint).

**Scenario tests (39):** Update module-override scenarios for the new directory structure. Add scenarios for multi-component check engine routing.

**Approach:** Update tests first (test-driven). Write failing structural tests for the new directory layout, then restructure to make them pass. This prevents accidentally shipping a structure that doesn't match what tests expect.
