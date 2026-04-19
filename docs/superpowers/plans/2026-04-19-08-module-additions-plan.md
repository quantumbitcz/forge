# Phase 08 — Module Additions Implementation Plan (Flask, Laravel, Rails, Swift Concurrency)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close audit finding W7 by adding three full framework convention bundles (Flask, Laravel, Rails) at Django/Spring depth, extending `modules/languages/swift.md` with a structured concurrency section (~200 lines), bumping `MIN_FRAMEWORKS` 21 → 24, and aligning `CLAUDE.md`.

**Architecture:** Additive, doc-only. Each framework gets its own directory under `modules/frameworks/{name}/` mirroring `modules/frameworks/django/` (five core files + `variants/` + `testing/` binding). A learnings file lands under `shared/learnings/{name}.md`. Swift concurrency is an in-place edit. No backwards-compat concerns; CI verification only.

**Tech Stack:** Markdown conventions, JSON rules + deprecations (schema v2), bash structural tests, git conventional commits.

**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-08-module-additions-design.md`
**Review:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-08-module-additions-spec-review.md` (APPROVE WITH MINOR)

---

## Review Issue Resolution

The spec review flagged three minor issues. This plan pre-resolves them:

1. **§5.1/5.2/5.3 header file counts (14/15/14) contradict row counts (10/12/11).** Resolution: this plan uses **10/12/11 as the authoritative per-framework counts** throughout. Total new files = 33 (10 + 12 + 11). Task rosters below enumerate every file individually.
2. **§9 rollout double-counts `shared/learnings/<name>.md`.** Resolution: per-framework commits include the learnings file *within* the 10/12/11 count — no "+ learnings" suffix. Task 1 (Flask) commits 10 files total including `shared/learnings/flask.md`. Same pattern for Laravel (12) and Rails (11).
3. **§10.5 variant calibration has no stop criterion.** Resolution: variants listed in this plan are **final**. Any additional variant surfacing during implementation (e.g. `flask/variants/async.md`, `laravel/variants/octane.md`, `rails/variants/jumpstart.md`) is **deferred to Phase 08.1 follow-up**. Removing a listed variant requires spec amendment. This plan does not extend.

## File Structure

**New (33 files):**

Flask (10):
- `modules/frameworks/flask/conventions.md`
- `modules/frameworks/flask/local-template.md`
- `modules/frameworks/flask/forge-config-template.md`
- `modules/frameworks/flask/rules-override.json`
- `modules/frameworks/flask/known-deprecations.json`
- `modules/frameworks/flask/variants/blueprint.md`
- `modules/frameworks/flask/variants/factory.md`
- `modules/frameworks/flask/variants/extension-stack.md`
- `modules/frameworks/flask/testing/pytest.md`
- `shared/learnings/flask.md`

Laravel (12):
- `modules/frameworks/laravel/conventions.md`
- `modules/frameworks/laravel/local-template.md`
- `modules/frameworks/laravel/forge-config-template.md`
- `modules/frameworks/laravel/rules-override.json`
- `modules/frameworks/laravel/known-deprecations.json`
- `modules/frameworks/laravel/variants/artisan.md`
- `modules/frameworks/laravel/variants/eloquent.md`
- `modules/frameworks/laravel/variants/livewire.md`
- `modules/frameworks/laravel/variants/inertia.md`
- `modules/frameworks/laravel/variants/api-only.md`
- `modules/frameworks/laravel/testing/phpunit.md`
- `shared/learnings/laravel.md`

Rails (11):
- `modules/frameworks/rails/conventions.md`
- `modules/frameworks/rails/local-template.md`
- `modules/frameworks/rails/forge-config-template.md`
- `modules/frameworks/rails/rules-override.json`
- `modules/frameworks/rails/known-deprecations.json`
- `modules/frameworks/rails/variants/hotwire.md`
- `modules/frameworks/rails/variants/activerecord.md`
- `modules/frameworks/rails/variants/api-only.md`
- `modules/frameworks/rails/variants/engine.md`
- `modules/frameworks/rails/testing/rspec.md`
- `shared/learnings/rails.md`

**Modified (3 files):**
- `modules/languages/swift.md` — add ~200-line structured concurrency section
- `tests/lib/module-lists.bash` — `MIN_FRAMEWORKS` 21 → 24
- `CLAUDE.md` — line 16 framework count string + enumeration

**Plus 4 new structural test files (new bats files count as test infra touches):**
- `tests/unit/swift-concurrency-section.bats`
- `tests/unit/claude-md-framework-count.bats`
- `tests/unit/variants-directory-present.bats`
- `tests/unit/testing-binding-present.bats`

Total file touches: 33 new module/learning files + 3 modified + 4 new test files = 40.

Reference templates during implementation:
- `modules/frameworks/django/` (depth reference for Flask)
- `modules/frameworks/spring/` (depth reference for Laravel, Rails)
- `modules/frameworks/django/known-deprecations.json` (v2 schema example)

---

## Task 1: Flask module

**Goal:** Create `modules/frameworks/flask/` with 9 files + `shared/learnings/flask.md` (10 total).

**Files:**
- Create: `modules/frameworks/flask/conventions.md`
- Create: `modules/frameworks/flask/local-template.md`
- Create: `modules/frameworks/flask/forge-config-template.md`
- Create: `modules/frameworks/flask/rules-override.json`
- Create: `modules/frameworks/flask/known-deprecations.json`
- Create: `modules/frameworks/flask/variants/blueprint.md`
- Create: `modules/frameworks/flask/variants/factory.md`
- Create: `modules/frameworks/flask/variants/extension-stack.md`
- Create: `modules/frameworks/flask/testing/pytest.md`
- Create: `shared/learnings/flask.md`

Reference: `modules/frameworks/django/` as depth/shape anchor (~235-line conventions.md). Cite official docs at https://flask.palletsprojects.com/en/3.0.x/.

- [ ] **Step 1: Create `modules/frameworks/flask/conventions.md`**

~400–500 lines. Mandatory sections (matching django conventions.md section hierarchy):
1. Overview (Flask 3.x scope, when to use vs Django/FastAPI)
2. Architecture (Blueprints, application factory, layered services, extension stack)
3. Routing (decorator style, url_prefix, converters, error handlers)
4. Templating (Jinja2 autoescape, `url_for`, macros, template context processors)
5. Persistence (Flask-SQLAlchemy 3.x idioms, session scoping, migrations via Flask-Migrate/Alembic)
6. Forms & validation (Flask-WTF, CSRF, FormClass pattern)
7. Auth (Flask-Login session model, token auth via itsdangerous/Authlib)
8. Security (CSRF, session cookie flags `SECURE`/`HTTPONLY`/`SAMESITE`, CORS via Flask-CORS, secret key management)
9. Performance (connection pooling, Flask-Caching, gunicorn worker sizing, `before_request`/`after_request` cost)
10. Testing (`app`/`client`/`runner` fixtures — defers details to `testing/pytest.md`)
11. Dos (at least 10 entries, each with code example)
12. Don'ts (at least 10 entries, each with code example + reason)

Close with a "Composition stack" note: `variant > flask/testing/pytest.md > flask/conventions.md > python.md > persistence/sqlalchemy.md > testing/pytest.md`.

- [ ] **Step 2: Create `modules/frameworks/flask/local-template.md`**

Seed copied into consumer's `.claude/forge.local.md` on `/forge-init`. Contents:

```markdown
# Forge local config — Flask

components:
  language: python
  framework: flask
  variant: factory          # options: blueprint | factory | extension-stack
  testing: pytest
  persistence: sqlalchemy   # optional; set null if not using SQLAlchemy
  migrations: alembic       # or flask-migrate
  auth: flask-login         # optional

# Project metadata (fill in)
project_name: TODO
wsgi_entrypoint: TODO       # e.g. wsgi:app
```

