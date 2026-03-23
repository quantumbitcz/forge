# Tier 2 Frameworks — Popular Ecosystems

**Date:** 2026-03-23
**Status:** Approved
**Scope:** Tier 2 implementation (after Tier 1 is complete and verified)
**Depends on:** 2026-03-23-module-restructuring-design.md (Tier 1)

---

## 1. Prerequisites

Tier 1 must be fully implemented and verified before Tier 2 begins:
- Three-layer module architecture operational (languages/, frameworks/, testing/)
- Convention composition and multi-component resolution working
- Cross-repo discovery chain functional
- All 12 migrated modules + 6 Tier 1 modules passing gap review (Section 7 of Tier 1 spec)
- Test suite updated and green for new structure

---

## 2. Tier 2 Frameworks

### 2.1 TypeScript + Angular (`frameworks/angular/`)

- **Language:** `languages/typescript.md` (shared)
- **Architecture:** Modules/Standalone Components, Services with DI, smart vs dumb components, NgRx/signals for state
- **Patterns:** Dependency injection via `inject()`, reactive forms, `HttpClient` with interceptors, guards for routing
- **Rendering:** Zone.js change detection (default), OnPush for performance, Angular signals (17+)
- **Variant:** `variants/typescript.md`
- **Testing:** `testing/jest.md` or `testing/vitest.md` + `testing/playwright.md` for E2E. Angular TestBed, `ComponentFixture`, `HttpClientTestingModule`
- **Deprecations:** `NgModules` -> standalone components (Angular 15+), `ComponentFixture` patterns evolving with signals, `@Injectable({providedIn: 'root'})` preferred over module providers
- **Commands:** `ng build`, `ng test`, `ng lint`
- **Required files:** conventions.md, variants/typescript.md, testing/jest.md (Angular-specific patterns), local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json

### 2.2 TypeScript + Vue (`frameworks/vue/`)

- **Language:** `languages/typescript.md` (shared)
- **Architecture:** Composition API (default), `<script setup>` SFC, composables for reusable logic, Pinia for state
- **Patterns:** `ref()`, `reactive()`, `computed()`, `watch()`/`watchEffect()`, props/emits with type inference
- **Routing:** Vue Router 4, `<RouterView>`, navigation guards, lazy loading via `defineAsyncComponent`
- **Variant:** `variants/typescript.md`
- **Testing:** `testing/vitest.md` + Vue Test Utils, `@vue/test-utils` mount/shallowMount, `testing/playwright.md` for E2E
- **Deprecations:** Options API -> Composition API, Vuex -> Pinia, `mixins` -> composables, Vue 2 patterns
- **Commands:** `pnpm build`, `pnpm test`, `pnpm lint`
- **Required files:** conventions.md, variants/typescript.md, testing/vitest.md (Vue-specific patterns), local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json

### 2.3 Kotlin + Ktor (`frameworks/ktor/`)

- **Language:** `languages/kotlin.md` (shared)
- **Architecture:** Plugin-based (routing, serialization, auth as plugins), suspend functions everywhere, no DI framework by default (manual or Koin)
- **Patterns:** `routing {}` DSL, `call.receive<T>()` / `call.respond()`, `StatusPages` plugin for error handling, `ContentNegotiation` for serialization
- **Database:** Exposed ORM or raw Ktor + kotlinx-serialization + PostgreSQL
- **Variant:** `variants/kotlin.md` with Ktor-specific additions (plugin installation, pipeline interceptors)
- **Testing:** `testing/kotest.md` + `testApplication {}` block, `HttpClient` in-process testing
- **Deprecations:** Old `Application.module()` patterns, Ktor 1.x vs 2.x differences, `io.ktor.application` -> `io.ktor.server.application`
- **Commands:** `./gradlew build`, `./gradlew test`, `./gradlew lintKotlin detekt`
- **Required files:** conventions.md, variants/kotlin.md, testing/kotest.md (Ktor-specific), local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json

### 2.4 PHP + Laravel (`frameworks/laravel/`)

- **Language:** `languages/php.md` (NEW)
  - Type declarations, nullable types, enums (8.1+), readonly properties (8.2+), match expressions
  - PSR-12 coding standard, PSR-4 autoloading
  - No `@` error suppression, no dynamic code execution, no `extract()`
