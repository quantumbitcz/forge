---
project_type: backend
components:
  language: ruby
  framework: rails
  variant: hotwire           # hotwire | activerecord | api-only | engine
  testing: rspec             # rspec | minitest
  persistence: activerecord
  migrations: activerecord   # ActiveRecord migrations (db/migrate/)
  auth: devise               # devise | sorcery | clearance | rodauth | null
  # build_system: bundler    # bundler (default for Ruby)
  # ci: github-actions       # github-actions | gitlab-ci | jenkins | circleci | azure-pipelines | bitbucket-pipelines | tekton
  # container: docker        # docker | docker-compose | podman
  # orchestrator: kamal      # kamal (Rails 8 default) | helm | argocd | fluxcd | docker-swarm
  code_quality: []
  code_quality_recommended: [rubocop, rubocop-rails, rubocop-rspec, brakeman, bundler-audit, simplecov, yard]

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "bin/rails zeitwerk:check"
  build_alt: "bundle exec ruby -c config/application.rb"
  lint: "bundle exec rubocop --parallel"
  test: "bundle exec rspec"
  test_alt: "bin/rails spec"
  test_single: "bundle exec rspec -e"
  format: "bundle exec rubocop -A"
  migrate: "bin/rails db:migrate"
  makemigrations: "bin/rails generate migration"
  security_scan: "bundle exec brakeman --no-pager && bundle exec bundle-audit check --update"
  build_timeout: 180
  test_timeout: 600
  lint_timeout: 90

scaffolder:
  enabled: true
  patterns:
    controller: "app/controllers/{feature}_controller.rb"
    model: "app/models/{feature}.rb"
    service: "app/services/{feature}/{action}.rb"
    form: "app/forms/{feature}/{name}_form.rb"
    query: "app/queries/{feature}/{name}_query.rb"
    policy: "app/policies/{feature}_policy.rb"
    job: "app/jobs/{feature}_job.rb"
    mailer: "app/mailers/{feature}_mailer.rb"
    view: "app/views/{feature}/{action}.html.erb"
    stimulus: "app/javascript/controllers/{name}_controller.js"
    migration: "db/migrate/{timestamp}_{description}.rb"
    factory: "spec/factories/{feature}.rb"
    request_spec: "spec/requests/{feature}_spec.rb"
    model_spec: "spec/models/{feature}_spec.rb"
    system_spec: "spec/system/{feature}_spec.rb"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: fg-412-architecture-reviewer
      focus: "controller/service/model boundaries, fat controllers, callback abuse, default_scope"
    - agent: fg-411-security-reviewer
      focus: "strong params, mass assignment, raw SQL, CSRF, debug routes, credentials"
    - agent: fg-416-performance-reviewer
      focus: "N+1 via missing includes, fat queries in views, update_all without scope, deliver_now"
  batch_2:
    - agent: fg-410-code-reviewer
      focus: "general correctness, RuboCop deviations, error handling, DRY/KISS"
    - agent: fg-417-dependency-reviewer
      condition: manifest_changed
      focus: "vulnerable, outdated, unmaintained gems; bundler-audit advisories"
    - agent: fg-418-docs-consistency-reviewer
      focus: "code-docs consistency, decision violations, stale documentation"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"
  inline_checks:
    - script: "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --verify"

test_gate:
  command: "bundle exec rspec"
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/rails/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/rails/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/rails/testing/${components.testing}.md"
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
  - "rails"
  - "activerecord"
  - "actioncontroller"
  - "actionview"
  - "actioncable"
  - "actionmailer"
  - "activejob"
  - "turbo-rails"
  - "stimulus-rails"
  - "rspec-rails"
  - "factory_bot"
  - "pundit"
  - "devise"

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

## Rails Backend Context

Rails 8.x with Hotwire (Turbo + Stimulus), Solid Queue / Cache / Cable (DB-backed defaults — no Redis required),
Propshaft for assets, and Importmap for JS by default. Business logic in service objects under `app/services/`,
forms via ActiveModel-backed form objects, complex reads in `app/queries/`. Persistence via ActiveRecord with
strong-migrations enforced. Auth via Devise sessions; authorization via Pundit policies. Background work via
ActiveJob (`solid_queue` adapter). Mailers always `.deliver_later`.

### Variant: hotwire (default)
Turbo Drive + Frames + Streams + Stimulus. Server-rendered HTML with progressive enhancement; no separate
JS frontend. Streams pushed via `turbo_stream_from` over `solid_cable`. Use Stimulus controllers (kebab-case)
for client-side behaviour, one responsibility per controller.

Customize `components.variant`, `components.testing`, `components.auth`, commands, and scaffolder
patterns to match your project layout.