Mirror the phrasing/shape of `modules/frameworks/django/local-template.md`.

- [ ] **Step 3: Create `modules/frameworks/flask/forge-config-template.md`**

Must include the CLAUDE.md-mandated fields. Minimum contents:

```markdown
# Forge config — Flask defaults

convergence:
  total_retries_max: 10
  oscillation_tolerance: 3

implementer:
  inner_loop:
    enabled: true
    lint_cmd: "ruff check"
    test_cmd: "pytest -x"

scoring:
  pass_threshold: 80
  concerns_threshold: 60

reviewer_weights:
  security: 1.2       # Flask session/CSRF foot-guns warrant elevated weight
  performance: 1.0

mutation_testing:
  enabled: false       # opt-in; mutmut for Python

feature_flags:
  enabled: false
```

Reference `modules/frameworks/django/forge-config-template.md` for the full schema shape and copy unknown defaults from there.

- [ ] **Step 4: Create `modules/frameworks/flask/rules-override.json`**

8–12 L1 regex rules. Structure (validate against existing `modules/frameworks/django/rules-override.json` schema before writing):

```json
{
  "version": 1,
  "framework": "flask",
  "rules": [
    { "id": "FLASK-NO-DEBUG-IN-PROD", "severity": "CRITICAL",
      "pattern": "app\\.run\\([^)]*debug\\s*=\\s*True", "message": "Never ship debug=True — leaks Werkzeug debugger to production." },
    { "id": "FLASK-HARDCODED-SECRET-KEY", "severity": "CRITICAL",
      "pattern": "SECRET_KEY\\s*=\\s*['\"][A-Za-z0-9_-]{1,32}['\"]", "message": "Load SECRET_KEY from env or a secret manager." },
    { "id": "FLASK-REQUIRE-CSRF-FOR-FORMS", "severity": "WARNING",
      "pattern": "<form[^>]*method=['\"](?i:post)['\"][^>]*>(?!.*csrf_token\\(\\))", "message": "POST forms must include {{ csrf_token() }} (Flask-WTF)." },
    { "id": "FLASK-FORBID-RAW-SQL-CONCAT", "severity": "CRITICAL",
      "pattern": "db\\.session\\.execute\\(.*%s|db\\.engine\\.execute\\(.*['\"]\\s*\\+\\s*", "message": "Use bound parameters with sqlalchemy.text(...) — never string-concat SQL." },
    { "id": "FLASK-REQUIRE-FACTORY-FOR-APP", "severity": "WARNING",
      "pattern": "^app\\s*=\\s*Flask\\(__name__\\)\\s*$", "message": "Prefer create_app() application factory over module-level Flask(__name__)." },
    { "id": "FLASK-NO-BEFORE-FIRST-REQUEST", "severity": "CRITICAL",
      "pattern": "@app\\.before_first_request", "message": "before_first_request was removed in Flask 2.3. Use an application factory or `with app.app_context()` on startup." },
    { "id": "FLASK-SESSION-COOKIE-SECURE", "severity": "WARNING",
      "pattern": "SESSION_COOKIE_SECURE\\s*=\\s*False", "message": "Set SESSION_COOKIE_SECURE=True in production configs." },
    { "id": "FLASK-EXPLICIT-RESPONSE-CONTENT-TYPE", "severity": "INFO",
      "pattern": "return\\s+Response\\([^)]*\\)(?![^\\n]*mimetype)", "message": "Set mimetype explicitly on Response(...) to avoid text/html default surprises." }
  ]
}
```

Validate JSON with `python -m json.tool modules/frameworks/flask/rules-override.json` before committing.

- [ ] **Step 5: Create `modules/frameworks/flask/known-deprecations.json`**

v2 schema, 8–10 entries. All nine required keys per entry: `pattern`, `replacement`, `package`, `since`, `removed_in`, `applies_from`, `applies_to`, `added`, `addedBy`. Wrapper keys: `version: 2`, `last_refreshed`, `deprecations: [...]`.

```json
{
  "version": 2,
  "last_refreshed": "2026-04-19",
  "deprecations": [
    {
      "pattern": "from flask import Markup",
      "replacement": "Import Markup from markupsafe: `from markupsafe import Markup`. flask.Markup was deprecated in Flask 2.3.",
      "package": "flask", "since": "2.3.0", "removed_in": "3.0.0",
      "applies_from": "2.3.0", "applies_to": "*",
      "language": "python", "added": "2026-04-19", "addedBy": "phase-08"
    },
    {
      "pattern": "from flask\\.json import JSONEncoder",
      "replacement": "Subclass app.json_provider_class (flask.json.provider.DefaultJSONProvider) instead of JSONEncoder. Removed in Flask 2.3.",
      "package": "flask", "since": "2.2.0", "removed_in": "2.3.0",
      "applies_from": "2.2.0", "applies_to": "*",
      "language": "python", "added": "2026-04-19", "addedBy": "phase-08"
    },
    {
      "pattern": "@(?:app|bp)\\.before_first_request",
      "replacement": "before_first_request was removed in Flask 2.3. Run startup code inside create_app() or via `with app.app_context()`.",
      "package": "flask", "since": "2.2.0", "removed_in": "2.3.0",
      "applies_from": "2.2.0", "applies_to": "*",
      "language": "python", "added": "2026-04-19", "addedBy": "phase-08"
    },
    {
      "pattern": "flask\\.signals_available",
      "replacement": "signals_available was removed in Flask 2.3; blinker is now a hard dependency. Drop the guard.",
      "package": "flask", "since": "2.3.0", "removed_in": "2.3.0",
      "applies_from": "2.3.0", "applies_to": "*",
      "language": "python", "added": "2026-04-19", "addedBy": "phase-08"
    },
    {
      "pattern": "session\\.permanent_session_lifetime\\s*=",
      "replacement": "Set PERMANENT_SESSION_LIFETIME on app.config, not on the session object.",
      "package": "flask", "since": "2.0.0", "removed_in": null,
      "applies_from": "2.0.0", "applies_to": "*",
      "language": "python", "added": "2026-04-19", "addedBy": "phase-08"
    },
    {
      "pattern": "werkzeug\\.urls\\.url_(?:quote|unquote|encode|decode)",
      "replacement": "Use urllib.parse equivalents. werkzeug.urls helpers were removed in Werkzeug 3.0.",
      "package": "werkzeug", "since": "2.3.0", "removed_in": "3.0.0",
      "applies_from": "2.3.0", "applies_to": "*",
      "language": "python", "added": "2026-04-19", "addedBy": "phase-08"
    },
    {
      "pattern": "from flask_sqlalchemy import SQLAlchemy[\\s\\S]*?\\.Model\\.query",
      "replacement": "Model.query is legacy. Use db.session.execute(db.select(Model)).scalars() (Flask-SQLAlchemy 3.x).",
      "package": "flask-sqlalchemy", "since": "3.0.0", "removed_in": null,
      "applies_from": "3.0.0", "applies_to": "*",
      "language": "python", "added": "2026-04-19", "addedBy": "phase-08"
    },
    {
      "pattern": "app\\.json_encoder\\s*=",
      "replacement": "app.json_encoder is deprecated. Assign app.json = CustomJSONProvider(app) (subclass DefaultJSONProvider).",
      "package": "flask", "since": "2.2.0", "removed_in": null,
      "applies_from": "2.2.0", "applies_to": "*",
      "language": "python", "added": "2026-04-19", "addedBy": "phase-08"
    }
  ]
}
```

Validate JSON and schema: `python -m json.tool modules/frameworks/flask/known-deprecations.json`. Ensure each entry has all nine keys — omission = `deprecation-schema.bats` failure.

- [ ] **Step 6: Create `modules/frameworks/flask/variants/blueprint.md`**

