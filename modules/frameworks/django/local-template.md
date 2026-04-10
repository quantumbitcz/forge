---
project_type: backend
components:
  language: python
  framework: django
  variant: python
  testing: pytest
  persistence: django-orm
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
  build: "python manage.py check --deploy"
  build_alt: "python manage.py check"
  lint: "ruff check . && mypy ."
  test: "pytest"
  test_alt: "uv run pytest"
  test_single: "pytest -k"
  format: "ruff format ."
  migrate: "python manage.py migrate"
  makemigrations: "python manage.py makemigrations"
  build_timeout: 120
  test_timeout: 300
  lint_timeout: 60

scaffolder:
  enabled: true
  patterns:
    model: "{app}/models.py"
    serializer: "{app}/serializers.py"
    service: "{app}/services.py"
    viewset: "{app}/views.py"
    urls: "{app}/urls.py"
    migration: "{app}/migrations/{N:04d}_{description}.py"
    factory: "tests/factories/{app}.py"
    test: "tests/test_{app}_{feature}.py"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: fg-412-architecture-reviewer
      focus: "MTV layering violations, business logic in views, direct ORM in views"
    - agent: fg-411-security-reviewer
      focus: "auth, permissions, SQL injection risk, ALLOWED_HOSTS, DEBUG, secrets"
    - agent: fg-416-backend-performance-reviewer
      focus: "N+1 queries, missing select_related/prefetch_related, queryset in loops"
  batch_2:
    - agent: fg-410-code-reviewer
      focus: "general correctness, maintainability, error handling, DRY/KISS"
    - agent: fg-420-dependency-reviewer
      condition: manifest_changed
      focus: "vulnerable, outdated, unmaintained dependencies"
    - agent: fg-418-docs-consistency-reviewer
      focus: "code-docs consistency, decision violations, stale documentation"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"
  inline_checks:
    - script: "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --verify"

test_gate:
  command: "pytest"
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/django/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/django/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/django/testing/${components.testing}.md"
conventions_persistence: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/django/persistence/${components.persistence}.md"
conventions_code_quality: "${CLAUDE_PLUGIN_ROOT}/modules/code-quality/"
conventions_code_quality_binding: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/django/code-quality/"
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
  - "django"
  - "djangorestframework"
  - "django-filter"
  - "celery"
  - "pytest-django"
  - "factory-boy"

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

## Django Backend Context

Django with MTV architecture + services layer (DRF for APIs).
Business logic lives in services, not in views or models. ORM-only data access.
DRF ViewSets + Routers for REST API; serializers for all input/output validation.

### Variant: Python (default)
Type hints throughout with django-stubs and mypy. TextChoices for model enums.
factory_boy for test data. ruff for linting/formatting.

Customize `components.variant`, `components.testing`, commands,
and scaffolder patterns to match your project layout.