- **Architecture:** MVC — Controllers -> Services -> Eloquent Models, Form Requests for validation, Resources for API responses
- **Patterns:** Eloquent ORM (scopes, accessors, casts), Artisan commands, middleware, queues/jobs, events/listeners
- **DI:** Service Container, auto-injection via type hints, service providers
- **Variant:** `variants/php.md`
- **Testing:** `testing/phpunit.md` (NEW) — PHPUnit + Pest (optional), `RefreshDatabase` trait, `actingAs()` for auth, model factories
- **Deprecations:** `Route::controller()` -> resource routes, `$casts` property -> `casts()` method (Laravel 11+), `app/Http/Kernel.php` -> bootstrap/app.php (Laravel 11+)
- **Commands:** `php artisan test`, `./vendor/bin/pint`, `phpstan analyse`
- **Required files:** conventions.md, variants/php.md, testing/phpunit.md (Laravel-specific), local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json

### 2.5 Ruby + Rails (`frameworks/rails/`)

- **Language:** `languages/ruby.md` (NEW)
  - Duck typing, blocks/procs/lambdas, modules for mixins, frozen string literals
  - Principle of least surprise, convention over configuration
  - No monkey-patching in application code, no `method_missing` abuse
- **Architecture:** MVC — Controllers -> Services (POROs) -> ActiveRecord Models, concerns for shared behavior, strong parameters
- **Patterns:** ActiveRecord (scopes, callbacks, validations), migrations, ActiveJob for background work, Action Mailer
- **API:** Rails API mode, serializers (Blueprinter/Alba preferred over jbuilder), Rack middleware
- **Variant:** `variants/ruby.md`
- **Testing:** `testing/rspec.md` (NEW) — RSpec, FactoryBot, Shoulda Matchers, VCR/WebMock for HTTP, `rails_helper.rb`
- **Deprecations:** `before_filter` -> `before_action`, classic autoloader -> Zeitwerk, Rails 6 patterns deprecated in 7+
- **Commands:** `bundle exec rspec`, `bundle exec rubocop`, `rails db:migrate`
- **Required files:** conventions.md, variants/ruby.md, testing/rspec.md, local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json

### 2.6 Dart + Flutter (`frameworks/flutter/`)

- **Language:** `languages/dart.md` (NEW)
  - Sound null safety, extension methods, records (3.0+), pattern matching (3.0+), sealed classes
  - `final` by default, async/await with `Future<T>` and `Stream<T>`
  - No `dynamic` unless interfacing with platform channels
- **Architecture:** Widget tree (StatelessWidget/StatefulWidget), BLoC or Riverpod for state, Repository pattern for data
- **Patterns:** `BuildContext` propagation, `InheritedWidget` for DI (or `get_it`), Navigator 2.0 / go_router, platform channels
- **State:** Riverpod (preferred) or BLoC — no `setState` in production except trivial local UI state
- **Variant:** `variants/dart.md`
- **Testing:** `testing/flutter-test.md` (NEW) — `flutter_test`, `WidgetTester`, `pumpWidget`, golden tests, `mockito`/`mocktail`, integration tests
- **Deprecations:** `FlatButton`/`RaisedButton` -> `ElevatedButton`/`TextButton`, `Navigator.push` -> go_router, `ChangeNotifier` -> Riverpod/BLoC
- **Commands:** `flutter build`, `flutter test`, `dart analyze`
- **Required files:** conventions.md, variants/dart.md, testing/flutter-test.md, local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json

### 2.7 Java + Quarkus (`frameworks/quarkus/`)

- **Language:** `languages/java.md` (shared)
- **Architecture:** CDI-based DI (`@ApplicationScoped`, `@RequestScoped`), JAX-RS endpoints (`@Path`, `@GET`), Panache for ORM (ActiveRecord or Repository pattern)
- **Patterns:** Build-time DI (no runtime reflection), `@ConfigProperty` for config, reactive with Mutiny (`Uni<T>`, `Multi<T>`), dev services for local testing
- **Native:** GraalVM native image support — no reflection, no dynamic proxies, `@RegisterForReflection` when needed
- **Variant:** `variants/java.md`
- **Testing:** `testing/junit5.md` + `@QuarkusTest`, `@QuarkusIntegrationTest`, RestAssured, Dev Services (auto-start containers)
- **Deprecations:** `javax.*` -> `jakarta.*` (Quarkus 3+), `@Inject` constructor patterns, Quarkus 2 -> 3 migration patterns
- **Commands:** `./mvnw compile quarkus:dev`, `./mvnw test`, `./mvnw checkstyle:check`
- **Required files:** conventions.md, variants/java.md, testing/junit5.md (Quarkus-specific), local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json

### 2.8 Kotlin + Android Views (`frameworks/android-views/`)