~120 lines. Blueprint-per-feature layout. Cover: directory shape (`app/features/{name}/{routes,services,models,forms}.py`), `Blueprint(__name__, url_prefix=...)`, registration order, nested blueprints (discouraged), template discovery (`template_folder`), static file scoping, Dos/Don'ts (at least 5 each).

- [ ] **Step 7: Create `modules/frameworks/flask/variants/factory.md`**

~120 lines. Application factory pattern. Cover: `create_app(config_name)` signature, `Flask(__name__, instance_relative_config=True)`, config class hierarchy (`BaseConfig`/`DevConfig`/`ProdConfig`/`TestConfig`), extension init_app pattern, `with app.app_context()` for CLI, testing with per-test app instances. Dos/Don'ts (5 each).

- [ ] **Step 8: Create `modules/frameworks/flask/variants/extension-stack.md`**

~120 lines. Flask-Login + Flask-SQLAlchemy + Flask-Migrate + Flask-WTF composition. Cover: extension instantiation order (global → init_app inside factory), login_manager user_loader, `db.Model` base class vs `DeclarativeBase`, migration command wiring (`flask db init/migrate/upgrade`), CSRFProtect global enable. Dos/Don'ts (5 each).

- [ ] **Step 9: Create `modules/frameworks/flask/testing/pytest.md`**

~150 lines. pytest binding specific to Flask. Cover: `app` fixture (scope=session), `client` fixture (function), `runner` fixture for CLI tests, transactional rollback pattern with SQLAlchemy, `pytest-flask` integration (not required but recommended), factory-driven fixture composition, parametrized config classes, testing blueprints in isolation. Must reference `modules/testing/pytest.md` as generic parent. Dos/Don'ts (5 each).

- [ ] **Step 10: Create `shared/learnings/flask.md`**

Initial learnings file, matches shape of `shared/learnings/django.md` (if present) or generic learnings format. At least 5 seeded entries covering: N+1 via Flask-SQLAlchemy lazy load, session-vs-request scope confusion with extensions, CSRF exemption footguns (`@csrf.exempt` on wrong route), debug mode in production detection, `@app.before_request` ordering / short-circuit pitfalls. Each entry: `## <short title>` → 1-paragraph pattern description + "Detection:" + "Fix:" subsections.

- [ ] **Step 11: Validate & commit**

Run:
```bash
python -m json.tool modules/frameworks/flask/rules-override.json > /dev/null
python -m json.tool modules/frameworks/flask/known-deprecations.json > /dev/null
ls modules/frameworks/flask/{conventions.md,local-template.md,forge-config-template.md,rules-override.json,known-deprecations.json}
ls modules/frameworks/flask/variants/{blueprint,factory,extension-stack}.md
ls modules/frameworks/flask/testing/pytest.md
ls shared/learnings/flask.md
```
Expected: all files exist, JSON valid, no errors.

Commit:
```bash
git add modules/frameworks/flask/ shared/learnings/flask.md
git commit -m "feat(modules): add Flask framework bundle (phase-08)

Adds Flask 3.x convention bundle at Django-depth parity:
conventions, local/config/rules/deprecation templates, three variants
(blueprint, factory, extension-stack), pytest binding, learnings seed.
Closes audit W7 Flask gap. Includes 10 files total.

Refs: docs/superpowers/specs/2026-04-19-08-module-additions-design.md"
```

---

## Task 2: Laravel module

**Goal:** Create `modules/frameworks/laravel/` with 11 files + `shared/learnings/laravel.md` (12 total).

**Files:**
- Create: `modules/frameworks/laravel/conventions.md`
- Create: `modules/frameworks/laravel/local-template.md`
- Create: `modules/frameworks/laravel/forge-config-template.md`
- Create: `modules/frameworks/laravel/rules-override.json`
- Create: `modules/frameworks/laravel/known-deprecations.json`
- Create: `modules/frameworks/laravel/variants/artisan.md`
- Create: `modules/frameworks/laravel/variants/eloquent.md`
- Create: `modules/frameworks/laravel/variants/livewire.md`
- Create: `modules/frameworks/laravel/variants/inertia.md`
- Create: `modules/frameworks/laravel/variants/api-only.md`
- Create: `modules/frameworks/laravel/testing/phpunit.md`
- Create: `shared/learnings/laravel.md`

Reference: `modules/frameworks/spring/` as depth anchor. Cite Laravel 11.x docs at https://laravel.com/docs/11.x.

- [ ] **Step 1: Create `modules/frameworks/laravel/conventions.md`**

~500–700 lines. Sections:
1. Overview (Laravel 11.x scope, streamlined skeleton)
2. Architecture (Controller + Service + Action, FormRequest validation pipeline, service providers, middleware, route files)
3. Routing (`routes/{web,api,console}.php`, route model binding, groups, throttle, rate limiting)
4. Eloquent (relationships, scopes, accessors/mutators, casts, chunk vs cursor, eager loading)
5. Migrations & schema (`php artisan make:migration`, schema builder idioms, zero-downtime patterns)
6. Validation (FormRequest, rules arrays, custom rules, authorize())
7. Auth (Sanctum, Passport, Breeze, policies/gates, Gate::before)
8. Queues & jobs (ShouldQueue, SerializesModels, batches, chains, failed_jobs table, horizon)
9. Events & listeners, broadcasting (Reverb/Pusher), model observers
10. Cache, rate limiting, mail (Mailable), notifications
11. Artisan command design (signature, scheduling in `routes/console.php`)
12. Security (mass assignment with `$fillable`/`$guarded`, CSRF, auth middleware, policies on controllers, signed URLs)
13. Performance (N+1 detection with `Model::preventLazyLoading()`, query logging, cache strategies)
14. Testing (defers details to `testing/phpunit.md`)
15. Dos (≥12) — code examples
16. Don'ts (≥12) — code examples + reason

Close with composition stack note: `variant > laravel/testing/phpunit.md > laravel/conventions.md > php.md > persistence/eloquent-binding > testing/phpunit.md`.

- [ ] **Step 2: Create `modules/frameworks/laravel/local-template.md`**

```markdown
# Forge local config — Laravel

components:
  language: php
  framework: laravel
  variant: eloquent            # options: artisan | eloquent | livewire | inertia | api-only
  testing: phpunit
  persistence: eloquent
  auth: sanctum                # options: sanctum | passport | breeze | null

project_name: TODO
artisan_entrypoint: artisan
```

- [ ] **Step 3: Create `modules/frameworks/laravel/forge-config-template.md`**

```markdown
# Forge config — Laravel defaults

convergence:
  total_retries_max: 10
  oscillation_tolerance: 3

implementer:
  inner_loop:
    enabled: true
    lint_cmd: "./vendor/bin/pint --test"
    test_cmd: "php artisan test --stop-on-failure"

scoring:
  pass_threshold: 80
  concerns_threshold: 60

reviewer_weights:
  security: 1.3        # mass assignment + SQL concat are high-impact
  performance: 1.1

mutation_testing:
  enabled: false        # infection/php

feature_flags:
  enabled: false
```

- [ ] **Step 4: Create `modules/frameworks/laravel/rules-override.json`**

10–14 rules. At minimum:

