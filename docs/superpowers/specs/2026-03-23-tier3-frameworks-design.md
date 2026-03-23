# Tier 3 Frameworks — Niche & Emerging Ecosystems

**Date:** 2026-03-23
**Status:** Draft — pending user approval
**Scope:** Tier 3 implementation (after Tier 2 is complete and verified)
**Depends on:** 2026-03-23-tier2-frameworks-design.md (Tier 2)

---

## 1. Prerequisites

Tier 2 must be fully implemented and verified before Tier 3 begins:
- All Tier 2 frameworks passing gap review
- 3 new language files (PHP, Ruby, Dart) operational
- All new linter adapters working
- Test suite green with Tier 2 framework count

---

## 2. Tier 3 Frameworks

### 2.1 Elixir + Phoenix (`frameworks/phoenix/`)

- **Language:** `languages/elixir.md` (NEW)
  - Pattern matching, pipe operator, immutability by default, processes for concurrency
  - OTP (GenServer, Supervisor, Application) for fault tolerance
  - Protocols for polymorphism, behaviours for contracts
  - No mutable state outside processes, no try/catch for control flow
- **Architecture:** Contexts (bounded contexts via Phoenix contexts), LiveView for real-time UI, Channels for WebSocket, PubSub
- **Patterns:** Ecto (changesets, schemas, multi, queries), Plug pipeline, Phoenix.Token for auth
- **Variant:** `variants/elixir.md`
- **Testing:** `testing/exunit.md` (NEW) — ExUnit, Mox for mocking, Ecto sandbox for DB isolation, Wallaby for browser testing
- **Deprecations:** Phoenix 1.6 -> 1.7 (verified routes, `~p` sigil), `use Phoenix.HTML` patterns, Ecto 2 -> 3 changes
- **Commands:** `mix compile`, `mix test`, `mix credo`
- **Required files:** conventions.md, variants/elixir.md, testing/exunit.md, local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json

### 2.2 Rust + Actix Web (`frameworks/actix/`)