- **Language:** `languages/kotlin.md` (shared)
- **Architecture:** MVVM with ViewBinding/DataBinding, Fragments + Activities, Navigation Component, ViewModel + LiveData/StateFlow
- **Patterns:** ViewBinding (no `findViewById`), Hilt DI, Room for persistence, Retrofit + OkHttp for networking, WorkManager for background
- **Lifecycle:** `lifecycleScope`, `repeatOnLifecycle`, `viewLifecycleOwner` in fragments
- **Variant:** `variants/kotlin.md` with Android Views additions
- **Testing:** `testing/junit5.md` + Espresso for UI, Robolectric for unit, MockK for mocking
- **Deprecations:** `kotlin-android-extensions` -> ViewBinding, `AsyncTask` -> coroutines, `startActivityForResult` -> Activity Result API
- **Commands:** `./gradlew assembleDebug`, `./gradlew testDebugUnitTest`, `./gradlew lint`
- **Required files:** conventions.md, variants/kotlin.md (Android Views additions), testing/junit5.md (Android-specific), local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json

---

## 3. New Language Files

| Language | File | Key Conventions |
|----------|------|-----------------|
| PHP | `languages/php.md` | Type declarations, PSR-12, no dynamic code execution, nullable types, enums, readonly |
| Ruby | `languages/ruby.md` | Duck typing, frozen strings, no monkey-patching, blocks/procs, PORO services |
| Dart | `languages/dart.md` | Sound null safety, final by default, no dynamic, records, sealed classes |

These are loaded as layer 1 for their respective frameworks.

## 4. New Testing Files

| Framework | File | Key Patterns |
|-----------|------|-------------|
| PHPUnit | `testing/phpunit.md` | PHPUnit + Pest, RefreshDatabase, model factories, actingAs |
| RSpec | `testing/rspec.md` | RSpec, FactoryBot, Shoulda Matchers, VCR/WebMock, rails_helper |
| Flutter Test | `testing/flutter-test.md` | flutter_test, WidgetTester, pumpWidget, golden tests, mocktail |

## 5. New Linter Adapters

| Framework | Adapter | Notes |
|-----------|---------|-------|
| Angular | (reuse `eslint.sh`) | Angular CLI wraps ESLint |
| Vue | (reuse `eslint.sh`) | Vue ESLint plugin |
| Ktor | (reuse `detekt.sh`) | Same Kotlin linting |
| Laravel | `pint.sh` (NEW) | Laravel Pint + PHPStan |
| Rails | `rubocop.sh` (NEW) | RuboCop + standardrb |
| Flutter | `dart-analyze.sh` (NEW) | `dart analyze` + custom lint rules |
| Quarkus | (reuse `checkstyle.sh`) | Checkstyle for Java |
| Android Views | (reuse `detekt.sh` + `android-lint.sh` from Tier 1) | Combined Kotlin + Android |

---

## 6. Verification

Tier 2 uses the same 3-pass gap review process defined in Tier 1 spec Section 7:

1. **Pass 1 — Convention completeness audit:** All Tier 2 framework conventions scored against the mandatory sections table. Target: 100%.
2. **Pass 2 — Agent coverage audit:** Verify all pipeline agents handle Tier 2 frameworks correctly (convention stack resolution, check engine routing, correct linter adapters).
3. **Pass 3 — End-to-end scenario testing:** Additional scenarios for Tier 2:
   - 11. Angular SPA feature — standalone component with NgRx signal store
   - 12. Vue + Pinia — composable with API integration
   - 13. Ktor API endpoint — suspend function with Exposed ORM
   - 14. Laravel CRUD — Eloquent model with Form Request validation
   - 15. Rails API — ActiveRecord + RSpec + FactoryBot
   - 16. Flutter widget — BLoC state + platform channel
   - 17. Quarkus native — JAX-RS + Panache + GraalVM native image considerations
   - 18. Android Views migration — legacy Fragment with ViewBinding + Hilt

**Fix loop:** Same as Tier 1 — audit, fix, re-audit until all conventions 100%, all agent cells filled, all scenarios pass, tests green.

---

## 7. Implementation Scope Summary

| Area | What Changes |
|------|-------------|
| **New frameworks** | Angular, Vue, Ktor, Laravel, Rails, Flutter, Quarkus, Android Views (8 total) |
| **New languages** | PHP, Ruby, Dart (3 files) |
| **New testing** | PHPUnit, RSpec, Flutter Test (3 files) |
| **New linter adapters** | pint.sh, rubocop.sh, dart-analyze.sh (3 new, 5 reuse existing) |
| **Framework config files** | 8 x (conventions.md, local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json) = 40 files |
| **Framework variants** | 8 variant files |
| **Framework testing** | Framework-specific testing overrides where needed |
| **Learnings files** | 8 new `shared/learnings/{framework}.md` files |
| **Test updates** | Structural tests updated for new framework count, new scenario tests |