```json
{
  "version": 1,
  "framework": "laravel",
  "rules": [
    { "id": "LARAVEL-FORBID-DB-RAW", "severity": "CRITICAL",
      "pattern": "DB::raw\\(\\s*['\"][^'\"]*\\$(?!.)", "message": "Never interpolate variables into DB::raw(). Use bindings." },
    { "id": "LARAVEL-REQUIRE-FORM-REQUEST", "severity": "WARNING",
      "pattern": "public function \\w+\\(Request \\$request\\)[\\s\\S]{0,400}\\$request->validate\\(", "message": "Move ad-hoc $request->validate() into a FormRequest class." },
    { "id": "LARAVEL-NO-MASS-ASSIGNMENT-WITHOUT-FILLABLE", "severity": "CRITICAL",
      "pattern": "extends Model[\\s\\S]*?(?!protected \\$(?:fillable|guarded))", "message": "Models must declare $fillable or $guarded." },
    { "id": "LARAVEL-REQUIRE-POLICY-FOR-MODEL", "severity": "WARNING",
      "pattern": "Route::(?:resource|apiResource)\\(\\s*['\"][^'\"]+['\"]\\s*,\\s*\\w+Controller::class\\s*\\)(?![\\s\\S]*->middleware\\(['\"]can:)", "message": "Resource routes should enforce authorization via a policy middleware or controller authorize()." },
    { "id": "LARAVEL-NO-ENV-OUTSIDE-CONFIG", "severity": "CRITICAL",
      "pattern": "(?<!config/)\\b(?!//\\s*)env\\(['\"]", "message": "env() outside config/ files breaks `php artisan config:cache`. Read config() instead." },
    { "id": "LARAVEL-REQUIRE-QUEUED-FOR-SLOW-OPS", "severity": "INFO",
      "pattern": "Mail::(?:to|send)\\([\\s\\S]{0,100}\\)->send\\(", "message": "Use ShouldQueue mailables for transactional email to avoid blocking the HTTP request." },
    { "id": "LARAVEL-NO-FACADE-INPUT", "severity": "CRITICAL",
      "pattern": "Illuminate\\\\Support\\\\Facades\\\\Input", "message": "Input facade was removed. Use the Request instance or `$request->input()`." },
    { "id": "LARAVEL-NO-UNGUARD-GLOBAL", "severity": "CRITICAL",
      "pattern": "Eloquent::unguard\\(\\s*\\)", "message": "Global unguard() disables mass-assignment protection — remove it." },
    { "id": "LARAVEL-PREVENT-LAZY-LOADING-IN-PROD", "severity": "INFO",
      "pattern": "AppServiceProvider[\\s\\S]{0,800}boot\\(\\)(?![\\s\\S]*Model::preventLazyLoading)", "message": "Enable Model::preventLazyLoading() in AppServiceProvider::boot() to catch N+1 in non-prod." },
    { "id": "LARAVEL-REQUIRE-TRANSACTION-FOR-MULTI-WRITE", "severity": "WARNING",
      "pattern": "->save\\(\\);[\\s\\S]{0,200}->save\\(\\);", "message": "Multiple model saves in sequence should run inside DB::transaction()." }
  ]
}
```

Validate JSON. Tune patterns to avoid false positives before commit.

- [ ] **Step 5: Create `modules/frameworks/laravel/known-deprecations.json`**

v2 schema, 10–12 entries. Same nine-key contract. Include:
- `Str::random` non-crypto uses → prefer `Str::password()` / random_bytes for secrets (Laravel 10+)
- `Illuminate\Support\Facades\Input` → Request injection (removed Laravel 6)
- `Mail::send(['template'], $data, $closure)` closures → Mailable classes
- `Eloquent::unguard()` global → model-level `$fillable`/`$guarded`
- `password_rules` helper signature change (Laravel 10)
- `Bus::chain()` old closure syntax → invokable jobs (Laravel 8+)
- Implicit `JsonResponse` wrapping via ->json($data)->getData() anti-pattern
- `Route::resource`'s `->only`/`->except` parameter-name drift (Laravel 8 → 10)
- `dispatchNow()` → `dispatchSync()` (Laravel 8)
- `artisan serve --dev` flag removal
- `Queue::after` closure registration → event listener class (Laravel 11)

Each entry: nine keys populated. `applies_from`/`removed_in` accurate to Laravel 6→11 timeline. Use Context7 (plugin context7) to verify current upstream status before commit:

```
# Optional: validate each entry against current docs
mcp__plugin_context7_context7__query-docs library:"laravel/framework" query:"deprecated ..."
```

Validate JSON with `python -m json.tool`.

- [ ] **Step 6: Create `modules/frameworks/laravel/variants/artisan.md`**

~120 lines. Console-command-driven variant. Cover: long-running daemons vs one-shot commands, signal handling, `--isolated`, scheduling in `routes/console.php`, exit codes, output verbosity, custom stubs. Dos/Don'ts (5 each).

- [ ] **Step 7: Create `modules/frameworks/laravel/variants/eloquent.md`**

~140 lines. ORM-centric. Cover: scopes (local/global), accessors/mutators (`Attribute::make`), attribute casting, relationships (`hasMany`, `belongsTo`, `morphTo`, `hasManyThrough`), polymorphic tables, chunking vs cursor, `withCount`, model events (created/updated) discipline, observers over closures. Dos/Don'ts (7 each).

- [ ] **Step 8: Create `modules/frameworks/laravel/variants/livewire.md`**

~120 lines. Livewire 3.x. Cover: component lifecycle (mount/hydrate/render), `wire:model.live` vs `wire:model.lazy`, full-page components, nested component keys, Alpine interop, validation in-component, form objects, lazy loading, file uploads, testing components. Dos/Don'ts (5 each).

- [ ] **Step 9: Create `modules/frameworks/laravel/variants/inertia.md`**

~110 lines. Inertia.js. Cover: `Inertia::render`, shared data via middleware, partial reloads (`only` / `except`), lazy props, form helper, SSR considerations, validation error propagation, CSRF with Axios, route() helper via Ziggy. Dos/Don'ts (5 each).

- [ ] **Step 10: Create `modules/frameworks/laravel/variants/api-only.md`**

~120 lines. Sanctum-first API. Cover: stateless vs SPA token flows, API resources (`JsonResource`, `ResourceCollection`), versioning via URL prefix vs header, rate limiting with `throttle:api`, pagination metadata, error response shape (`problem+json` vs Laravel default), conditional resources, API documentation via Scribe. Dos/Don'ts (5 each).

- [ ] **Step 11: Create `modules/frameworks/laravel/testing/phpunit.md`**

~160 lines. PHPUnit binding. Cover: Feature vs Unit tests, `RefreshDatabase` trait vs `DatabaseTransactions` vs `DatabaseMigrations`, `actingAs($user)`, HTTP testing assertions (`assertOk`, `assertJsonStructure`), factories (`UserFactory`, `state()`, `has()`), Mockery bindings, `Bus::fake()` / `Queue::fake()` / `Mail::fake()` / `Event::fake()`, parallel testing (`artisan test --parallel`), Pest interop note. Must reference `modules/testing/phpunit.md` as generic parent. Dos/Don'ts (6 each).

- [ ] **Step 12: Create `shared/learnings/laravel.md`**

At least 5 seeded entries: mass assignment via `->fill($request->all())` on models without `$fillable`; N+1 from eager-load gaps in API resources; queue serialization of Eloquent models with loaded relations (memory blowup + stale data); `env()` outside config breaks `config:cache`; implicit route model binding on soft-deleted models.

- [ ] **Step 13: Validate & commit**

```bash
python -m json.tool modules/frameworks/laravel/rules-override.json > /dev/null
python -m json.tool modules/frameworks/laravel/known-deprecations.json > /dev/null
ls modules/frameworks/laravel/{conventions.md,local-template.md,forge-config-template.md,rules-override.json,known-deprecations.json}
ls modules/frameworks/laravel/variants/{artisan,eloquent,livewire,inertia,api-only}.md
ls modules/frameworks/laravel/testing/phpunit.md
ls shared/learnings/laravel.md
```

