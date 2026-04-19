# Phase 08 — Module Additions (Flask, Laravel, Rails, Swift Concurrency)

> **Roadmap:** A+ Phase 08, priority P1. Single-PR delivery.
> **Scope:** Additive. No backwards compatibility concerns. CI-driven verification only.

---

## 1. Goal

Add three new framework bindings (Flask, Laravel, Rails) at depth parity with existing first-class frameworks (Django for Flask; Spring for Laravel and Rails) and extend `modules/languages/swift.md` with a first-class Swift 5.5+ structured concurrency section, closing audit finding W7.

## 2. Motivation

Audit finding **W7 (missing major frameworks)** flagged three P1 gaps and one P2 gap in the framework/language coverage matrix:

| Stack | Gap | Current state | Target |
|---|---|---|---|
| Python / Flask | Missing entirely | `modules/frameworks/{django,fastapi}/` exist; no Flask | Parity with Django |
| PHP / Laravel | No PHP framework bindings at all | `modules/languages/php.md` exists; zero framework modules | Parity with Spring |
| Ruby / Rails | No Ruby framework bindings at all | `modules/languages/ruby.md` exists; zero framework modules | Parity with Spring |
| Swift / async-await | Underrepresented (~5 lines in existing Concurrency section) | Brief mentions of `@MainActor`, `async let`, `actor` | +~200 lines covering Task, TaskGroup, structured concurrency, actor isolation, cancellation, AsyncSequence |

**Secondary signal:** Flask is the third-largest Python web framework by deployment share; Laravel dominates PHP server-side work; Rails remains the canonical Ruby web stack. Absence blocks `/forge-init` auto-detection, `fg-130-docs-discoverer` context loading, and reviewer convention enforcement for any project using these stacks. A PHP/Ruby consumer today receives language-only coverage with no framework idioms, routing conventions, ORM patterns, or deprecation registry — essentially a degraded pipeline.

**Audit cross-reference:** The audit also flagged `CLAUDE.md:16` claiming "21" frameworks while `modules/frameworks/` contains 23 directories (including `VARIANTS.md`, `base-template.md` — 21 actual framework dirs today). Phase 06 fixes the count string; Phase 08 adds 3 new frameworks bringing the true count to 24. This spec records the post-Phase-08 target count and verifies CLAUDE.md alignment as a gate.

## 3. Scope

### In scope

- **`modules/frameworks/flask/`** — Full convention bundle matching Django depth:
  - `conventions.md`, `local-template.md`, `forge-config-template.md`, `rules-override.json`, `known-deprecations.json`
  - `variants/` subdirectory: Blueprint-centric layouts, application factory pattern, extension-based (Flask-Login, Flask-SQLAlchemy, Flask-Migrate)
  - `testing/` binding: pytest with Flask test client + application factory fixtures
- **`modules/frameworks/laravel/`** — Full convention bundle matching Spring depth:
  - Standard five files as above
  - `variants/`: Artisan-command-driven apps, Eloquent-centric, Livewire (server-rendered reactive), Inertia (SPA-coupled), API-only (Sanctum)
  - `testing/`: PHPUnit binding (Laravel HTTP tests, database transactions, Mockery)
- **`modules/frameworks/rails/`** — Full convention bundle matching Spring depth:
  - Standard five files
  - `variants/`: Hotwire (Turbo + Stimulus), ActiveRecord-centric, API-only, Engine-based (multi-tenant)
  - `testing/`: RSpec binding (factory_bot, request specs, system specs with Capybara)
- **`modules/languages/swift.md`** — Extend existing file with ~200-line structured concurrency section covering:
  - `Task { }`, `Task.detached`, `Task.sleep`, task priority, task cancellation (cooperative cancellation, `Task.isCancelled`, `checkCancellation()`)
  - `TaskGroup` / `ThrowingTaskGroup` / `withTaskGroup` / `withThrowingTaskGroup` with when to use vs `async let`
  - `async let` parallelism rules and implicit cancellation
  - Structured vs unstructured concurrency (when `Task.detached` is justified)
  - `actor` isolation rules: reentrancy, `nonisolated`, `isolated` parameters, `@MainActor` propagation
  - Sendable conformance (`Sendable`, `@unchecked Sendable`, region-based isolation in Swift 6)
  - `AsyncSequence` / `AsyncStream` / `AsyncThrowingStream` for async iteration
  - `Continuation` bridges (`withCheckedContinuation`, `withUnsafeContinuation`) for C/Obj-C interop
  - Common pitfalls: priority inversion, actor reentrancy bugs, unstructured task leaks, `Task.detached` anti-pattern