- **Language:** `languages/rust.md` (shared)
- **Architecture:** Handler functions -> Services -> Repositories, Actix extractors (Path, Query, Json, Data), middleware via Transform trait
- **Patterns:** `web::Data<T>` for shared state (vs Axum's `Arc<AppState>`), `#[actix_web::main]`, error handling via `ResponseError` trait, `web::block` for CPU-bound work
- **Variant:** `variants/rust.md` with Actix-specific patterns (actor model optional, extractors, error types)
- **Testing:** `testing/rust-test.md` (shared) + `actix_web::test` helpers, `TestRequest::default().to_http_request()`
- **Deprecations:** Actix-web 3 -> 4 patterns, `HttpServer::new` closure changes, middleware API evolution
- **Commands:** `cargo build`, `cargo test`, `cargo clippy`
- **Required files:** conventions.md, variants/rust.md, testing/rust-test.md (Actix-specific), local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json

### 2.3 Go + Echo (`frameworks/echo/`)

- **Language:** `languages/go.md` (shared)
- **Architecture:** Handler -> Service -> Repository (same layering as Gin), `echo.Context` interface, middleware chaining
- **Patterns:** Route groups, custom validators, centralized error handler via `HTTPErrorHandler`, `echo.Bind` for request parsing
- **Variant:** `variants/go.md` with Echo-specific patterns (vs Gin: `echo.Context` is an interface, different middleware signature)
- **Testing:** `testing/go-testing.md` (shared) + `httptest.NewRecorder`, Echo-specific test helpers
- **Deprecations:** Echo v3 -> v4 API changes, `e.Logger` patterns, middleware signature changes
- **Commands:** `go build ./...`, `go test ./...`, `golangci-lint run`
- **Required files:** conventions.md, variants/go.md, testing/go-testing.md (Echo-specific), local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json

### 2.4 Go + Fiber (`frameworks/fiber/`)

- **Language:** `languages/go.md` (shared)
- **Architecture:** Express-inspired API, `fiber.Ctx` (not `net/http` compatible), zero-allocation router
- **Patterns:** `c.Params()`, `c.BodyParser()`, `c.JSON()`, middleware via `app.Use()`, `fiber.Storage` interface for sessions
- **Gotchas:** `fiber.Ctx` is reused from pool — do not store references. Use `c.Locals()` for request-scoped data
- **Variant:** `variants/go.md` with Fiber-specific gotchas (ctx pooling, not net/http compatible)
- **Testing:** `testing/go-testing.md` (shared) + `app.Test()` helper for in-process HTTP testing
- **Deprecations:** Fiber v2 -> v3 breaking changes, `c.Query()` API changes
- **Commands:** `go build ./...`, `go test ./...`, `golangci-lint run`
- **Required files:** conventions.md, variants/go.md, testing/go-testing.md (Fiber-specific), local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json

### 2.5 TypeScript + React Native (`frameworks/react-native/`)

- **Language:** `languages/typescript.md` (shared)
- **Architecture:** Screen -> Component hierarchy, React Navigation for routing, native modules via Turbo Modules (new arch)
- **State:** Zustand or Redux Toolkit for global state, TanStack Query for server state, AsyncStorage for persistence
- **Patterns:** Platform-specific files (`.ios.tsx`, `.android.tsx`), `StyleSheet.create()`, FlatList for lists, Animated API / Reanimated for animations
- **Variant:** `variants/typescript.md` with React Native additions (no DOM APIs, platform-specific styling, native module bridging)
- **Testing:** `testing/jest.md` + React Native Testing Library, Detox for E2E
- **Deprecations:** Old architecture (Bridge) -> New Architecture (Fabric + Turbo Modules), `AsyncStorage` from core -> `@react-native-async-storage/async-storage`
- **Commands:** `npx react-native build-android`, `npm test`, `npx react-native lint`
- **Required files:** conventions.md, variants/typescript.md (RN additions), testing/jest.md (RN-specific), local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json

### 2.6 Scala + Play / ZIO (`frameworks/scala-play/`)

- **Language:** `languages/scala.md` (NEW)
  - Immutability by default, case classes, pattern matching, traits for composition
  - Functional programming: `Option`, `Either`, `for` comprehensions, type classes
  - No `null`, no mutable `var` in domain code, no `Any`/`AnyRef` casts
- **Architecture:** Play Framework MVC or ZIO-based functional effects, dependency injection via compile-time (MacWire) or runtime (Guice)
- **Patterns:** Action composition, `Future`-based (Play) or `ZIO`-based (ZIO HTTP), Slick or Doobie for DB
- **Variant:** `variants/scala.md`
- **Testing:** `testing/scalatest.md` (NEW) — ScalaTest or MUnit, Play `WithApplication`, `FakeRequest`, specs2 style
- **Deprecations:** Play 2.8 -> 3.0 patterns, `GlobalSettings` removal, Akka -> Pekko migration
- **Commands:** `sbt compile`, `sbt test`, `sbt scalafmtCheck`
- **Required files:** conventions.md, variants/scala.md, testing/scalatest.md, local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json

### 2.7 Zig (`frameworks/zig-stdlib/`)

- **Language:** `languages/zig.md` (NEW)
  - Comptime metaprogramming, optional types, error unions, no hidden control flow
  - Manual memory management with allocators (no GC), `defer` for cleanup
  - No operator overloading, no macros (comptime replaces both)
  - Safety: runtime safety checks in debug, disabled in ReleaseFast
- **Architecture:** No framework — stdlib-based. Modules via `@import`, build system via `build.zig`
- **Patterns:** Allocator-first design (pass allocators explicitly), error handling via `try`/`catch`, comptime generics
- **Variant:** None (language-only, no framework layer)
- **Testing:** `testing/zig-test.md` (NEW) — built-in `test` blocks, `std.testing.expect`, `std.testing.allocator`
- **Commands:** `zig build`, `zig build test`, `zig fmt --check`
- **Required files:** conventions.md (in frameworks/zig-stdlib/), local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json

### 2.8 Haskell + Servant/IHP (`frameworks/haskell-servant/`)

- **Language:** `languages/haskell.md` (NEW)
  - Type-driven development, algebraic data types, type classes, monads
  - Total functions preferred (no `head`, `tail` on empty lists), `Maybe`/`Either` for errors
  - No partial functions, no `unsafePerformIO` outside FFI, no `String` (use `Text`)
- **Architecture:** Servant type-level API definitions, handlers as `ServerT`, ReaderT pattern for dependency injection
- **Patterns:** Servant combinators for routing, Persistent/Esqueleto for DB, `ExceptT` for error handling
- **Variant:** `variants/haskell.md`
- **Testing:** `testing/hspec.md` (NEW) — HSpec, QuickCheck for property testing, Servant test client, `hspec-wai`
- **Deprecations:** `String` -> `Text`, `Data.List` partial functions, Cabal vs Stack build system evolution
- **Commands:** `cabal build`, `cabal test`, `hlint`
- **Required files:** conventions.md, variants/haskell.md, testing/hspec.md, local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json

---

## 3. New Language Files

| Language | File | Key Conventions |
|----------|------|-----------------|
| Elixir | `languages/elixir.md` | Pattern matching, pipe operator, OTP, immutability, processes |
| Scala | `languages/scala.md` | Immutability, case classes, Option/Either, no null, type classes |
| Zig | `languages/zig.md` | Comptime, allocators, error unions, no hidden control flow |
| Haskell | `languages/haskell.md` | Type-driven, ADTs, monads, no partial functions, Text over String |

## 4. New Testing Files

| Framework | File | Key Patterns |
|-----------|------|-------------|
| ExUnit | `testing/exunit.md` | ExUnit, Mox, Ecto sandbox, Wallaby |
| ScalaTest | `testing/scalatest.md` | ScalaTest/MUnit, WithApplication, FakeRequest |
| Zig Test | `testing/zig-test.md` | Built-in test blocks, std.testing |
| HSpec | `testing/hspec.md` | HSpec, QuickCheck, Servant test client |

## 5. New Linter Adapters

| Framework | Adapter | Notes |
|-----------|---------|-------|
| Phoenix | `credo.sh` (NEW) | Credo for Elixir |
| Actix | (reuse `clippy.sh`) | Same Rust linting |
| Echo | (reuse `golangci-lint.sh` from Tier 1) | Same Go linting |
| Fiber | (reuse `golangci-lint.sh` from Tier 1) | Same Go linting |
| React Native | (reuse `eslint.sh`) | Same TS/JS linting |
| Scala Play | `scalafmt.sh` (NEW) | scalafmt + scalafix + WartRemover |
| Zig | `zig-fmt.sh` (NEW) | `zig fmt` |
| Haskell | `hlint.sh` (NEW) | HLint + Ormolu |

---

## 6. Verification

Tier 3 uses the same 3-pass gap review process defined in Tier 1 spec Section 7:

1. **Pass 1 — Convention completeness audit:** All Tier 3 framework conventions scored against the mandatory sections table. Target: 100%.
2. **Pass 2 — Agent coverage audit:** Verify all pipeline agents handle Tier 3 frameworks correctly.
3. **Pass 3 — End-to-end scenario testing:** Additional scenarios for Tier 3:
   - 19. Phoenix LiveView — real-time feature with Ecto changeset validation
   - 20. Actix Web endpoint — handler with custom error type and middleware
   - 21. Echo API — middleware chain with JWT auth and rate limiting
   - 22. Fiber handler — high-performance endpoint with ctx pooling awareness
   - 23. React Native screen — cross-platform with platform-specific styling
   - 24. Scala Play/ZIO — type-safe API endpoint with Slick/Doobie query
   - 25. Zig library — allocator-aware module with comptime generics
   - 26. Haskell Servant — type-level API with Persistent + QuickCheck properties

**Fix loop:** Same as Tier 1 and Tier 2 — audit, fix, re-audit until all conventions 100%, all agent cells filled, all scenarios pass, tests green.

---

## 7. Implementation Scope Summary

| Area | What Changes |
|------|-------------|
| **New frameworks** | Phoenix, Actix, Echo, Fiber, React Native, Scala Play, Zig stdlib, Haskell Servant (8 total) |
| **New languages** | Elixir, Scala, Zig, Haskell (4 files) |
| **New testing** | ExUnit, ScalaTest, Zig Test, HSpec (4 files) |
| **New linter adapters** | credo.sh, scalafmt.sh, zig-fmt.sh, hlint.sh (4 new, 4 reuse existing) |
| **Framework config files** | 8 x 5 = 40 files |
| **Framework variants** | 6 variant files (Zig and some Go frameworks share variants) |
| **Framework testing** | Framework-specific testing overrides where needed |
| **Learnings files** | 8 new `shared/learnings/{framework}.md` files |
| **Test updates** | Structural tests updated for new framework count, new scenario tests |

---

## 8. Cumulative Totals (All 3 Tiers)

After all tiers are complete:

| Metric | Count |
|--------|-------|
| **Languages** | 14 (kotlin, java, typescript, python, go, rust, swift, c, csharp, php, ruby, dart, elixir, scala, zig, haskell) — 16 total |
| **Frameworks** | 28 (12 migrated + 6 Tier 1 + 8 Tier 2 + 8 Tier 3 — minus 6 that share framework dirs = ~28 unique framework dirs) |
| **Testing files** | 19 (kotest, junit5, vitest, jest, pytest, go-testing, xctest, rust-test, xunit-nunit, testcontainers, playwright, phpunit, rspec, flutter-test, exunit, scalatest, zig-test, hspec + framework-specific overrides) |
| **Linter adapters** | 18 (8 existing + 3 Tier 1 + 3 Tier 2 + 4 Tier 3) |
| **Verification scenarios** | 26 (10 Tier 1 + 8 Tier 2 + 8 Tier 3) |