Commit:
```bash
git add modules/frameworks/laravel/ shared/learnings/laravel.md
git commit -m "feat(modules): add Laravel framework bundle (phase-08)

Adds Laravel 11.x convention bundle at Spring-depth parity:
conventions, local/config/rules/deprecation templates, five variants
(artisan, eloquent, livewire, inertia, api-only), phpunit binding,
learnings seed. Closes audit W7 Laravel gap. Includes 12 files total.

Refs: docs/superpowers/specs/2026-04-19-08-module-additions-design.md"
```

---

## Task 3: Rails module

**Goal:** Create `modules/frameworks/rails/` with 10 files + `shared/learnings/rails.md` (11 total).

**Files:**
- Create: `modules/frameworks/rails/conventions.md`
- Create: `modules/frameworks/rails/local-template.md`
- Create: `modules/frameworks/rails/forge-config-template.md`
- Create: `modules/frameworks/rails/rules-override.json`
- Create: `modules/frameworks/rails/known-deprecations.json`
- Create: `modules/frameworks/rails/variants/hotwire.md`
- Create: `modules/frameworks/rails/variants/activerecord.md`
- Create: `modules/frameworks/rails/variants/api-only.md`
- Create: `modules/frameworks/rails/variants/engine.md`
- Create: `modules/frameworks/rails/testing/rspec.md`
- Create: `shared/learnings/rails.md`

Reference: `modules/frameworks/spring/` as depth anchor. Rails 7.2 guides at https://guides.rubyonrails.org/.

- [ ] **Step 1: Create `modules/frameworks/rails/conventions.md`**

~500–700 lines. Sections:
1. Overview (Rails 7.2 scope — Hotwire, Propshaft, importmaps default)
2. Architecture (MVC + Service objects + Form objects + Query objects; concerns discipline)
3. Routing (`config/routes.rb`, `resources`/`resource`, nested limits, `constraints`, `direct`/`resolve`)
4. ActiveRecord (migrations, strong migrations pattern, indexes-on-fk, scopes, callbacks vs services, `#update_all` caveats)
5. Strong Parameters (permit whitelist, nested attributes, Pundit enforcement)
6. Views & templating (ERB vs Slim/Haml, partials, `render collection:`)
7. Asset pipeline (Propshaft over Sprockets, importmap-rails, cssbundling-rails, jsbundling-rails alternatives)
8. Hotwire (Turbo Drive, Turbo Frames, Turbo Streams, Stimulus controllers)
9. ActionCable, ActionMailer, ActiveJob (adapter choice, retries, discard_on)
10. Authorization (Pundit policies, CanCanCan, role modeling with Rolify)
11. I18n (locale files, fallback, pluralization, `I18n.t` discipline)
12. Security (strong parameters, CSRF, session store, encrypted credentials via `rails credentials:edit`)
13. Generators & engines (`rails g`, engine isolation, routes.draw in engines)
14. Testing (defers to `testing/rspec.md`)
15. Dos (≥12) with code
16. Don'ts (≥12) with code + reason

Composition stack note: `variant > rails/testing/rspec.md > rails/conventions.md > ruby.md > persistence/active-record.md > testing/rspec.md`.

- [ ] **Step 2: Create `modules/frameworks/rails/local-template.md`**

```markdown
# Forge local config — Rails

components:
  language: ruby
  framework: rails
  variant: hotwire         # options: hotwire | activerecord | api-only | engine
  testing: rspec
  persistence: activerecord
  auth: devise             # options: devise | sorcery | clearance | null

project_name: TODO
rails_version: "7.2"
```

- [ ] **Step 3: Create `modules/frameworks/rails/forge-config-template.md`**

```markdown
# Forge config — Rails defaults

convergence:
  total_retries_max: 10
  oscillation_tolerance: 3

implementer:
  inner_loop:
    enabled: true
    lint_cmd: "bundle exec rubocop"
    test_cmd: "bundle exec rspec --fail-fast"

scoring:
  pass_threshold: 80
  concerns_threshold: 60

reviewer_weights:
  security: 1.3        # strong params + SQL injection foot-guns
  performance: 1.2     # N+1 very common

mutation_testing:
  enabled: false       # mutant-rspec

feature_flags:
  enabled: false

rubocop:
  rails: true          # hint for reviewers to load rubocop-rails
```

- [ ] **Step 4: Create `modules/frameworks/rails/rules-override.json`**

10–14 rules. Include:

```json
{
  "version": 1,
  "framework": "rails",
  "rules": [
    { "id": "RAILS-NO-MASS-ASSIGNMENT-WITHOUT-STRONG-PARAMS", "severity": "CRITICAL",
      "pattern": "\\.(?:create|update|new)\\(params\\[:\\w+\\](?:\\s*\\.\\s*to_h)?\\)", "message": "Use strong parameters — never pass raw params hash to create/update/new." },
    { "id": "RAILS-REQUIRE-POLICY-ON-CONTROLLER", "severity": "WARNING",
      "pattern": "class \\w+Controller < ApplicationController[\\s\\S]{0,400}(?!authorize|policy_scope)", "message": "Controllers should enforce Pundit authorize/policy_scope (or equivalent)." },
    { "id": "RAILS-NO-FIND-BY-SQL", "severity": "CRITICAL",
      "pattern": "find_by_sql\\(['\"][^'\"]*#\\{", "message": "Never interpolate into find_by_sql. Use sanitize_sql_array or ActiveRecord relations." },
    { "id": "RAILS-REQUIRE-INDEX-ON-FK", "severity": "WARNING",
      "pattern": "t\\.references :\\w+(?![^,)]*index: true)(?![^,)]*foreign_key: true.*index)", "message": "Add index: true on t.references for foreign keys." },
    { "id": "RAILS-NO-UPDATE-ALL-WITHOUT-SCOPE", "severity": "CRITICAL",
      "pattern": "\\.update_all\\(", "message": "update_all skips callbacks and validations. Confirm scope and absence of required callbacks before use." },
    { "id": "RAILS-REQUIRE-STRONG-MIGRATIONS", "severity": "WARNING",
      "pattern": "remove_column :\\w+, :\\w+(?![^\\n]*safety_assured)", "message": "remove_column requires safety_assured block (strong_migrations) for zero-downtime deploys." },
    { "id": "RAILS-FORBID-SKIP-CALLBACKS", "severity": "WARNING",
      "pattern": "\\.(?:save|update)\\(.*validate:\\s*false", "message": "save(validate: false) skips validations. Prefer fixing the root cause." },
    { "id": "RAILS-NO-BEFORE-FILTER", "severity": "WARNING",
      "pattern": "before_filter\\s+", "message": "before_filter was removed in Rails 5.1. Use before_action." },
    { "id": "RAILS-NO-RAW-SQL-INTERPOLATION", "severity": "CRITICAL",
      "pattern": "\\.where\\(['\"][^'\"]*#\\{", "message": "Use .where(col: value) or parameterized strings — never interpolate into where." },
    { "id": "RAILS-REQUIRE-ACTIVE-JOB-FOR-SLOW-OPS", "severity": "INFO",
      "pattern": "\\w+Mailer\\.\\w+\\([^)]*\\)\\.deliver_now\\b", "message": "Prefer deliver_later (ActiveJob) for outbound mail in request paths." }
  ]
}
```

Validate JSON.

- [ ] **Step 5: Create `modules/frameworks/rails/known-deprecations.json`**

v2 schema, 10–12 entries. Include:
- `update_attributes` → `update` (Rails 6)
- `uniq` on Relation → `distinct` (Rails 5.1)
- `before_filter` → `before_action` (Rails 5.1)
- `ActionController::Parameters#to_h` without permit (Rails 5+ raises)
- `ActiveRecord::Base.establish_connection` global usage → connection handling config
- `Rails.application.secrets` → credentials (Rails 7.2)
- Sprockets → Propshaft (Rails 7+)
- `render text:` → `render plain:` (Rails 5.1)
- `render nothing: true` → `head :ok` (Rails 5.1)
- `redirect_to :back` → `redirect_back(fallback_location: ...)` (Rails 5)
- `ActionView::Helpers::TextHelper#reset_cycle` removed (Rails 7)
- `Rails::Application#config_for` YAML auto-parsing change (Rails 6.1)

