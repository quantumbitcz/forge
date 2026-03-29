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
    - agent: architecture-reviewer
      focus: "MTV layering violations, business logic in views, direct ORM in views"
    - agent: security-reviewer
      focus: "auth, permissions, SQL injection risk, ALLOWED_HOSTS, DEBUG, secrets"
    - agent: backend-performance-reviewer
      focus: "N+1 queries, missing select_related/prefetch_related, queryset in loops"
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
language_file: "${CLAUDE_PLUGIN_ROOT}/modules/languages/${components.language}.md"
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

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

graph:
  enabled: false          # set to true to enable Neo4j knowledge graph
  enrich_symbols: true
  neo4j_port: 7687
  neo4j_http_port: 7474
