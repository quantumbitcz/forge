---
project_type: backend
components:
  language: php
  framework: laravel
  variant: eloquent          # eloquent | artisan | livewire | inertia | api-only
  testing: phpunit
  persistence: eloquent
  migrations: laravel-migrations
  auth: sanctum             # sanctum | passport | breeze | null
  # build_system: composer
  # ci: github-actions       # github-actions | gitlab-ci | jenkins | circleci | azure-pipelines | bitbucket-pipelines | tekton
  # container: docker        # docker | docker-compose | podman
  # orchestrator: helm       # helm | docker-swarm | argocd | fluxcd
  code_quality: []
  code_quality_recommended: [pint, phpstan, larastan, php-cs-fixer, infection, psalm]

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "php artisan optimize"
  build_alt: "composer dump-autoload && php artisan config:cache"
  lint: "./vendor/bin/pint --test"
  lint_alt: "./vendor/bin/phpstan analyse"
  test: "php artisan test"
  test_alt: "./vendor/bin/phpunit"
  test_single: "php artisan test --filter"
  format: "./vendor/bin/pint"
  migrate: "php artisan migrate --force"
  makemigrations: "php artisan make:migration"
  build_timeout: 180
  test_timeout: 600
  lint_timeout: 60

scaffolder:
  enabled: true
  patterns:
    controller: "app/Http/Controllers/{Feature}Controller.php"
    request: "app/Http/Requests/{Feature}/Store{Feature}Request.php"
    resource: "app/Http/Resources/{Feature}Resource.php"
    service: "app/Services/{Feature}Service.php"
    action: "app/Actions/{Feature}/{Verb}{Feature}Action.php"
    model: "app/Models/{Feature}.php"
    policy: "app/Policies/{Feature}Policy.php"
    job: "app/Jobs/{Verb}{Feature}Job.php"
    event: "app/Events/{Feature}{PastTense}Event.php"
    listener: "app/Listeners/Send{Feature}NotificationListener.php"
    observer: "app/Observers/{Feature}Observer.php"
    migration: "database/migrations/{timestamp}_{verb}_{table}_table.php"
    factory: "database/factories/{Feature}Factory.php"
    seeder: "database/seeders/{Feature}Seeder.php"
    test_feature: "tests/Feature/{Feature}{Behavior}Test.php"
    test_unit: "tests/Unit/Services/{Feature}ServiceTest.php"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: fg-412-architecture-reviewer
      focus: "controller/service/action layering, business logic in controllers, Eloquent in views"
    - agent: fg-411-security-reviewer
      focus: "mass assignment, $fillable discipline, env() outside config, csrf exempts, raw SQL, policy enforcement"
    - agent: fg-416-performance-reviewer
      focus: "N+1 from missing eager loads, missing preventLazyLoading, whereHas in loops, missing pagination"
  batch_2:
    - agent: fg-410-code-reviewer
      focus: "general correctness, maintainability, error handling, DRY/KISS, FormRequest discipline"
    - agent: fg-417-dependency-reviewer
      condition: manifest_changed
      focus: "vulnerable, outdated, unmaintained Composer packages"
    - agent: fg-418-docs-consistency-reviewer
      focus: "code-docs consistency, decision violations, stale documentation"
    - agent: "pr-review-toolkit:code-reviewer"
      source: plugin
      focus: "CLAUDE.md adherence"
  inline_checks:
    - script: "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --verify"

test_gate:
  command: "php artisan test"
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

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/laravel/conventions.md"
conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/laravel/variants/${components.variant}.md"
conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/laravel/testing/${components.testing}.md"
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
  - "laravel/framework"
  - "laravel/sanctum"
  - "laravel/passport"
  - "laravel/breeze"
  - "laravel/horizon"
  - "laravel/telescope"
  - "laravel/pint"
  - "spatie/laravel-permission"
  - "phpunit/phpunit"

graph:
  enabled: true
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

project_name: TODO
artisan_entrypoint: artisan
---

## Laravel Backend Context

Laravel 11.x with the streamlined skeleton (`bootstrap/app.php` configuration, `routes/console.php`
for scheduling, no `App\Http\Kernel`). Business logic lives in services and actions, never in
controllers or Blade templates. Persistence via Eloquent with `$fillable` allowlists, eager
loading at the query site, and `Model::preventLazyLoading()` enabled in non-prod.

Validation runs through `FormRequest` classes; authorization through Policies invoked from
`$this->authorize(...)`. Slow work (mail, third-party API calls, batch updates) goes through
queued jobs that implement `ShouldQueue + SerializesModels`.

### Variant: eloquent (default)
ORM-centric variant. Eloquent models with explicit relationships, accessors via `Attribute::make`,
typed casts, observer-driven lifecycle hooks. JSON serialization via `JsonResource` /
`ResourceCollection`. See `modules/frameworks/laravel/variants/eloquent.md`.

Customize `components.variant`, `components.testing`, `components.auth`, commands, and
scaffolder patterns to match your project layout.
