---
project_type: backend
components:
  language: csharp
  framework: aspnet
  variant: csharp
  testing: xunit-nunit
  persistence: efcore        # efcore (only supported option currently)
  # build_system: dotnet       # dotnet (msbuild)
  # ci: github-actions         # github-actions | gitlab-ci | jenkins | circleci | azure-pipelines | bitbucket-pipelines | tekton
  # container: docker          # docker | docker-compose | podman
  # orchestrator: helm         # helm | docker-swarm | argocd | fluxcd | openshift
  code_quality: []
  code_quality_recommended: [roslyn-analyzers, dotnet-format, coverlet, xmldoc, dotnet-audit, stryker]

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "dotnet build --no-restore"
  lint: "dotnet format --verify-no-changes"
  test: "dotnet test"
  test_single: "dotnet test --filter"
  format: "dotnet format"
  build_timeout: 120
  test_timeout: 300
  lint_timeout: 60

scaffolder:
  enabled: true
  patterns:
    controller: "src/{AppName}.Api/Controllers/{Entity}Controller.cs"
    service_interface: "src/{AppName}.Application/Interfaces/I{Entity}Service.cs"
    service: "src/{AppName}.Application/Services/{Entity}Service.cs"
    repository_interface: "src/{AppName}.Application/Interfaces/I{Entity}Repository.cs"
    repository: "src/{AppName}.Infrastructure/Repositories/{Entity}Repository.cs"
    entity: "src/{AppName}.Domain/Entities/{Entity}.cs"
    request_dto: "src/{AppName}.Application/DTOs/{Entity}Requests.cs"
    response_dto: "src/{AppName}.Application/DTOs/{Entity}Response.cs"
    migration: "src/{AppName}.Infrastructure/Migrations/{Timestamp}_{Description}.cs"
    test: "tests/{AppName}.Api.Tests/{Entity}ApiTests.cs"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: architecture-reviewer
      focus: "Clean Architecture layer violations, controller logic boundary"
    - agent: security-reviewer
      focus: "auth, ownership, injection, secrets, CORS misconfiguration"
    - agent: backend-performance-reviewer
      focus: "N+1 queries, sync-over-async, missing AsNoTracking, EF Core efficiency"
  batch_2:
    - agent: "Code Reviewer"
      source: builtin
      focus: "general correctness, maintainability"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"
    - agent: docs-consistency-reviewer
      focus: "code-docs consistency, decision violations, stale documentation"
  inline_checks:
    - script: "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --verify"

test_gate:
  command: "dotnet test"
  max_test_cycles: 2
  analysis_agents:
    - agent: "pr-review-toolkit:pr-test-analyzer"
      source: plugin

validation:
  perspectives: [architecture, security, edge_cases, test_strategy, conventions, approach_quality, documentation_consistency]
  max_validation_retries: 2

implementation:
  parallel_threshold: 3
  max_fix_loops: 3
  tdd: true
  scaffolder_before_impl: true

risk:
  auto_proceed: MEDIUM

linear:
  enabled: false
  team: ""
  project: ""
  labels: ["pipeline-managed"]

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/aspnet/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/aspnet/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/aspnet/testing/${components.testing}.md"
conventions_persistence: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/aspnet/persistence/${components.persistence}.md"
conventions_code_quality: "${CLAUDE_PLUGIN_ROOT}/modules/code-quality/"
conventions_code_quality_binding: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/aspnet/code-quality/"
language_file: "${CLAUDE_PLUGIN_ROOT}/modules/languages/${components.language}.md"
preempt_file: ".claude/forge-log.md"
config_file: ".claude/forge-config.md"

documentation:
  enabled: true
  output_dir: docs/
  auto_generate:
    readme: true
    architecture: true
    adrs: true
    api_docs: true
    onboarding: true
    changelogs: true
    diagrams: true
    domain_docs: true
    runbooks: false
    user_guides: false
    migration_guides: true
  discovery:
    max_files: 500
    max_file_size_kb: 512
    exclude_patterns: []
  external_sources: []
  export:
    confluence:
      enabled: false
    notion:
      enabled: false
  user_maintained_marker: "<!-- user-maintained -->"

context7_libraries:
  - "aspnet-core"
  - "aspnet-identity"
  - "xunit"
  - "fluentassertions"
  # Persistence — uncomment based on components.persistence:
  # efcore (default):
  - "entity-framework-core"

graph:
  enabled: true           # set to false if Docker is unavailable
  enrich_symbols: true
  neo4j_port: 7687
  neo4j_http_port: 7474

# Git conventions (auto-detected or configured by /forge-init)
git:
  branch_template: "{type}/{ticket}-{slug}"
  branch_types: [feat, fix, refactor, chore]
  slug_max_length: 40
  ticket_source: auto
  commit_format: conventional
  commit_types: [feat, fix, test, refactor, docs, chore, perf, ci]
  commit_scopes: auto
  max_subject_length: 72
  require_scope: false
  sign_commits: false
  # commit_enforcement: external  # Uncomment if project has its own hooks

# Kanban tracking
tracking:
  prefix: FG
  archive_after_days: 90  # Auto-archive done/ tickets (30-365, 0=disabled)
  # enabled: true  # Set to false to disable tracking
---

## ASP.NET Core Backend Context

ASP.NET Core with Clean Architecture (Controllers → Application → Domain → Infrastructure).
DTOs at controller boundary; entities never leak to API. Constructor injection only.

Persistence layer is configurable via `components.persistence`.

### Variant: C# (default)
Nullable reference types enabled. Record DTOs for requests/responses.
Primary constructors for services. Options pattern for configuration.

Customize `components.language`, `components.variant`, `components.testing`, `components.persistence`,
commands, and scaffolder patterns to match your project layout.