Each entry: nine keys, accurate version ranges. Validate JSON.

- [ ] **Step 6: Create `modules/frameworks/rails/variants/hotwire.md`**

~130 lines. Turbo + Stimulus. Cover: Turbo Drive visit lifecycle, Turbo Frame scoping, Turbo Stream action types (`append`/`prepend`/`replace`/`update`/`remove`/`before`/`after`), `turbo_stream.from` ActionCable, Stimulus controller naming (kebab-case), data-action syntax, targets/values/classes, lifecycle callbacks (connect/disconnect), morphing. Dos/Don'ts (6 each).

- [ ] **Step 7: Create `modules/frameworks/rails/variants/activerecord.md`**

~140 lines. Cover: scope DSL, default_scope pitfalls, concerns for shared behavior, callback discipline (`after_commit` for side effects, `before_save` for derived columns only), query objects for complex scopes, `includes` vs `preload` vs `eager_load`, `arel_table` for complex conditions, counter caches, optimistic locking, STI caveats. Dos/Don'ts (7 each).

- [ ] **Step 8: Create `modules/frameworks/rails/variants/api-only.md`**

~130 lines. Cover: `--api` mode skeleton, JBuilder vs fast_jsonapi vs Alba (recommend Alba), versioning via namespace vs header, pagination (Pagy), rate limiting with rack-attack, authentication with JWT via devise-jwt or Sorcery, CORS with rack-cors, error envelope convention (`problem+json` vs Rails default). Dos/Don'ts (6 each).

- [ ] **Step 9: Create `modules/frameworks/rails/variants/engine.md`**

~120 lines. Engine-based modular monolith. Cover: `rails plugin new --mountable`, engine isolation (`isolate_namespace`), routes mounting, migrations in engine dumps, assets in engines (Propshaft), dependency injection via Rails config, testing engines independently, shared models across engines (avoid). Dos/Don'ts (5 each).

- [ ] **Step 10: Create `modules/frameworks/rails/testing/rspec.md`**

~170 lines. RSpec binding. Cover: request specs (preferred) vs controller specs (legacy), system specs with Capybara + Playwright/Cuprite driver, factory_bot (traits, associations, transient attributes, `build_stubbed`), shared examples vs shared contexts, `database_cleaner-active_record` vs transactional fixtures, `rspec --profile` for slow test discovery, rspec-rails matchers (`have_http_status`, `render_template`, `redirect_to`), `ActiveJob::TestHelper`, VCR for external HTTP. Must reference `modules/testing/rspec.md` as generic parent. Dos/Don'ts (7 each).

- [ ] **Step 11: Create `shared/learnings/rails.md`**

At least 5 seeded entries: N+1 from missing `includes` in views/serializers; strong params bypass via `params.to_unsafe_h`; callback hell (fat models with cascading `after_save`); `update_all` silently skipping validations and callbacks; fat controllers (10+ action methods, business logic inline) and the service-object-without-return-contract smell.

- [ ] **Step 12: Validate & commit**

```bash
python -m json.tool modules/frameworks/rails/rules-override.json > /dev/null
python -m json.tool modules/frameworks/rails/known-deprecations.json > /dev/null
ls modules/frameworks/rails/{conventions.md,local-template.md,forge-config-template.md,rules-override.json,known-deprecations.json}
ls modules/frameworks/rails/variants/{hotwire,activerecord,api-only,engine}.md
ls modules/frameworks/rails/testing/rspec.md
ls shared/learnings/rails.md
```

Commit:
```bash
git add modules/frameworks/rails/ shared/learnings/rails.md
git commit -m "feat(modules): add Rails framework bundle (phase-08)

Adds Rails 7.2 convention bundle at Spring-depth parity:
conventions, local/config/rules/deprecation templates, four variants
(hotwire, activerecord, api-only, engine), rspec binding, learnings seed.
Closes audit W7 Rails gap. Includes 11 files total.

Refs: docs/superpowers/specs/2026-04-19-08-module-additions-design.md"
```

---

## Task 4: Swift structured concurrency extension

**Goal:** Extend `modules/languages/swift.md` with ~200-line structured-concurrency section. File currently 114 lines; grows to ~315.

**Files:**
- Modify: `modules/languages/swift.md`

Reference § 4.4 of spec. 8 subsections under existing `## Concurrency` header.

- [ ] **Step 1: Read current swift.md to locate the Concurrency section**

Run: `grep -n "^## " /Users/denissajnar/IdeaProjects/forge/modules/languages/swift.md`

Identify the line range for the existing Concurrency section and the Dos/Don'ts tail. Keep all non-concurrency content intact.

- [ ] **Step 2: Rewrite the Concurrency section**

Replace the existing Concurrency body (preserve the `## Concurrency` header itself + any 1-paragraph intro) with the 8 structured subsections. Each subsection 20–30 lines with at least one code block.

Required subsection headers (exact text, used by `swift-concurrency-section.bats`):

```markdown
## Concurrency

Swift 5.5+ structured concurrency. All guidance assumes Swift 5.9+; Swift 6 strict-concurrency specifics called out inline.

### Task basics

- `Task { ... }` creates an unstructured top-level task inheriting actor context + priority.
- `Task.detached { ... }` discards actor + priority inheritance — use only for CPU-bound work that should not touch the UI actor.
- `Task.sleep(for: .seconds(N))` is cancellation-aware; `Thread.sleep` is not.
- `Task.isCancelled` is a poll; `try Task.checkCancellation()` throws `CancellationError`.
- Priorities: `.userInitiated`, `.utility`, `.background`. Avoid `.high` in library code.

```swift
let task = Task(priority: .userInitiated) {
    try await fetchThumbnail()
}
task.cancel()  // cooperative
```

### TaskGroup and async let

- `async let` is lexically scoped parallelism for a fixed number of child tasks; cancellation propagates automatically.
- `withTaskGroup(of:)` / `withThrowingTaskGroup(of:)` for dynamic fan-out. Always `await group.waitForAll()` or exit the block.
- Prefer `async let` when N is small and known; switch to TaskGroup when N is dynamic or you need early-exit semantics.

```swift
// async let — fixed N
async let a = loadA()
async let b = loadB()
let (x, y) = try await (a, b)