- **`shared/learnings/flask.md`**, **`shared/learnings/laravel.md`**, **`shared/learnings/rails.md`** — New learnings files seeded with common pitfalls discovered during spec authoring (N+1 patterns, mass assignment, security baselines)
- **`tests/lib/module-lists.bash`** — Bump `MIN_FRAMEWORKS` from current value (21) to **24**
- **`CLAUDE.md` alignment** — Phase 06 owns the string fix; Phase 08 verifies count math reconciles (21 audit baseline + 3 new = 24) and adds the three framework names to the `frameworks/` enumeration

### Out of scope

- Elixir Phoenix, Python Starlette, Rust Actix-web — deferred to Phase 16+
- Retroactive convention audits of existing framework modules
- Swift 6 strict-concurrency migration tooling (beyond covering the rules in conventions)
- PHP language module enhancements beyond what Laravel's conventions require
- Ruby language module enhancements beyond what Rails requires
- Migration modules (`modules/migrations/`) specific to Rails or Laravel migrations
- Framework-specific observability bindings (OpenTelemetry integrations)
- Eval harness infrastructure itself — produced by Phase 01; this spec consumes it

## 4. Architecture

### 4.1 File layout per new framework

Mirrors the existing `modules/frameworks/django/` layout exactly. Example for Flask:

```
modules/frameworks/flask/
├── conventions.md                  # Primary convention doc (Architecture, DI, ORM, Security, Testing, Dos/Don'ts)
├── local-template.md               # Seeded into `.claude/forge.local.md` on init
├── forge-config-template.md        # Seeded into `.claude/forge-config.md` (MUST include total_retries_max, oscillation_tolerance)
├── rules-override.json             # Framework-specific L1 check-engine rules
├── known-deprecations.json         # Schema v2 deprecation registry (5-15 entries)
├── variants/
│   ├── blueprint.md                # Blueprint-based modular layout
│   ├── factory.md                  # Application factory pattern
│   └── extension-stack.md          # Flask-Login + Flask-SQLAlchemy + Flask-Migrate idioms
└── testing/
    └── pytest.md                   # Flask-specific pytest binding (client fixture, app fixture, DB rollback)
```

Laravel mirrors this layout with `variants/{artisan,eloquent,livewire,inertia,api-only}.md` and `testing/phpunit.md`. Rails mirrors with `variants/{hotwire,activerecord,api-only,engine}.md` and `testing/rspec.md`.

### 4.2 Composition order (per `shared/composition.md`)

Most-specific wins, top-down. For a Flask + SQLAlchemy + pytest project:

```
variant (flask/variants/factory.md)
  > framework-binding (flask/testing/pytest.md)
    > framework (flask/conventions.md)
      > language (python.md)
        > code-quality (ruff, mypy, etc.)
          > generic-layer (persistence/sqlalchemy.md)
            > testing (testing/pytest.md)
```

Each new framework's `testing/` binding extends the generic `modules/testing/{pytest,phpunit,rspec}.md` — framework-binding beats generic-testing in the composition order. Reviewers and the implementer see the fully-composed stack; conflicts resolve by position (higher-up wins).

### 4.3 Two alternatives considered

**Alternative A (rejected): Minimal skeleton.** Ship each framework with only `conventions.md` + `known-deprecations.json` (no variants, no testing binding, no rules-override). Rationale for rejection: produces a visibly second-class tier of frameworks. `/forge-init` would detect the framework but generate partial config. Reviewers would fall back to language-only rules, producing noisy reviews for idiomatic Flask/Laravel/Rails code. Composition order tests in `tests/scenario/` would emit synthetic warnings. The whole point of Phase 08 is closing the audit W7 gap — a skeleton half-closes it and guarantees a Phase 12 follow-up.

**Alternative B (chosen): Full Spring/Django-depth coverage.** Every new framework ships with the complete five-file bundle, variants subdirectory, testing binding, rules-override, deprecation registry, and learnings file. Rationale: this is what the audit asked for and what CLAUDE.md §"Adding new modules" codifies as the contract for any new framework. Anything less creates immediate technical debt.

**Depth target per framework:**
- Flask ≈ Django (similar scope: Python web framework, ORM-heavy, extension ecosystem). Target `conventions.md` length: ~400-500 lines, matching Django.
- Laravel ≈ Spring (full-stack: routing, ORM, auth, queues, events, cache, validation, mailers, artisan tooling). Target ~500-700 lines.
- Rails ≈ Spring (full-stack: routing, ActiveRecord, ActionCable, ActiveJob, ActionMailer, generators, engines). Target ~500-700 lines.

### 4.4 Swift async/await extension strategy

Extends the existing **Concurrency** section in `modules/languages/swift.md` (currently ~7 bullets) into a dedicated, structured subsection hierarchy:

