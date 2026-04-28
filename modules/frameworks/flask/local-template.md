---
project_type: backend
components:
  language: python
  framework: flask
  variant: factory          # factory | blueprint | extension-stack
  testing: pytest
  persistence: sqlalchemy
  migrations: alembic       # alembic (Flask-Migrate wraps it)
  auth: flask-login         # flask-login | itsdangerous | authlib | null
  # build_system: uv         # uv | pip | poetry | pdm
  # ci: github-actions       # github-actions | gitlab-ci | jenkins | circleci | azure-pipelines | bitbucket-pipelines | tekton
  # container: docker        # docker | docker-compose | podman
  # orchestrator: helm       # helm | docker-swarm | argocd | fluxcd
  code_quality: []
  code_quality_recommended: [ruff, mypy, coverage-py, sphinx, safety, mutmut]

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "python -m compileall app"
  build_alt: "flask --app wsgi check"
  lint: "ruff check . && mypy ."
  test: "pytest"
  test_alt: "uv run pytest"
  test_single: "pytest -k"
  format: "ruff format ."
  migrate: "flask db upgrade"
  makemigrations: "flask db migrate"
  build_timeout: 120
  test_timeout: 300
  lint_timeout: 60

scaffolder:
  enabled: true
  patterns:
    blueprint: "app/{feature}/__init__.py"
    routes: "app/{feature}/routes.py"
    service: "app/{feature}/services.py"
    model: "app/{feature}/models.py"
    form: "app/{feature}/forms.py"
    schema: "app/{feature}/schemas.py"
    migration: "migrations/versions/{N}_{description}.py"
    factory: "tests/factories/{feature}.py"
    test: "tests/test_{feature}_{behaviour}.py"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: fg-412-architecture-reviewer
      focus: "blueprint/services/routes layering, business logic in routes, ORM in routes"
    - agent: fg-411-security-reviewer
      focus: "session cookie flags, CSRF, debug mode, SECRET_KEY, raw SQL, mass assignment"
    - agent: fg-416-performance-reviewer
      focus: "N+1 via lazy load, missing selectinload/joinedload, before_request cost"
  batch_2:
    - agent: fg-410-code-reviewer
      focus: "general correctness, maintainability, error handling, DRY/KISS"
    - agent: fg-417-dependency-reviewer
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/flask/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/flask/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/flask/testing/${components.testing}.md"
conventions_persistence: "${CLAUDE_PLUGIN_ROOT}/modules/persistence/${components.persistence}.md"
conventions_code_quality: "${CLAUDE_PLUGIN_ROOT}/modules/code-quality/"
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
  - "flask"
  - "flask-sqlalchemy"
  - "flask-migrate"
  - "flask-login"
  - "flask-wtf"
  - "pytest-flask"
  - "werkzeug"

graph:
  enabled: true           # set to false if Docker is unavailable
  enrich_symbols: true
  neo4j_port: 7687
  neo4j_http_port: 7474

# Git conventions (auto-detected or configured by /forge)
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

## Flask Backend Context

Flask 3.x with the application factory pattern + Blueprints + a services layer.
Business logic lives in services, never in routes or templates. Persistence via Flask-SQLAlchemy
2.0-style queries (`db.session.execute(db.select(Model))`). Forms via Flask-WTF with CSRF on every
browser form. Auth via Flask-Login session cookies (or itsdangerous tokens for APIs). Migrations
via Flask-Migrate / Alembic.

### Variant: factory (default)
Application factory in `app/__init__.py` with module-level extension singletons in `app/extensions.py`.
Blueprints registered inside `create_app`. Per-test app instances enable isolated DBs and config swapping.

Customize `components.variant`, `components.testing`, commands, and scaffolder patterns
to match your project layout.