// TaskGroup — dynamic N
try await withThrowingTaskGroup(of: Item.self) { group in
    for id in ids { group.addTask { try await fetch(id) } }
    for try await item in group { items.append(item) }
}
```

### Structured vs unstructured concurrency

- Structured: `async let`, TaskGroup, `async` functions. Parent outlives child; cancellation propagates.
- Unstructured: `Task { }`, `Task.detached`. Caller does not await; leaks possible.
- `Task.detached` is almost never right — forget about it unless you are intentionally breaking out of the actor isolation tree.

### Actor isolation

- `actor` serializes access to mutable state. Calls from outside the actor are always `await`ed.
- Reentrancy: when an actor method awaits, state can change. Never assume invariants hold across `await` boundaries inside an actor.
- `nonisolated` marks read-only or Sendable-safe members.
- `isolated` parameters allow cross-actor escape hatches; prefer structured calls.
- `@MainActor` on a type hoists all members to the main actor; it propagates through protocol conformances.

```swift
actor Counter {
    private var value = 0
    func increment() { value += 1 }
    nonisolated let id: UUID = UUID()  // Sendable immutable — no isolation needed
}
```

### Sendable and data-race safety

- `Sendable` types can cross actor boundaries. Value types with `Sendable` stored properties are `Sendable` automatically.
- `@Sendable` closures may not capture non-Sendable state.
- `@unchecked Sendable` is a promise you are manually enforcing — use only with clear documentation and internal locking.
- Swift 6 strict-concurrency mode promotes Sendable violations from warnings to errors. Region-based isolation (SE-0414) permits more compile-time safe sharing; check compiler diagnostics first before reaching for `@unchecked`.

### AsyncSequence / AsyncStream

- `AsyncSequence` for async iteration; `for try await x in seq`.
- `AsyncStream(unfolding:onCancel:)` bridges a producer callback to an async iterator.
- `AsyncThrowingStream` for producers that can fail.
- Buffering policy matters: `.bufferingNewest(N)` drops old elements; `.unbounded` risks memory growth.

```swift
let stream = AsyncStream<Event> { continuation in
    let sub = subject.sink { continuation.yield($0) }
    continuation.onTermination = { _ in sub.cancel() }
}
for await event in stream { handle(event) }
```

### Bridging legacy callbacks

- `withCheckedContinuation { cont in ... cont.resume(returning:) }` wraps single-shot callbacks. Must resume exactly once.
- `withCheckedThrowingContinuation` for throwing APIs.
- `withUnsafeContinuation` skips the double-resume check — use only on hot paths after verifying safety.
- Prefer `async`-native APIs when available (URLSession, FileManager).

```swift
func load() async throws -> Data {
    try await withCheckedThrowingContinuation { cont in
        legacyLoad { result in
            switch result {
            case .success(let d): cont.resume(returning: d)
            case .failure(let e): cont.resume(throwing: e)
            }
        }
    }
}
```

### Concurrency anti-patterns

- `Task.detached { @MainActor in ... }` to "escape" then re-enter Main — usually indicates an incorrect caller isolation choice.
- Unstructured `Task { }` without holding the handle — leaks; prefer structured or store the handle.
- Assuming actor state invariants hold across `await` — reentrancy will burn you.
- `@unchecked Sendable` without documenting the synchronization mechanism.
- `Task.sleep` used as a retry backoff without cancellation check — never respects `Task.cancel()`.
- Priority inversion: low-priority task holding an actor that a high-priority task awaits. Use `Task.yield()` or restructure.
```

- [ ] **Step 3: Update the Dos/Don'ts tail**

Append 5–7 new concurrency-flavored entries to the existing Dos/Don'ts section. Examples:

**Dos:**
- Do use `async let` for fixed-N parallelism; reach for `TaskGroup` only when N is dynamic.
- Do mark read-only immutable actor members `nonisolated`.
- Do resume continuations exactly once; prefer checked variants during development.
- Do use `Task.sleep(for:)` over `Thread.sleep` for cancellation-aware backoff.

**Don'ts:**
- Don't reach for `Task.detached` to sidestep actor isolation — fix the isolation instead.
- Don't assume state invariants hold across `await` inside an actor (reentrancy).
- Don't mark a type `@unchecked Sendable` without internal synchronization you've documented.

Do not delete any existing Dos/Don'ts entries.

- [ ] **Step 4: Verify the file grew by ~200 lines and headers are present**

Run:
```bash
wc -l /Users/denissajnar/IdeaProjects/forge/modules/languages/swift.md
grep -E '^### (Task basics|TaskGroup and async let|Structured vs unstructured concurrency|Actor isolation|Sendable and data-race safety|AsyncSequence / AsyncStream|Bridging legacy callbacks|Concurrency anti-patterns)$' /Users/denissajnar/IdeaProjects/forge/modules/languages/swift.md | wc -l
```

Expected: line count 280–350 (was 114; target ~315 ±20%). All 8 subsection headers matched (count = 8).

- [ ] **Step 5: Commit**

```bash
git add modules/languages/swift.md
git commit -m "feat(modules): extend Swift concurrency section (phase-08)

Replaces 7-bullet Concurrency section with 8 structured subsections
covering Task basics, TaskGroup/async let, structured vs unstructured,
actor isolation + reentrancy, Sendable + Swift 6 strict-concurrency,
AsyncSequence/AsyncStream, continuation bridging, anti-patterns.
Adds 5-7 Dos/Don'ts entries. File grows ~114 -> ~315 lines.

Refs: docs/superpowers/specs/2026-04-19-08-module-additions-design.md"
```

---

## Task 5: Bump MIN_FRAMEWORKS and add structural tests

**Goal:** Update `tests/lib/module-lists.bash` and add four new bats tests that gate future drift.

**Files:**
- Modify: `tests/lib/module-lists.bash`
- Create: `tests/unit/swift-concurrency-section.bats`
- Create: `tests/unit/claude-md-framework-count.bats`
- Create: `tests/unit/variants-directory-present.bats`
- Create: `tests/unit/testing-binding-present.bats`

- [ ] **Step 1: Bump `MIN_FRAMEWORKS`**

Edit `tests/lib/module-lists.bash` line 74: change `MIN_FRAMEWORKS=21` → `MIN_FRAMEWORKS=24`. No other lines change.

Verify:
```bash
grep -n "^MIN_FRAMEWORKS=" /Users/denissajnar/IdeaProjects/forge/tests/lib/module-lists.bash
```
Expected: `74:MIN_FRAMEWORKS=24`

- [ ] **Step 2: Bump `MIN_UNIT_TESTS`**

Same file, line 104. Current `MIN_UNIT_TESTS=104` and comment states "Current: 106 files". We add 4 new unit tests → current will become 110. Update to `MIN_UNIT_TESTS=108` and update the trailing comment to `# Current: 110 files (added 4 phase-08 tests)`.

- [ ] **Step 3: Create `tests/unit/swift-concurrency-section.bats`**

```bash
#!/usr/bin/env bats
# Phase 08: asserts modules/languages/swift.md contains the 8 structured-concurrency subsections.

PLUGIN_ROOT="${BATS_TEST_DIRNAME}/../.."
SWIFT_FILE="$PLUGIN_ROOT/modules/languages/swift.md"

@test "swift.md exists" {
  [ -f "$SWIFT_FILE" ]
}

@test "swift.md contains all 8 concurrency subsections" {
  for header in \
    "### Task basics" \
    "### TaskGroup and async let" \
    "### Structured vs unstructured concurrency" \
    "### Actor isolation" \
    "### Sendable and data-race safety" \
    "### AsyncSequence / AsyncStream" \
    "### Bridging legacy callbacks" \
    "### Concurrency anti-patterns"; do
      grep -qF "$header" "$SWIFT_FILE" || {
        echo "missing header: $header"
        return 1
      }
  done
}

@test "swift.md line count is within 280-350 (target ~315)" {
  local lines
  lines=$(wc -l < "$SWIFT_FILE")
  [ "$lines" -ge 280 ]
  [ "$lines" -le 350 ]
}
```

- [ ] **Step 4: Create `tests/unit/claude-md-framework-count.bats`**

```bash
#!/usr/bin/env bats
# Phase 08: asserts CLAUDE.md:16 framework count string matches MIN_FRAMEWORKS.

PLUGIN_ROOT="${BATS_TEST_DIRNAME}/../.."
CLAUDE_MD="$PLUGIN_ROOT/CLAUDE.md"

load "${BATS_TEST_DIRNAME}/../lib/module-lists.bash"

@test "CLAUDE.md exists" {
  [ -f "$CLAUDE_MD" ]
}

@test "CLAUDE.md framework count matches MIN_FRAMEWORKS" {
  # Line 16 format: "   - `frameworks/` (NN): spring, react, ..."
  local count
  count=$(grep -oE '`frameworks/` \([0-9]+\)' "$CLAUDE_MD" | head -1 | grep -oE '[0-9]+')
  [ -n "$count" ]
  [ "$count" = "$MIN_FRAMEWORKS" ]
}

@test "CLAUDE.md framework list includes flask, laravel, rails" {
  grep -q 'flask' "$CLAUDE_MD"
  grep -q 'laravel' "$CLAUDE_MD"
  grep -q 'rails' "$CLAUDE_MD"
}
```

