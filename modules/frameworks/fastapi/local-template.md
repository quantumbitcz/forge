---
project_type: backend
components:
  language: python
  framework: fastapi
  variant: python
  testing: pytest
  persistence: sqlalchemy    # sqlalchemy (only supported option currently)
  # build_system: uv           # uv | pip | poetry
  # ci: github-actions         # github-actions | gitlab-ci | jenkins | circleci | azure-pipelines | bitbucket-pipelines | tekton
  # container: docker          # docker | docker-compose | podman
  # orchestrator: helm         # helm | docker-swarm | argocd | fluxcd
  code_quality: []
  code_quality_recommended: [ruff, mypy, coverage-py, sphinx, safety, mutmut]

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "uv run python -m py_compile main.py"
  build_alt: "python -m compileall ."
  lint: "ruff check ."
  test: "uv run pytest"
  test_alt: "pytest"
  test_single: "uv run pytest -k"
  format: "ruff format ."
  build_timeout: 120
  test_timeout: 300
  lint_timeout: 60

scaffolder:
  enabled: true
  patterns:
    router: "app/routers/{area}.py"
    service: "app/services/{area}_service.py"
    repository: "app/repositories/{area}_repository.py"
    model: "app/models/{area}.py"
    schema: "app/schemas/{area}.py"
    migration: "app/migrations/versions/{rev}_{description}.py"
    test: "tests/test_{area}.py"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: architecture-reviewer
      focus: "router/service/repository layering violations"
    - agent: security-reviewer
      focus: "auth, injection, data exposure, CORS"
    - agent: backend-performance-reviewer
      focus: "N+1 queries, blocking I/O, algorithm complexity, DB efficiency"
  batch_2:
    - agent: "Code Reviewer"
      source: builtin
      focus: "general correctness, maintainability"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"
    - agent: docs-consistency-reviewer
      focus: "code-docs consistency, decision violations, stale documentation"

test_gate:
  command: "uv run pytest"
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/fastapi/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/fastapi/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/fastapi/testing/${components.testing}.md"
conventions_persistence: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/fastapi/persistence/${components.persistence}.md"
conventions_code_quality: "${CLAUDE_PLUGIN_ROOT}/modules/code-quality/"
conventions_code_quality_binding: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/fastapi/code-quality/"
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
  - "fastapi"
  - "pydantic"
  - "pytest"
  - "uvicorn"
  # Persistence — uncomment based on components.persistence:
  # sqlalchemy (default):
  - "sqlalchemy"
  - "alembic"

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
  # enabled: true  # Set to false to disable tracking
---

## Python/FastAPI Backend Context

Router/Service/Repository layering with async-first design. All endpoints use Pydantic models
for request/response validation. Dependency injection via Depends().

Persistence layer is configurable via `components.persistence`. Customize along with commands
and scaffolder patterns to match your project.