```
## Concurrency                                  # existing header; retain
  (brief intro paragraph — existing)

### Task basics                                 # new
### TaskGroup and async let                     # new
### Structured vs unstructured concurrency      # new
### Actor isolation                             # new
### Sendable and data-race safety               # new
### AsyncSequence / AsyncStream                 # new
### Bridging legacy callbacks                   # new
### Concurrency anti-patterns                   # new
```

Each subsection is ~20-30 lines with code examples. Total addition: ~200 lines. The existing Dos/Don'ts section at the file tail is updated to add 5-7 new concurrency entries; nothing is removed. File grows from its current line count to ~315 lines — still comfortably under any token ceiling for a language module.

## 5. Components

Exact file inventory. Count verifications below match the caller's estimate (~50 files).

### 5.1 Flask (14 files)

| # | Path | Purpose |
|---|---|---|
| 1 | `modules/frameworks/flask/conventions.md` | Architecture (Blueprints, factory, layered services), routing, Jinja2, Flask-SQLAlchemy idioms, Flask-WTF validation, Flask-Login auth, error handlers, security (CSRF, session config, CORS via Flask-CORS), performance (connection pooling, caching with Flask-Caching), testing |
| 2 | `modules/frameworks/flask/local-template.md` | `.claude/forge.local.md` seed: component pinning (`framework: flask`, `persistence: sqlalchemy`, `testing: pytest`), project metadata placeholders |
| 3 | `modules/frameworks/flask/forge-config-template.md` | `.claude/forge-config.md` seed: Flask-specific scoring thresholds, reviewer selection overrides, `total_retries_max: 10`, `oscillation_tolerance: 3`, `inner_loop.enabled: true` |
| 4 | `modules/frameworks/flask/rules-override.json` | L1 rules: `NO_DEBUG_IN_PROD` (blocks `app.run(debug=True)`), `NO_HARDCODED_SECRET_KEY`, `REQUIRE_CSRF_FOR_FORMS`, `FORBID_RAW_SQL_CONCAT`, `REQUIRE_FACTORY_FOR_APP` — 8-12 rules |
| 5 | `modules/frameworks/flask/known-deprecations.json` | v2 schema, 8-10 entries covering: `flask.Markup` → `markupsafe.Markup` (Flask 2.3), `flask.json.JSONEncoder` → `app.json_encoder` custom provider (Flask 2.2), `Flask.before_first_request` removal (Flask 2.3), `flask.signals_available`, `session.permanent_session_lifetime` usage, Werkzeug deprecations |
| 6 | `modules/frameworks/flask/variants/blueprint.md` | Blueprint-per-feature module layout |
| 7 | `modules/frameworks/flask/variants/factory.md` | `create_app()` application factory pattern |
| 8 | `modules/frameworks/flask/variants/extension-stack.md` | Flask-Login + Flask-SQLAlchemy + Flask-Migrate + Flask-WTF conventions |
| 9 | `modules/frameworks/flask/testing/pytest.md` | pytest fixtures: `app`, `client`, `db`, `runner`; transaction-rollback pattern; `pytest-flask` integration; factory-driven fixture composition |
| 10 | `shared/learnings/flask.md` | Initial learnings: N+1 patterns, session-vs-request scope confusion, CSRF exemption misuse, debug-mode-in-prod, `@app.before_request` ordering |