- [ ] **Step 5: Create `tests/unit/variants-directory-present.bats`**

```bash
#!/usr/bin/env bats
# Phase 08: asserts each new framework has a populated variants/ directory.

PLUGIN_ROOT="${BATS_TEST_DIRNAME}/../.."

@test "flask variants/ has at least 3 .md files" {
  local n
  n=$(find "$PLUGIN_ROOT/modules/frameworks/flask/variants" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -ge 3 ]
}

@test "laravel variants/ has at least 5 .md files" {
  local n
  n=$(find "$PLUGIN_ROOT/modules/frameworks/laravel/variants" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -ge 5 ]
}

@test "rails variants/ has at least 4 .md files" {
  local n
  n=$(find "$PLUGIN_ROOT/modules/frameworks/rails/variants" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -ge 4 ]
}
```

- [ ] **Step 6: Create `tests/unit/testing-binding-present.bats`**

```bash
#!/usr/bin/env bats
# Phase 08: asserts each new framework has a testing/ binding file.

PLUGIN_ROOT="${BATS_TEST_DIRNAME}/../.."

@test "flask testing/pytest.md exists" {
  [ -f "$PLUGIN_ROOT/modules/frameworks/flask/testing/pytest.md" ]
}

@test "laravel testing/phpunit.md exists" {
  [ -f "$PLUGIN_ROOT/modules/frameworks/laravel/testing/phpunit.md" ]
}

@test "rails testing/rspec.md exists" {
  [ -f "$PLUGIN_ROOT/modules/frameworks/rails/testing/rspec.md" ]
}

@test "flask testing binding references generic pytest module" {
  grep -q 'modules/testing/pytest.md' "$PLUGIN_ROOT/modules/frameworks/flask/testing/pytest.md"
}

@test "laravel testing binding references generic phpunit module" {
  grep -q 'modules/testing/phpunit.md' "$PLUGIN_ROOT/modules/frameworks/laravel/testing/phpunit.md"
}

@test "rails testing binding references generic rspec module" {
  grep -q 'modules/testing/rspec.md' "$PLUGIN_ROOT/modules/frameworks/rails/testing/rspec.md"
}
```

- [ ] **Step 7: Make bats files executable-friendly and commit**

No chmod needed (bats reads, does not exec shebang directly). Verify:
```bash
ls -la tests/unit/swift-concurrency-section.bats tests/unit/claude-md-framework-count.bats tests/unit/variants-directory-present.bats tests/unit/testing-binding-present.bats
grep -n "^MIN_FRAMEWORKS=\|^MIN_UNIT_TESTS=" tests/lib/module-lists.bash
```

Commit:
```bash
git add tests/lib/module-lists.bash tests/unit/swift-concurrency-section.bats tests/unit/claude-md-framework-count.bats tests/unit/variants-directory-present.bats tests/unit/testing-binding-present.bats
git commit -m "test(phase-08): bump MIN_FRAMEWORKS 21 -> 24 and add structural guards

Bumps MIN_FRAMEWORKS to 24 after Flask/Laravel/Rails additions.
Adds four new unit bats files:
- swift-concurrency-section: asserts 8 required subsection headers
- claude-md-framework-count: asserts CLAUDE.md count matches MIN_FRAMEWORKS
- variants-directory-present: asserts per-framework variant counts
- testing-binding-present: asserts testing binding files + generic-parent ref

Bumps MIN_UNIT_TESTS 104 -> 108 for the new files.

Refs: docs/superpowers/specs/2026-04-19-08-module-additions-design.md"
```

---

## Task 6: CLAUDE.md count alignment

**Goal:** Update `CLAUDE.md:16` framework count string to `24` and append `flask, laravel, rails` to the enumeration.

**Files:**
- Modify: `CLAUDE.md`

Depends on: Tasks 1–5 complete (so count and new framework dirs are in place).

- [ ] **Step 1: Read the current line**

```bash
sed -n '16p' /Users/denissajnar/IdeaProjects/forge/CLAUDE.md
```

Expected current text: ``   - `frameworks/` (21): spring, react, fastapi, axum, swiftui, vapor, express, sveltekit, k8s, embedded, go-stdlib, aspnet, django, nextjs, gin, jetpack-compose, kotlin-multiplatform, angular, nestjs, vue, svelte — each with `conventions.md`, config files, `variants/`, and subdirectory bindings (`testing/`, `persistence/`, `messaging/`, etc.)``

- [ ] **Step 2: Replace with the Phase 08 target**

Use `Edit` tool with `old_string` = the exact current line above (sans leading line-number tab from `sed`) and `new_string`:

``   - `frameworks/` (24): spring, react, fastapi, axum, swiftui, vapor, express, sveltekit, k8s, embedded, go-stdlib, aspnet, django, nextjs, gin, jetpack-compose, kotlin-multiplatform, angular, nestjs, vue, svelte, flask, laravel, rails — each with `conventions.md`, config files, `variants/`, and subdirectory bindings (`testing/`, `persistence/`, `messaging/`, etc.)``

(Three names appended at the end of the enumeration, preserving the existing alphabetical-by-priority ordering rather than strict alphabetical — this matches the existing pattern where `spring` leads.)

Note on Phase 06 coordination: if Phase 06 (string fix from 21 → 22) has already merged to master before Phase 08's PR opens, rebase on master, then update `(22)` → `(24)` instead of `(21)` → `(24)`. The `claude-md-framework-count.bats` test from Task 5 catches any drift automatically — trust the gate.

- [ ] **Step 3: Verify alignment**

```bash
grep -oE '`frameworks/` \([0-9]+\)' /Users/denissajnar/IdeaProjects/forge/CLAUDE.md | head -1
grep -n "^MIN_FRAMEWORKS=" /Users/denissajnar/IdeaProjects/forge/tests/lib/module-lists.bash
```
Expected: both report `24`.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: align CLAUDE.md framework count to 24 (phase-08)

Updates line 16: 21 -> 24 frameworks, appends flask, laravel, rails
to enumeration. Matches MIN_FRAMEWORKS=24 in tests/lib/module-lists.bash.

Refs: docs/superpowers/specs/2026-04-19-08-module-additions-design.md"
```

---

## Self-Review Notes

1. **Spec coverage.** Every spec section has a task: §3/§5 scope → Tasks 1/2/3; §4.4 Swift → Task 4; §5.5 MIN bump → Task 5; §5.6 CLAUDE.md → Task 6; §6.4 deprecation schema → enforced in each framework's Step 5; §8.1/§8.2 tests → Task 5 creates the four new bats files; §11 success criteria → matched by Task-5 gates + per-framework validation steps. Eval fixtures (§8.4) are explicitly deferred to Phase 08 follow-up per the "additive only / no backwards compat" constraint — they depend on Phase 01's eval harness infrastructure and are not blocked here.
2. **Placeholder scan.** No TBDs; every code block shows concrete content. Line ranges and fixture sizes are specified as targets with tolerances (±20% for Swift).
3. **Type consistency.** File names in "File Structure" match Task N "Files" sections and validation steps. Commit messages reference consistent paths. MIN_FRAMEWORKS=24 used in Task 5 matches CLAUDE.md=24 in Task 6 and is verified by `claude-md-framework-count.bats`.
4. **Review issue resolution (spec review minors):**
   - Issue 1 resolved in "Review Issue Resolution" section (counts locked to 10/12/11).
   - Issue 2 resolved by wording per-framework commits as inclusive counts (no "+" suffix).
   - Issue 3 resolved by the Phase 08.1 deferral rule stated explicitly.

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-04-19-08-module-additions-plan.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