Flask file count: 10 core files (the caller's "~15" estimate assumed more variants — actual Flask idiom only needs 3 variants).

### 5.2 Laravel (15 files)

| # | Path | Purpose |
|---|---|---|
| 1 | `modules/frameworks/laravel/conventions.md` | Architecture (Controller/Service/Repository or Action-based), Eloquent, migrations, validation (FormRequest), auth (Sanctum/Passport/Breeze), queues, events + listeners, broadcasting, cache, mail, artisan command design, service providers, middleware, policies/gates |
| 2 | `modules/frameworks/laravel/local-template.md` | Laravel pin (`framework: laravel`, `persistence: eloquent`, `testing: phpunit`) |
| 3 | `modules/frameworks/laravel/forge-config-template.md` | With `total_retries_max: 10`, `oscillation_tolerance: 3`, Laravel-specific reviewer weights |
| 4 | `modules/frameworks/laravel/rules-override.json` | `FORBID_DB_RAW`, `REQUIRE_FORM_REQUEST_VALIDATION`, `NO_MASS_ASSIGNMENT_WITHOUT_FILLABLE`, `REQUIRE_POLICY_FOR_MODEL`, `NO_ENV_OUTSIDE_CONFIG`, `REQUIRE_QUEUED_JOBS_FOR_SLOW_OPS` — 10-14 rules |
| 5 | `modules/frameworks/laravel/known-deprecations.json` | v2 schema, 10-12 entries: `Str::random` non-cryptographic uses, `Illuminate\Support\Facades\Input` removal, `Mail::send()` closures → Mailable classes, `Eloquent::unguard()` global usage, Laravel 10 `password_rules` helpers, `Bus::chain()` old syntax, `JsonResponse` wrapping |
| 6 | `modules/frameworks/laravel/variants/artisan.md` | Console-command-driven application variant |
| 7 | `modules/frameworks/laravel/variants/eloquent.md` | ORM-centric conventions (scopes, accessors/mutators, attribute casting, relationships, polymorphic) |
| 8 | `modules/frameworks/laravel/variants/livewire.md` | Livewire server-rendered reactive component conventions |
| 9 | `modules/frameworks/laravel/variants/inertia.md` | Inertia.js SPA-coupled conventions (shared data, partial reloads) |
| 10 | `modules/frameworks/laravel/variants/api-only.md` | Sanctum token auth, resource classes, versioning, rate limiting |
| 11 | `modules/frameworks/laravel/testing/phpunit.md` | Feature tests, `RefreshDatabase`, HTTP testing, factories, Mockery bindings, parallel testing via `artisan test --parallel` |
| 12 | `shared/learnings/laravel.md` | Mass assignment, N+1 from eager loading gaps, queue serialization of Eloquent models, `env()` outside config, implicit route model binding pitfalls |

Laravel file count: 12 core files.

### 5.3 Rails (14 files)

| # | Path | Purpose |
|---|---|---|
| 1 | `modules/frameworks/rails/conventions.md` | Architecture (MVC + Service objects + Form objects + Query objects), ActiveRecord, migrations, strong parameters, ActiveJob, ActionMailer, ActionCable, Pundit/CanCanCan policies, concerns, generators, engine design, I18n, asset pipeline vs Propshaft, importmaps |
| 2 | `modules/frameworks/rails/local-template.md` | Rails pin (`framework: rails`, `persistence: activerecord`, `testing: rspec`) |
| 3 | `modules/frameworks/rails/forge-config-template.md` | With `total_retries_max: 10`, `oscillation_tolerance: 3`, RuboCop-rails integration hints |
| 4 | `modules/frameworks/rails/rules-override.json` | `NO_MASS_ASSIGNMENT_WITHOUT_STRONG_PARAMS`, `REQUIRE_POLICY_ON_CONTROLLER`, `NO_FIND_BY_SQL`, `REQUIRE_INDEX_ON_FK`, `NO_UPDATE_ALL_WITHOUT_SCOPE`, `REQUIRE_STRONG_MIGRATIONS`, `FORBID_SKIP_CALLBACKS` — 10-14 rules |
| 5 | `modules/frameworks/rails/known-deprecations.json` | v2 schema, 10-12 entries: `update_attributes` → `update` (Rails 6), `uniq` on Relation → `distinct`, `before_filter` → `before_action`, `ActionController::Parameters#to_h` safety, `ActiveRecord::Base.establish_connection` global usage, `Rails.application.secrets` → credentials (Rails 7.2), Sprockets → Propshaft |
| 6 | `modules/frameworks/rails/variants/hotwire.md` | Turbo + Stimulus conventions, Turbo Streams, frame discipline |
| 7 | `modules/frameworks/rails/variants/activerecord.md` | Scope design, concerns, callbacks discipline, query objects |
| 8 | `modules/frameworks/rails/variants/api-only.md` | `--api` mode, JBuilder vs fast_jsonapi vs Alba, versioning, rate limiting with rack-attack |
| 9 | `modules/frameworks/rails/variants/engine.md` | Engine-based modular monolith |
| 10 | `modules/frameworks/rails/testing/rspec.md` | factory_bot, request specs, system specs + Capybara + Playwright driver, database_cleaner or transactional fixtures, shared examples, `rspec --profile` |
| 11 | `shared/learnings/rails.md` | N+1 from missing includes, strong params bypass, callback hell, `update_all` skipping callbacks, fat controllers, service-object-without-return-contract |

Rails file count: 11 core files.

### 5.4 Swift concurrency extension (1 file modified)

| # | Path | Change |
|---|---|---|
| 1 | `modules/languages/swift.md` | In-place edit: replace existing Concurrency section (~7 bullets) with structured ~200-line section per §4.4. Preserve all other sections unchanged. Update Dos/Don'ts tail with 5-7 new concurrency entries. |

### 5.5 Test infrastructure (1 file modified)

| # | Path | Change |
|---|---|---|
| 1 | `tests/lib/module-lists.bash` | Bump `MIN_FRAMEWORKS` constant from 21 → 24. Update the authoritative framework enumeration list (if present) to add `flask`, `laravel`, `rails`. |

### 5.6 CLAUDE.md verification (1 file, optional touch)

Phase 06 owns the primary count fix. If Phase 06 lands before Phase 08 merges: Phase 08 updates the number again from `22` → `24` and appends `flask, laravel, rails` to the framework enumeration on line 16. If Phase 06 lands after: Phase 08 coordinates with Phase 06 spec to ensure the post-merge count is `24`, not `22`. A conflict check in CI (see §8) enforces this.

### 5.7 Total file count

- Flask: 10 new files
- Laravel: 12 new files
- Rails: 11 new files
- Swift: 1 modified file
- Test lib: 1 modified file
- CLAUDE.md: 1 modified file (touch)
- **Total: 33 new files + 3 modified files = 36 files affected**

(The caller's "~50 files" estimate assumed more variants per framework; actual idiom-driven variant counts are lower. Count still comfortably in single-PR territory.)

## 6. Data / State / Config

### 6.1 `/forge-init` discovery

`/forge-init` currently runs a detection pipeline that reads the consumer's project for signals. Phase 08 adds detection probes:

| Framework | Primary signal | Secondary signal |
|---|---|---|
| Flask | `requirements.txt` or `pyproject.toml` contains `flask` | `app.py` or `wsgi.py` defines `Flask(__name__)` or `create_app()` |
| Laravel | `composer.json` `require` contains `laravel/framework` | `artisan` file at project root |
| Rails | `Gemfile` contains `gem "rails"` | `config/application.rb` defines `Rails::Application` subclass |

Detection is **additive** — pure additions to the detection table in `skills/forge-init.md`'s detection logic. Existing detections unchanged.

### 6.2 Test lib bump

`tests/lib/module-lists.bash`:

```bash
# Before
MIN_FRAMEWORKS=21
# After
MIN_FRAMEWORKS=24
```

If the file maintains an explicit enumerated `FRAMEWORKS=(...)` array, append `flask laravel rails` alphabetically.

### 6.3 Config template shape

Every `forge-config-template.md` **must include** (per CLAUDE.md §"Adding new modules"):

```yaml
convergence:
  total_retries_max: 10
  oscillation_tolerance: 3
```

Plus framework-specific defaults for reviewer weights, scoring thresholds, and inner-loop behavior. Structural test `config-template-required-fields.bats` (already exists for other frameworks) verifies presence; Phase 08 adds the three new framework fixtures to its iteration list.

### 6.4 Deprecation registry v2 schema conformance

Every `known-deprecations.json` entry uses the full v2 schema:

```json
{
  "pattern": "regex or structural pattern",
  "replacement": "idiomatic replacement snippet or guidance",
  "package": "flask",
  "since": "2.2.0",
  "removed_in": "2.3.0",
  "applies_from": "2.2.0",
  "applies_to": null,
  "added": "2026-04-19",
  "addedBy": "phase-08"
}
```

`applies_from` ensures the rule is skipped on projects pinning an older version where the replacement is unavailable. `removed_in` elevates severity to CRITICAL once reached. `addedBy: "phase-08"` enables post-merge analytics.

### 6.5 Runtime state

No changes to `.forge/state.json` schema, no new events, no new knowledge-graph nodes. Pure additive content module work. Module loading is filesystem-scan based; adding three directories under `modules/frameworks/` is automatically picked up by the composition engine.

## 7. Compatibility

**Backwards compatibility is not a concern** (per caller directive). That said, the work is naturally additive and introduces zero breakage:

- New framework directories are ignored by projects that don't select them via `components.framework`.
- The Swift extension is in-place edit of an existing section — projects using `modules/languages/swift.md` see richer guidance, never conflicting guidance (existing bullets are preserved, new subsections added).
- `MIN_FRAMEWORKS` bump fails fast on CI if anyone removes a framework — intentional safety.
- `/forge-init` detection probes for Flask/Laravel/Rails are new; projects not matching those signals see no change in behavior.
- CLAUDE.md count update is cosmetic/documentation, non-breaking.

No deprecations in this phase. No migrations. No version-gated behavior changes outside the per-framework deprecation registries (which are project-version-aware via `applies_from`).

## 8. Testing Strategy

**No local test execution** (per caller directive). All verification runs in CI post-push.

### 8.1 Structural tests (existing harness extended)

`tests/validate-plugin.sh` runs 73+ structural checks. The following existing tests will automatically pick up the new modules; no test code changes required for these:

- `module-presence.bats` — verifies each entry in `MIN_FRAMEWORKS` maps to a real directory
- `framework-required-files.bats` — each `modules/frameworks/*/` has `conventions.md`, `local-template.md`, `forge-config-template.md`, `rules-override.json`, `known-deprecations.json`
- `deprecation-schema.bats` — every `known-deprecations.json` conforms to v2 schema (required keys: `pattern`, `replacement`, `package`, `since`, `removed_in`, `applies_from`, `applies_to`, `added`, `addedBy`)
- `config-template-required-fields.bats` — templates include `total_retries_max` and `oscillation_tolerance`
- `rules-override-schema.bats` — `rules-override.json` structure valid
- `learnings-present.bats` — each framework has matching `shared/learnings/{name}.md`

### 8.2 New or extended structural tests

- `variants-directory-present.bats` — assert `modules/frameworks/{flask,laravel,rails}/variants/` exists and contains at least 3 `.md` files each
- `testing-binding-present.bats` — assert `modules/frameworks/{flask,laravel,rails}/testing/*.md` exists and references a real file in `modules/testing/`
- `min-frameworks-matches-reality.bats` — assert `MIN_FRAMEWORKS` equals the count of real framework dirs (excludes `VARIANTS.md`, `base-template.md`)
- `swift-concurrency-section.bats` — asserts `modules/languages/swift.md` contains headers matching the §4.4 hierarchy (`### Task basics`, `### TaskGroup and async let`, `### Actor isolation`, etc.)
- `claude-md-framework-count.bats` — parses the framework count string in `CLAUDE.md:16` and asserts it matches the `MIN_FRAMEWORKS` constant (catches Phase 06 / Phase 08 drift)

### 8.3 Composition tests

`tests/scenario/composition.bats` (exists) exercises the composition engine with synthetic configs. Extend with three new scenarios:

- `flask + sqlalchemy + pytest + blueprint variant` → assert resolved stack includes Flask conventions, blueprint variant overrides, pytest binding overrides, SQLAlchemy persistence
- `laravel + eloquent + phpunit + livewire variant` → similar
- `rails + activerecord + rspec + hotwire variant` → similar

Each scenario verifies (a) file resolution order, (b) no duplicate or conflicting rule IDs, (c) testing binding correctly extends generic `modules/testing/{pytest,phpunit,rspec}.md`.

### 8.4 Eval harness scenarios (from Phase 01)

Phase 01 produces the eval harness infrastructure. Phase 08 contributes **three new scenario fixtures**, one per framework:

- `evals/fixtures/flask-blog/` — canonical Flask blog app (Blueprints, Flask-SQLAlchemy, Flask-Login) with a seeded requirement (`"add draft-post feature with preview URL"`). Expected pipeline outputs baseline-compared against stored golden transcripts.
- `evals/fixtures/laravel-shop/` — canonical Laravel shop (Eloquent, Sanctum API, Livewire admin) with requirement (`"add discount-code support to checkout"`).
- `evals/fixtures/rails-blog/` — canonical Rails blog (ActiveRecord, Hotwire, Pundit) with requirement (`"add comment threading with Turbo Stream updates"`).

Each eval scenario passes when: (a) the pipeline completes in standard mode, (b) score ≥ 80, (c) framework-appropriate conventions appear in the generated code (e.g., Flask uses `current_app`, Laravel uses FormRequest, Rails uses strong params), (d) deprecation registry flags zero false positives.

### 8.5 Deprecation registry pattern tests

`tests/unit/deprecation-patterns.bats` (exists) runs each pattern in every `known-deprecations.json` against a small corpus of real-world code samples. Extend the corpus with Flask/Laravel/Rails snippets (3-5 per framework) that exercise both positive matches (pattern catches real deprecation) and negative (pattern doesn't false-positive on idiomatic modern code).

### 8.6 CI gating

All of the above run in the existing GitHub Actions workflow. New frameworks land only if the full matrix is green. No gates bypassed. No local test execution.

## 9. Rollout

**Single PR** containing all 36 file changes. Rationale:

- Structural tests that check `MIN_FRAMEWORKS` vs directory count would fail on a partial merge.
- Composition tests exercising cross-framework conventions need all three frameworks present to validate the composition engine handles mixed-stack monorepos.
- The audit finding is logically one unit ("add missing major frameworks"); splitting into three PRs creates three rounds of review noise for identical structural scaffolding.
- Swift extension is small enough (~200 lines in one file) to ride in the same PR without review burden.

**PR composition checklist** (for the Phase 08 implementation plan):

1. Commit 1: Flask module (10 files) + `shared/learnings/flask.md`
2. Commit 2: Laravel module (12 files) + `shared/learnings/laravel.md`
3. Commit 3: Rails module (11 files) + `shared/learnings/rails.md`
4. Commit 4: Swift `modules/languages/swift.md` extension
5. Commit 5: `tests/lib/module-lists.bash` bump + new structural tests (§8.2)
6. Commit 6: Composition scenarios + eval scenario fixtures
7. Commit 7: `CLAUDE.md` count/enumeration touch-up (if Phase 06 already merged)

Each commit is independently buildable against CI. PR description references audit W7 and Phase 08 roadmap entry. Version bump: minor (`3.0.0` → `3.1.0`) — additive surface area expansion. Tag `v3.1.0-phase08` per implementation workflow.

**Post-merge:** `/forge-init` on a real Flask/Laravel/Rails repo should auto-detect the framework and generate the correct config templates. Dogfood verification on three canonical open-source apps (one per framework) within one week of merge.

## 10. Risks / Open Questions

### 10.1 Version drift in deprecation registries

**Risk:** Framework versions evolve; deprecations marked `removed_in: "X.Y.0"` may become stale if the framework team slips releases, or new deprecations land upstream without a corresponding registry update.

**Mitigation:**
- Every entry includes `addedBy: "phase-08"` to enable targeted analytics — `/forge-insights` can surface the oldest Phase 08 deprecations as refresh candidates.
- `fg-140-deprecation-refresh` (existing agent) runs during PREFLIGHT and can live-check upstream changelogs; its behavior applies uniformly to the new frameworks.
- A quarterly cadence review (tracked outside this spec, in ops backlog) re-audits all three frameworks' registries against upstream release notes.

**Residual risk:** Medium. Accepted — the cost of perfectly current deprecations is unsustainable.

### 10.2 Link rot in framework documentation references

**Risk:** `conventions.md` files cite upstream docs (Flask, Laravel, Rails official sites, community resources). URLs change; community blog posts vanish.

**Mitigation:**
- Cite only versioned official documentation URLs (e.g., `https://flask.palletsprojects.com/en/3.0.x/`) — these have stable paths within a major version.
- No deep linking into third-party blog posts or Stack Overflow answers.
- A periodic link-check CI job (outside Phase 08 scope; Phase 14 candidate) flags 404s.

**Residual risk:** Low-medium. Upstream docs move infrequently; framework-authored URLs are stable.

### 10.3 CLAUDE.md count drift between Phase 06 and Phase 08

**Risk:** Phase 06 updates the framework count string from `21` → `22` (correcting audit finding); Phase 08 needs it to end at `24`. If phases merge out of order or concurrently, the string lands at the wrong number.

**Mitigation:** `claude-md-framework-count.bats` (§8.2) asserts CLAUDE.md count matches `MIN_FRAMEWORKS`. Any PR landing with mismatched values fails CI. Phase 06 and Phase 08 implementation plans explicitly coordinate via the PR description.

### 10.4 Swift concurrency content quality

**Risk:** Swift 6 introduces region-based isolation and strict-concurrency mode; getting the nuances wrong (e.g., when `@unchecked Sendable` is actually safe) ships subtly wrong guidance.

**Mitigation:** Content cross-checked against Apple's official Swift Concurrency documentation (see §12), with emphasis on Swift 5.9+ behavior. Anti-patterns section explicitly calls out evolution — `Task.detached` is technically valid but almost never right. Dogfood the section against a real Swift project (e.g., an open-source SwiftUI app) during Phase 08 review.

**Residual risk:** Low. The topic is well-documented upstream; the module cites and defers to Apple for bleeding-edge Swift 6 specifics.

### 10.5 Variant count calibration

**Open question:** Each framework's `variants/` subdirectory lists a fixed set (Flask: 3, Laravel: 5, Rails: 4). Are these the right variants, or does the community have common idioms we're missing?

**Resolution during implementation:** Validated against top-N StackOverflow questions and each framework's "awesome-X" list during the implementation plan's first task. Variants can be added in follow-up phases without breaking the module contract.

### 10.6 PHP/Ruby language module adequacy

**Open question:** `modules/languages/php.md` and `modules/languages/ruby.md` may have gaps that only surface once Laravel/Rails compose against them. Are they thin in ways that produce degraded review output?

**Mitigation:** Composition tests (§8.3) exercise the full stack. If gaps surface, raise in Phase 08 retrospective; out-of-scope for this spec to expand the language modules proactively.

## 11. Success Criteria

Phase 08 is complete when **all** of the following hold:

1. **Structural:** `modules/frameworks/flask/`, `modules/frameworks/laravel/`, `modules/frameworks/rails/` each exist with the full file bundle (conventions, templates, rules-override, deprecations, variants/, testing/). CI structural tests green.
2. **Count parity:** `tests/lib/module-lists.bash` has `MIN_FRAMEWORKS=24`. `CLAUDE.md` framework count string matches. `claude-md-framework-count.bats` passes.
3. **Schema conformance:** All three `known-deprecations.json` files validate against v2 schema with 5-15 entries each. `deprecation-schema.bats` passes.
4. **Composition:** Composition tests pass for all three new `{framework, testing, variant, persistence}` combinations.
5. **Detection:** `/forge-init` detects Flask/Laravel/Rails on canonical test fixtures (one real project each) and generates valid `forge-config.md` and `forge.local.md`.
6. **Eval harness:** Three new eval scenarios (one per framework) run via the Phase 01 eval harness and score ≥ 80 with deterministic output. At least one scenario exercises a framework-specific convention (e.g., Laravel FormRequest generation).
7. **Swift concurrency:** `modules/languages/swift.md` contains the 8-subsection concurrency hierarchy, adds ~200 lines (±20%), and passes `swift-concurrency-section.bats`. Dos/Don'ts updated with 5-7 new entries.
8. **Learnings:** `shared/learnings/{flask,laravel,rails}.md` exist with at least 5 seeded learnings each.
9. **Zero regressions:** Full `tests/run-all.sh` matrix green on CI. No existing test modified to accommodate new content.
10. **Post-merge dogfood:** Within one week, `/forge-run` executes end-to-end on one real-world project per framework without mode-specific failures.

Failure to meet any criterion blocks merge.

## 12. References

### Flask

- Flask 3.x official documentation — `https://flask.palletsprojects.com/en/3.0.x/`
- Flask Application Factories pattern — `https://flask.palletsprojects.com/en/3.0.x/patterns/appfactories/`
- Flask Blueprints — `https://flask.palletsprojects.com/en/3.0.x/blueprints/`
- Flask-SQLAlchemy 3.x — `https://flask-sqlalchemy.palletsprojects.com/en/3.1.x/`
- Flask-Login — `https://flask-login.readthedocs.io/en/latest/`
- Flask-Migrate — `https://flask-migrate.readthedocs.io/en/latest/`
- pytest-flask — `https://pytest-flask.readthedocs.io/en/latest/`

### Laravel

- Laravel 11.x documentation — `https://laravel.com/docs/11.x`
- Eloquent ORM — `https://laravel.com/docs/11.x/eloquent`
- Form Request Validation — `https://laravel.com/docs/11.x/validation#form-request-validation`
- Laravel Sanctum — `https://laravel.com/docs/11.x/sanctum`
- Livewire 3.x — `https://livewire.laravel.com/docs/quickstart`
- Inertia.js — `https://inertiajs.com/`
- PHPUnit in Laravel — `https://laravel.com/docs/11.x/testing`

### Rails

- Rails 7.2 Guides — `https://guides.rubyonrails.org/`
- Active Record Basics — `https://guides.rubyonrails.org/active_record_basics.html`
- Strong Parameters — `https://guides.rubyonrails.org/action_controller_overview.html#strong-parameters`
- Hotwire (Turbo + Stimulus) — `https://hotwired.dev/`
- RSpec Rails — `https://rspec.info/documentation/6.0/rspec-rails/`
- factory_bot_rails — `https://github.com/thoughtbot/factory_bot_rails`
- Pundit — `https://github.com/varvet/pundit`
- Propshaft (Rails 7+ asset pipeline) — `https://github.com/rails/propshaft`

### Swift concurrency

- Swift Concurrency (Apple official) — `https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/`
- Swift Evolution SE-0296 (async/await) — `https://github.com/apple/swift-evolution/blob/main/proposals/0296-async-await.md`
- Swift Evolution SE-0304 (Structured Concurrency) — `https://github.com/apple/swift-evolution/blob/main/proposals/0304-structured-concurrency.md`
- Swift Evolution SE-0306 (Actors) — `https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md`
- Swift Evolution SE-0302 (Sendable) — `https://github.com/apple/swift-evolution/blob/main/proposals/0302-concurrent-value-and-concurrent-closures.md`
- WWDC 2021 "Meet async/await in Swift" — `https://developer.apple.com/videos/play/wwdc2021/10132/`
- WWDC 2021 "Protect mutable state with Swift actors" — `https://developer.apple.com/videos/play/wwdc2021/10133/`
- WWDC 2022 "Eliminate data races using Swift Concurrency" — `https://developer.apple.com/videos/play/wwdc2022/110351/`

### Forge internal

- `/Users/denissajnar/IdeaProjects/forge/CLAUDE.md` — §"Adding new modules" contract for new framework directories
- `/Users/denissajnar/IdeaProjects/forge/shared/composition.md` — composition order algorithm
- `/Users/denissajnar/IdeaProjects/forge/modules/frameworks/django/` — depth reference for Flask
- `/Users/denissajnar/IdeaProjects/forge/modules/frameworks/spring/` — depth reference for Laravel and Rails
- `/Users/denissajnar/IdeaProjects/forge/tests/lib/module-lists.bash` — `MIN_FRAMEWORKS` home
- Audit finding W7 (missing major frameworks)
- Phase 01 spec (eval harness; produces the infrastructure Phase 08 consumes)
- Phase 06 spec (CLAUDE.md count correction; coordinates on framework-count string)
