# Plan 1: Module Architecture Restructuring

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat `modules/{name}/` structure with a three-layer composable system (`modules/languages/`, `modules/frameworks/`, `modules/testing/`) and migrate all 12 existing modules into the new structure.

**Architecture:** Each module currently mixes language idioms, framework patterns, and testing conventions into a single `conventions.md`. The new structure separates these into three layers: language files define idioms (null safety, ownership, async), framework directories define patterns (DI, transactions, routing) with per-language variants, and testing files define test framework conventions. The orchestrator composes the correct stack per component at PREFLIGHT time.

**Tech Stack:** Bash (test scripts), Markdown (convention files), JSON (rules-override, known-deprecations), YAML frontmatter (config templates)

**Spec:** `docs/superpowers/specs/2026-03-23-module-restructuring-design.md` — Sections 2.1-2.8

---

## File Structure Map

### New directories and files to CREATE:

```
modules/
├── languages/
│   ├── kotlin.md          # Extracted from kotlin-spring + kotlin sections
│   ├── java.md            # Extracted from java-spring
│   ├── typescript.md       # Extracted from react-vite + typescript-node + typescript-svelte
│   ├── python.md          # Extracted from python-fastapi
│   ├── go.md              # Extracted from go-stdlib
│   ├── rust.md            # Extracted from rust-axum
│   ├── swift.md           # Extracted from swift-ios + swift-vapor
│   ├── c.md               # Extracted from c-embedded
│   └── csharp.md          # NEW — Tier 1
│
├── frameworks/
│   ├── spring/
│   │   ├── conventions.md          # Shared Spring patterns (from kotlin-spring + java-spring)
│   │   ├── variants/
│   │   │   ├── kotlin.md           # Kotlin+Spring specifics (from kotlin-spring)
│   │   │   └── java.md             # Java+Spring specifics (from java-spring)
│   │   ├── testing/
│   │   │   ├── kotest.md           # Spring-specific Kotest patterns
│   │   │   └── junit5-assertj.md   # Spring-specific JUnit5 patterns
│   │   ├── local-template.md       # Adapted from kotlin-spring (parameterized)
│   │   ├── pipeline-config-template.md
│   │   ├── rules-override.json     # Merged from kotlin-spring + java-spring
│   │   └── known-deprecations.json # Merged from kotlin-spring + java-spring
│   ├── react/
│   │   ├── conventions.md          # From react-vite (framework parts)
│   │   ├── variants/
│   │   │   └── typescript.md       # TS+React specifics
│   │   ├── testing/
│   │   │   └── vitest.md           # React-specific Vitest patterns
│   │   ├── local-template.md
│   │   ├── pipeline-config-template.md
│   │   ├── rules-override.json
│   │   └── known-deprecations.json
│   ├── fastapi/            # From python-fastapi
│   ├── axum/               # From rust-axum
│   ├── swiftui/            # From swift-ios
│   ├── vapor/              # From swift-vapor
│   ├── express/            # From typescript-node
│   ├── sveltekit/          # From typescript-svelte
│   ├── k8s/                # From infra-k8s
│   └── embedded/           # From c-embedded
│
├── testing/
│   ├── kotest.md           # Generic Kotest conventions
│   ├── junit5.md           # Generic JUnit5 conventions
│   ├── vitest.md           # Generic Vitest conventions
│   ├── jest.md             # Generic Jest conventions
│   ├── pytest.md           # Generic pytest conventions
│   ├── go-testing.md       # Generic Go testing conventions
│   ├── xctest.md           # Generic XCTest conventions
│   ├── rust-test.md        # Generic Rust test conventions
│   ├── xunit-nunit.md     # Generic .NET xUnit/NUnit conventions (Tier 1)
│   ├── testcontainers.md   # Shared DB/infra test container patterns
│   └── playwright.md       # Shared E2E conventions
```

### Files to MODIFY:

```
tests/validate-plugin.sh           # Update MODULES array + paths to new structure
tests/contract/*.bats              # Update module-completeness checks
CLAUDE.md                          # Update module documentation
shared/learnings/                  # Rename files (kotlin-spring.md -> spring.md, etc.)
```

### Files to DELETE:

```
modules/kotlin-spring/             # Replaced by modules/frameworks/spring/ + modules/languages/kotlin.md
modules/java-spring/               # Replaced by modules/frameworks/spring/ + modules/languages/java.md
modules/react-vite/                # Replaced by modules/frameworks/react/ + modules/languages/typescript.md
modules/python-fastapi/            # Replaced by modules/frameworks/fastapi/ + modules/languages/python.md
modules/go-stdlib/                 # Replaced by modules/languages/go.md + modules/testing/go-testing.md
modules/rust-axum/                 # Replaced by modules/frameworks/axum/ + modules/languages/rust.md
modules/swift-ios/                 # Replaced by modules/frameworks/swiftui/ + modules/languages/swift.md
modules/swift-vapor/               # Replaced by modules/frameworks/vapor/ + modules/languages/swift.md
modules/typescript-node/           # Replaced by modules/frameworks/express/ + modules/languages/typescript.md
modules/typescript-svelte/         # Replaced by modules/frameworks/sveltekit/ + modules/languages/typescript.md
modules/c-embedded/                # Replaced by modules/frameworks/embedded/ + modules/languages/c.md
modules/infra-k8s/                 # Replaced by modules/frameworks/k8s/
```

---

## Task 1: Update Test Infrastructure for New Structure

Update the structural tests FIRST so they define the target structure. They will fail until the migration is done — this is intentional (test-driven restructuring).

**Files:**
- Modify: `tests/validate-plugin.sh:94-148` (module validation section)
- Modify: `tests/contract/module-completeness.bats` (if exists)

- [ ] **Step 1: Read the current module validation in validate-plugin.sh**

Read lines 94-200 of `tests/validate-plugin.sh` to understand all module-related checks.

- [ ] **Step 2: Update the MODULES array and paths**

Replace the flat module list with framework-based structure:

```bash
# --- MODULES --- section replacement

# Framework modules (each must have conventions.md + 4 config files)
FRAMEWORKS=(spring react fastapi axum swiftui vapor express sveltekit k8s embedded go-stdlib)
REQUIRED_FRAMEWORK_FILES=(conventions.md local-template.md pipeline-config-template.md rules-override.json known-deprecations.json)

# Language files
LANGUAGES=(kotlin java typescript python go rust swift c csharp)

# Testing files
TESTING_FILES=(kotest.md junit5.md vitest.md jest.md pytest.md go-testing.md xctest.md rust-test.md xunit-nunit.md testcontainers.md playwright.md)
```

Update Check 6 (module required files) to iterate `$ROOT/modules/frameworks/` instead of `$ROOT/modules/`.

Update Check 7 (conventions.md Dos/Don'ts) to check `$ROOT/modules/frameworks/*/conventions.md`.

Update Check 8-9 (pipeline-config-template fields) for new paths.

Update Check 10 (local-template linear:) for new paths.

Add new checks:
- Check N: All language files exist in `modules/languages/`
- Check N+1: All testing files exist in `modules/testing/`
- Check N+2: Learnings files exist for each framework

- [ ] **Step 3: Run the structural tests — expect FAIL**

Run: `./tests/run-all.sh structural`
Expected: FAIL (new paths don't exist yet)

- [ ] **Step 4: Update contract tests for module-completeness**

Update `tests/contract/module-completeness.bats` to check the new directory structure. The expected module list changes from `c-embedded go-stdlib infra-k8s...` to `spring react fastapi axum...`.

- [ ] **Step 5: Commit the failing tests**

```bash
git add tests/validate-plugin.sh tests/contract/
git commit -m "test: update module validation for three-layer structure (tests will fail until migration)"
```

---

## Task 2: Create Language Files

Extract language-specific conventions from existing module conventions.md files into standalone language files. Each language file covers: null safety/type system, naming idioms, concurrency patterns, memory management (if applicable), common anti-patterns.

**Files:**
- Create: `modules/languages/kotlin.md`
- Create: `modules/languages/java.md`
- Create: `modules/languages/typescript.md`
- Create: `modules/languages/python.md`
- Create: `modules/languages/go.md`
- Create: `modules/languages/rust.md`
- Create: `modules/languages/swift.md`
- Create: `modules/languages/c.md`
- Create: `modules/languages/csharp.md` (NEW — Tier 1)

- [ ] **Step 1: Read kotlin-spring/conventions.md and extract Kotlin-only idioms**

Read the full file. Identify sections that are Kotlin-specific (not Spring-specific):
- Null safety patterns (`!!` prohibition, `?.let {}`, `?.` chaining)
- Kotlin types (`kotlin.uuid.Uuid`, `kotlinx.datetime.Instant`)
- Sealed classes, data classes, typed IDs
- Coroutines and suspend functions
- Extension functions
- `when` expressions

Write `modules/languages/kotlin.md` with these patterns. Structure with sections: Type System, Null Safety, Concurrency, Naming Idioms, Anti-Patterns.

- [ ] **Step 2: Extract Java language conventions**

Read `java-spring/conventions.md`. Extract Java-specific patterns:
- Records, Optional, var (local type inference)
- Streams API
- `java.time.*` usage
- Sealed interfaces (Java 17+)
- Text blocks

Write `modules/languages/java.md`.

- [ ] **Step 3: Extract TypeScript language conventions**

Read `react-vite/conventions.md`, `typescript-node/conventions.md`, `typescript-svelte/conventions.md`. Merge TypeScript-specific patterns (deduplicate):
- Strict mode, `noUncheckedIndexedAccess`
- Union types, discriminated unions, template literal types
- `as const` assertions
- Utility types (Partial, Pick, Omit, Record)
- `async`/`await`, Promise patterns
- Import order conventions

Write `modules/languages/typescript.md`.

- [ ] **Step 4: Extract Python language conventions**

Read `python-fastapi/conventions.md`. Extract:
- Type hints (PEP 484), `from __future__ import annotations`
- dataclasses, Pydantic BaseModel
- `async`/`await`, `asyncio`
- Context managers
- f-strings, walrus operator

Write `modules/languages/python.md`.

- [ ] **Step 5: Extract Go language conventions**

Read `go-stdlib/conventions.md`. Extract:
- Interface-driven design (accept interfaces, return structs)
- Error handling (`if err != nil`)
- Context propagation
- Goroutines, channels
- Package naming, import grouping
- `defer` patterns

Write `modules/languages/go.md`.

- [ ] **Step 6: Extract remaining languages (Rust, Swift, C)**

Read `rust-axum/conventions.md` -> `modules/languages/rust.md` (ownership, borrowing, lifetimes, traits, Result/Option)

Read `swift-ios/conventions.md` + `swift-vapor/conventions.md` -> `modules/languages/swift.md` (value types, optionals, protocol-oriented, `@MainActor`, memory safety)

Read `c-embedded/conventions.md` -> `modules/languages/c.md` (memory management, const correctness, header guards, ISR safety, RTOS patterns)

- [ ] **Step 7: Create C# language file (NEW for Tier 1)**

Write `modules/languages/csharp.md` covering:
- Nullable reference types (`#nullable enable`)
- Records, init-only properties
- Pattern matching (`is`, `switch` expressions)
- `async`/`await`, `Task<T>`, `ValueTask<T>`
- LINQ (method syntax preferred)
- String interpolation, raw string literals (C# 11)

Use Context7 MCP to fetch current C# best practices if available.

- [ ] **Step 8: Verify all 9 language files exist**

```bash
ls modules/languages/*.md | wc -l
# Expected: 9
```

- [ ] **Step 9: Commit language files**

```bash
git add modules/languages/
git commit -m "feat: create language convention files (9 languages extracted + csharp new)"
```

---

## Task 3: Create Generic Testing Files

Create cross-cutting test framework conventions that are framework-agnostic. Each file covers: test structure, naming, matchers/assertions, lifecycle hooks, common patterns, anti-patterns.

**Files:**
- Create: `modules/testing/kotest.md`
- Create: `modules/testing/junit5.md`
- Create: `modules/testing/vitest.md`
- Create: `modules/testing/jest.md`
- Create: `modules/testing/pytest.md`
- Create: `modules/testing/go-testing.md`
- Create: `modules/testing/xctest.md`
- Create: `modules/testing/rust-test.md`
- Create: `modules/testing/xunit-nunit.md`
- Create: `modules/testing/testcontainers.md`
- Create: `modules/testing/playwright.md`

- [ ] **Step 1: Create kotest.md**

Generic Kotest conventions (not Spring-specific):
- `ShouldSpec` as default style
- Matchers (`shouldBe`, `shouldContain`, `shouldThrow`)
- Lifecycle (`beforeTest`, `afterTest`, `beforeSpec`)
- Data-driven testing (`forAll`)
- Property-based testing
- Coroutine test support (`runTest`)
- Naming: `"should {behavior}" {}` pattern

- [ ] **Step 2: Create junit5.md**

Generic JUnit5 conventions:
- `@Test`, `@Nested`, `@DisplayName`
- AssertJ preferred (`assertThat(x).isEqualTo(y)`)
- `@ParameterizedTest` with `@ValueSource`, `@MethodSource`
- `@BeforeEach`/`@AfterEach` lifecycle
- `assertThrows` for exception testing
- Mockito patterns (`@Mock`, `@InjectMocks`, `when().thenReturn()`)

- [ ] **Step 3: Create vitest.md**

Generic Vitest conventions:
- `describe`/`it`/`expect` structure
- `beforeEach`/`afterEach` lifecycle
- `vi.fn()`, `vi.spyOn()` for mocking
- Snapshot testing (when appropriate)
- `expect(x).toBe()`, `toEqual()`, `toContain()`
- Async test patterns (`async`/`await` in tests)

- [ ] **Step 4: Create jest.md**

Generic Jest conventions (overlaps with Vitest but distinct ecosystem):
- `describe`/`it`/`expect` structure
- `jest.fn()`, `jest.spyOn()` for mocking
- `jest.mock()` for module mocking
- Snapshot testing guidelines
- Timer mocking (`jest.useFakeTimers()`)
- Manual mocks (`__mocks__/`)

- [ ] **Step 5: Create pytest.md**

Generic pytest conventions:
- `test_` prefix naming
- Fixtures (`@pytest.fixture`, `conftest.py`)
- Parametrize (`@pytest.mark.parametrize`)
- `assert` plain assertions (no unittest-style)
- Async testing (`@pytest.mark.asyncio`)
- Markers for categorization

- [ ] **Step 6: Create go-testing.md, xctest.md, rust-test.md**

`go-testing.md`: Table-driven tests, `testing.T`, subtests, `testify` assertions, `httptest`, benchmarks

`xctest.md`: `XCTestCase`, `XCTAssert*`, async test support, `@MainActor` test considerations, UI testing basics

`rust-test.md`: `#[test]`, `#[cfg(test)]`, `assert!`/`assert_eq!`, `#[should_panic]`, `tokio::test` for async, mock traits

- [ ] **Step 7: Create xunit-nunit.md (NEW for Tier 1 — .NET)**

Generic .NET testing conventions:
- xUnit preferred (`[Fact]`, `[Theory]`, `[InlineData]`)
- FluentAssertions (`result.Should().Be()`, `result.Should().ContainSingle()`)
- NSubstitute for mocking (`Substitute.For<IService>()`)
- `IClassFixture<T>` for shared test context
- `IAsyncLifetime` for async setup/teardown
- `WebApplicationFactory<Program>` for integration tests
- Collection fixtures for database sharing

- [ ] **Step 8: Create testcontainers.md (shared)**

Cross-framework shared patterns:
- PostgreSQL, MySQL, Redis, Kafka container setup
- Lifecycle: per-test vs per-class vs reuse mode
- Connection configuration injection
- Framework-specific notes (Spring `@DynamicPropertySource`, FastAPI fixture, Go `testcontainers-go`)
- Cleanup and port management

- [ ] **Step 8: Create playwright.md**

Cross-framework E2E patterns:
- Page Object pattern
- Selector strategy (prefer `getByRole`, `getByText`)
- Network mocking (`page.route()`)
- Visual regression (`toHaveScreenshot()`)
- Parallel execution configuration
- Authentication state reuse
- CI configuration (headless, retry)

- [ ] **Step 10: Verify all 11 testing files exist**

```bash
ls modules/testing/*.md | wc -l
# Expected: 11
```

- [ ] **Step 11: Commit testing files**

```bash
git add modules/testing/
git commit -m "feat: create generic testing convention files (10 test frameworks)"
```

---

## Task 4: Migrate Spring Module (kotlin-spring + java-spring -> frameworks/spring/)

This is the most complex migration — two existing modules merge into one framework with two language variants and two testing variants.

**Files:**
- Create: `modules/frameworks/spring/conventions.md`
- Create: `modules/frameworks/spring/variants/kotlin.md`
- Create: `modules/frameworks/spring/variants/java.md`
- Create: `modules/frameworks/spring/testing/kotest.md`
- Create: `modules/frameworks/spring/testing/junit5-assertj.md`
- Move+adapt: `modules/frameworks/spring/local-template.md`
- Move+adapt: `modules/frameworks/spring/pipeline-config-template.md`
- Merge: `modules/frameworks/spring/rules-override.json`
- Merge: `modules/frameworks/spring/known-deprecations.json`

- [ ] **Step 1: Read both existing conventions fully**

Read `modules/kotlin-spring/conventions.md` and `modules/java-spring/conventions.md` in full. Identify:
- Shared Spring patterns (DI, `@Transactional`, security, WebFlux, error handling, API design)
- Kotlin-only patterns (sealed interfaces, typed IDs, coroutines, R2DBC specifics)
- Java-only patterns (records, Optional, streams, Bean Validation)

- [ ] **Step 2: Write frameworks/spring/conventions.md**

Shared Spring conventions (language-agnostic):
- Constructor injection (never field injection)
- `@Transactional` on use case/service layer only, never on adapters
- Spring Security configuration patterns
- WebFlux reactive stack patterns
- Error handling: `@ControllerAdvice` + `ProblemDetail`
- API design: REST conventions, pagination, HATEOAS
- Database: connection pooling, `@DynamicPropertySource` for tests
- Caching: `@Cacheable` with explicit TTL

Include Architecture, Naming, Code Quality, Error Handling, Security, Performance, Dos/Don'ts sections.

- [ ] **Step 3: Write variants/kotlin.md**

Kotlin-specific Spring overrides:
- Sealed interface hierarchy (`XxxPersisted`, `XxxNotPersisted`, `XxxId`)
- `kotlin.uuid.Uuid` and `kotlinx.datetime.Instant` (not Java types in core)
- R2DBC with `CoroutineCrudRepository`
- Suspend functions in controllers and services
- Extension functions for Spring beans
- KDoc patterns

- [ ] **Step 4: Write variants/java.md**

Java-specific Spring overrides:
- Records for DTOs and value objects
- `Optional<T>` for nullable returns from repositories
- Bean Validation annotations (`@Valid`, `@NotBlank`)
- `var` for local type inference
- Streams for collection processing
- Javadoc patterns

- [ ] **Step 5: Write testing/kotest.md (Spring-specific)**

Spring+Kotest patterns (extends generic `testing/kotest.md`):
- `@RestIntegrationTest` with Testcontainers
- `@PersistenceIntegrationTest` with PostgreSQL
- `testFixtures` source set for factories
- Keycloak test realm patterns
- `WebTestClient` with coroutines

- [ ] **Step 6: Write testing/junit5-assertj.md (Spring-specific)**

Spring+JUnit5 patterns (extends generic `testing/junit5.md`):
- `@SpringBootTest` + `@AutoConfigureMockMvc`
- `MockMvc` for controller tests
- `@DataJpaTest` for repository tests
- `@MockBean` for service mocking
- TestContainers with `@DynamicPropertySource`

- [ ] **Step 7: Adapt local-template.md**

Take `kotlin-spring/local-template.md` as base. Parameterize the language-specific parts:
- Remove hardcoded `module: kotlin-spring` -> add `language:`, `framework:`, `variant:`, `testing:` fields under `components:`
- Keep commands section (still framework-specific)
- Add `components:` wrapper structure per spec Section 2.3

- [ ] **Step 8: Merge rules-override.json from both modules**

Combine kotlin-spring and java-spring rules. Language-specific rules move to a `"variant_rules"` section keyed by language:
```json
{
  "extends": "spring",
  "variant_rules": {
    "kotlin": {
      "additional_rules": [...KS-ARCH-001, KS-ARCH-002...],
      "additional_boundaries": [...]
    },
    "java": {
      "additional_rules": [...JS-ARCH-001...],
      "additional_boundaries": [...]
    }
  },
  "shared_rules": {
    "additional_rules": [...rules that apply regardless of language...]
  }
}
```

- [ ] **Step 9: Merge known-deprecations.json**

Combine entries from both modules. Add `"language"` field to entries that are language-specific (e.g., `java.util.UUID` only applies to Kotlin variant where core uses Kotlin types). Shared Spring deprecations (e.g., `javax.*` -> `jakarta.*`) apply to both.

- [ ] **Step 10: Verify Spring module structure**

```bash
ls -R modules/frameworks/spring/
# Expected: conventions.md, variants/kotlin.md, variants/java.md,
#   testing/kotest.md, testing/junit5-assertj.md,
#   local-template.md, pipeline-config-template.md,
#   rules-override.json, known-deprecations.json
```

- [ ] **Step 11: Commit Spring migration**

```bash
git add modules/frameworks/spring/
git commit -m "feat: migrate kotlin-spring + java-spring into frameworks/spring/ with variants"
```

---

## Task 5: Migrate Frontend Modules (react-vite -> frameworks/react/, typescript-svelte -> frameworks/sveltekit/)

**Files:**
- Create: `modules/frameworks/react/` (full structure)
- Create: `modules/frameworks/sveltekit/` (full structure)

- [ ] **Step 1: Read react-vite/conventions.md fully**

Identify framework-specific patterns (React hooks, JSX, component patterns, theme tokens) vs TypeScript-specific patterns (already in `languages/typescript.md`) vs testing-specific patterns (Vitest, Testing Library — already in `testing/vitest.md`).

- [ ] **Step 2: Write frameworks/react/conventions.md**

React-specific conventions (not TypeScript-specific, not Vitest-specific):
- Component structure (functional components only, no class components)
- Hook patterns (`useState`, `useEffect`, `useMemo`, custom hooks)
- Theme tokens (`bg-background`, `text-foreground`, never hardcoded hex)
- Typography via inline `style={{ fontSize }}`, not Tailwind `text-*`
- Error Boundaries around route-level components
- State management: server data in TanStack Query/SWR, not useState
- Empty states, loading states, error states
- Accessibility requirements
- Chart conventions (recharts)

- [ ] **Step 3: Create variants/typescript.md, testing/vitest.md for React**

`variants/typescript.md`: React+TypeScript patterns (generic component typing, `React.FC` vs plain functions, prop types, event handler types)

`testing/vitest.md`: React-specific Vitest patterns (Testing Library, `render()`, `screen.getBy*`, `userEvent`, MSW for network mocking)

- [ ] **Step 4: Migrate config files for React**

Adapt `react-vite/local-template.md` -> `frameworks/react/local-template.md` (add `components:` structure)
Copy and adapt: `pipeline-config-template.md`, `rules-override.json`, `known-deprecations.json`

- [ ] **Step 5: Migrate SvelteKit module similarly**

Read `typescript-svelte/conventions.md`. Split into:
- `frameworks/sveltekit/conventions.md` — Svelte 5 runes, file-based routing, load functions, form actions
- `frameworks/sveltekit/variants/typescript.md` — TS+Svelte specifics
- `frameworks/sveltekit/testing/vitest.md` — SvelteKit testing patterns
- Config files adapted from typescript-svelte

- [ ] **Step 6: Verify both frontend modules**

```bash
ls -R modules/frameworks/react/ modules/frameworks/sveltekit/
```

- [ ] **Step 7: Commit frontend migrations**

```bash
git add modules/frameworks/react/ modules/frameworks/sveltekit/
git commit -m "feat: migrate react-vite and typescript-svelte into frameworks/"
```

---

## Task 6: Migrate Remaining Backend Modules

**Files:**
- Create: `modules/frameworks/fastapi/` (from python-fastapi)
- Create: `modules/frameworks/axum/` (from rust-axum)
- Create: `modules/frameworks/vapor/` (from swift-vapor)
- Create: `modules/frameworks/express/` (from typescript-node)

- [ ] **Step 1: Migrate FastAPI**

Read `python-fastapi/conventions.md`. Split:
- Python idioms already in `languages/python.md`
- FastAPI patterns -> `frameworks/fastapi/conventions.md` (Depends(), async handlers, Pydantic models, SQLAlchemy async)
- `frameworks/fastapi/variants/python.md` — Python+FastAPI specifics
- `frameworks/fastapi/testing/pytest.md` — FastAPI pytest patterns (`TestClient`, `AsyncClient`, `@pytest.mark.asyncio`)
- Migrate config files

- [ ] **Step 2: Migrate Axum**

Read `rust-axum/conventions.md`. Split:
- Rust idioms already in `languages/rust.md`
- Axum patterns -> `frameworks/axum/conventions.md` (extractors, `Arc<AppState>`, Tower middleware, error handling)
- `frameworks/axum/variants/rust.md` — Rust+Axum specifics
- `frameworks/axum/testing/rust-test.md` — Axum testing patterns (`axum::test`, `TestClient`)
- Migrate config files

- [ ] **Step 3: Migrate Vapor**

Read `swift-vapor/conventions.md`. Split:
- Swift idioms already in `languages/swift.md`
- Vapor patterns -> `frameworks/vapor/conventions.md` (repository pattern, Fluent ORM, async routes, Validatable)
- `frameworks/vapor/variants/swift.md`
- `frameworks/vapor/testing/xctest.md` — Vapor testing patterns (`Application.test`, `XCTVapor`)
- Migrate config files

- [ ] **Step 4: Migrate Express/Node**

Read `typescript-node/conventions.md`. Split:
- TypeScript idioms already in `languages/typescript.md`
- Express patterns -> `frameworks/express/conventions.md` (middleware, error handlers, route grouping, NestJS patterns)
- `frameworks/express/variants/typescript.md`
- `frameworks/express/testing/vitest.md` — Express testing patterns (supertest, in-memory server)
- Migrate config files

- [ ] **Step 5: Verify all 4 backend migrations**

```bash
for fw in fastapi axum vapor express; do
  echo "=== $fw ===" && ls modules/frameworks/$fw/
done
```

- [ ] **Step 6: Commit backend migrations**

```bash
git add modules/frameworks/fastapi/ modules/frameworks/axum/ modules/frameworks/vapor/ modules/frameworks/express/
git commit -m "feat: migrate fastapi, axum, vapor, express into frameworks/"
```

---

## Task 7: Migrate Infrastructure and Special Modules

**Files:**
- Create: `modules/frameworks/k8s/` (from infra-k8s)
- Create: `modules/frameworks/embedded/` (from c-embedded)
- Handle: go-stdlib (language-only, no framework)

- [ ] **Step 1: Migrate K8s**

Read `infra-k8s/conventions.md`. This module has no language layer (YAML/Helm templates):
- `frameworks/k8s/conventions.md` — Helm charts, K8s security, resource management, probes, GitOps, Docker
- No variants directory (no language layer)
- No testing directory (no traditional tests — helm lint/template)
- Migrate config files

- [ ] **Step 2: Migrate Embedded**

Read `c-embedded/conventions.md`. Split:
- C idioms already in `languages/c.md`
- Embedded patterns -> `frameworks/embedded/conventions.md` (ISR patterns, RTOS, real-time safety, hardware abstraction)
- `frameworks/embedded/variants/c.md` — C+Embedded specifics
- Minimal testing (hardware test patterns)
- Migrate config files

- [ ] **Step 3: Handle go-stdlib**

Go stdlib has no framework — only language + testing. Create a minimal framework entry:
- `frameworks/go-stdlib/conventions.md` — stdlib-specific patterns (net/http handlers, http.ServeMux, encoding/json)
- `frameworks/go-stdlib/variants/go.md` — minimal (stdlib is the "framework")
- Migrate config files
- NOTE: The orchestrator should handle `framework: go-stdlib` by loading language + this minimal framework + testing. No variant layer needed beyond the stub.

- [ ] **Step 4: Verify special modules**

```bash
for fw in k8s embedded go-stdlib; do
  echo "=== $fw ===" && ls modules/frameworks/$fw/
done
```

- [ ] **Step 5: Commit special module migrations**

```bash
git add modules/frameworks/k8s/ modules/frameworks/embedded/ modules/frameworks/go-stdlib/
git commit -m "feat: migrate k8s, embedded, go-stdlib into frameworks/"
```

---

## Task 8: Rename Learnings Files

**Files:**
- Rename: `shared/learnings/kotlin-spring.md` -> `shared/learnings/spring.md`
- Rename: `shared/learnings/java-spring.md` -> `shared/learnings/spring.md` (merge content)
- Rename: `shared/learnings/react-vite.md` -> `shared/learnings/react.md`
- Rename: `shared/learnings/typescript-svelte.md` -> `shared/learnings/sveltekit.md`
- Rename: `shared/learnings/typescript-node.md` -> `shared/learnings/express.md`
- Rename: `shared/learnings/python-fastapi.md` -> `shared/learnings/fastapi.md`
- Rename: `shared/learnings/go-stdlib.md` -> `shared/learnings/go-stdlib.md` (keep)
- Rename: `shared/learnings/rust-axum.md` -> `shared/learnings/axum.md`
- Rename: `shared/learnings/swift-ios.md` -> `shared/learnings/swiftui.md`
- Rename: `shared/learnings/swift-vapor.md` -> `shared/learnings/vapor.md`
- Rename: `shared/learnings/c-embedded.md` -> `shared/learnings/embedded.md`
- Rename: `shared/learnings/infra-k8s.md` -> `shared/learnings/k8s.md`

- [ ] **Step 1: Rename all learnings files**

```bash
cd shared/learnings/
mv kotlin-spring.md spring.md
# Append java-spring content to spring.md if java-spring.md has content
cat java-spring.md >> spring.md 2>/dev/null; rm -f java-spring.md
mv react-vite.md react.md
mv typescript-svelte.md sveltekit.md
mv typescript-node.md express.md
mv python-fastapi.md fastapi.md
mv rust-axum.md axum.md
mv swift-ios.md swiftui.md
mv swift-vapor.md vapor.md
mv c-embedded.md embedded.md
mv infra-k8s.md k8s.md
```

- [ ] **Step 2: Verify learnings files match frameworks**

```bash
for fw in spring react sveltekit express fastapi go-stdlib axum swiftui vapor embedded k8s; do
  test -f shared/learnings/$fw.md && echo "OK: $fw" || echo "MISSING: $fw"
done
```

- [ ] **Step 3: Commit learnings migration**

```bash
git add shared/learnings/
git commit -m "refactor: rename learnings files to match new framework names"
```

---

## Task 9: Delete Old Module Directories

**Files:**
- Delete: all 12 `modules/{old-name}/` directories

- [ ] **Step 1: Verify new structure has all content**

Run a comparison to ensure nothing was lost:

```bash
# Count sections in old conventions vs new (framework + language + variant)
for old in kotlin-spring java-spring react-vite python-fastapi go-stdlib rust-axum swift-ios swift-vapor typescript-node typescript-svelte c-embedded infra-k8s; do
  echo "=== $old ==="
  grep -c '^## ' modules/$old/conventions.md 2>/dev/null || echo "already moved"
done
```

- [ ] **Step 2: Delete old directories**

```bash
rm -rf modules/kotlin-spring modules/java-spring modules/react-vite modules/python-fastapi
rm -rf modules/go-stdlib modules/rust-axum modules/swift-ios modules/swift-vapor
rm -rf modules/typescript-node modules/typescript-svelte modules/c-embedded modules/infra-k8s
```

- [ ] **Step 3: Verify clean structure**

```bash
ls modules/
# Expected: frameworks/  languages/  testing/
# No old module directories
```

- [ ] **Step 4: Commit deletion**

```bash
git add -A modules/
git commit -m "refactor: remove old flat module directories (migrated to three-layer structure)"
```

---

## Task 10: Update Agent, Skill, and Script References

Files outside tests and CLAUDE.md that reference old `modules/{name}/` paths must be updated.

**Files:**
- Modify: `shared/checks/engine.sh` (module rules-override path resolution)
- Modify: `agents/pl-200-planner.md` (conventions file references)
- Modify: `agents/pl-210-validator.md` (conventions file references)
- Modify: `skills/pipeline-init/SKILL.md` (module detection and template paths)
- Modify: any other files found by grep

- [ ] **Step 1: Find all references to old module paths**

```bash
grep -rn 'modules/kotlin-spring\|modules/java-spring\|modules/react-vite\|modules/python-fastapi\|modules/go-stdlib\|modules/rust-axum\|modules/swift-ios\|modules/swift-vapor\|modules/typescript-node\|modules/typescript-svelte\|modules/c-embedded\|modules/infra-k8s' --include='*.md' --include='*.sh' --include='*.json' . | grep -v '.git/' | grep -v 'docs/superpowers/'
```

- [ ] **Step 2: Update shared/checks/engine.sh**

The check engine resolves `modules/${module}/rules-override.json`. Update the path resolution to use `modules/frameworks/${framework}/rules-override.json`. The module variable may come from `.pipeline/.module-cache` — update the cache logic to store the framework name.

- [ ] **Step 3: Update agent references**

In agents that reference specific module paths (e.g., `modules/kotlin-spring/conventions.md`), replace with the generic pattern `modules/frameworks/{framework}/conventions.md`. These are documentation references, not runtime paths (runtime paths come from `dev-pipeline.local.md` config).

- [ ] **Step 4: Update pipeline-init skill**

The init skill detects the project's framework and copies the template from `modules/{detected_module}/local-template.md`. Update to `modules/frameworks/{detected_framework}/local-template.md`. Also update the module detection logic to output framework names instead of old module names.

- [ ] **Step 5: Verify no old module path references remain**

```bash
grep -rn 'modules/kotlin-spring\|modules/java-spring\|modules/react-vite\|modules/python-fastapi\|modules/go-stdlib\|modules/rust-axum\|modules/swift-ios\|modules/swift-vapor\|modules/typescript-node\|modules/typescript-svelte\|modules/c-embedded\|modules/infra-k8s' --include='*.md' --include='*.sh' --include='*.json' . | grep -v '.git/' | grep -v 'docs/superpowers/'
# Expected: no output
```

- [ ] **Step 6: Commit reference updates**

```bash
git add shared/checks/ agents/ skills/
git commit -m "refactor: update agent, skill, and engine references to new module paths"
```

---

## Task 11: Run Full Test Suite and Fix

- [ ] **Step 1: Run structural tests**

```bash
./tests/run-all.sh structural
```

Fix any failures. Common issues:
- Path mismatches in validate-plugin.sh
- Missing files in the new structure
- Assertion count changes

- [ ] **Step 2: Run contract tests**

```bash
./tests/run-all.sh contract
```

Fix module-completeness assertions.

- [ ] **Step 3: Run unit tests**

```bash
./tests/run-all.sh unit
```

Fix any module detection cache or path issues in check engine tests.

- [ ] **Step 4: Run scenario tests**

```bash
./tests/run-all.sh scenario
```

Fix module-override scenarios that reference old paths.

- [ ] **Step 5: Run full suite**

```bash
./tests/run-all.sh
```

Expected: ALL PASS. If not, iterate until green.

- [ ] **Step 6: Commit test fixes**

```bash
git add tests/
git commit -m "fix: update all test tiers for three-layer module structure"
```

---

## Task 12: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update module documentation**

Replace the "Adding a new module" section to reference the new structure. Update:
- Module directory references (`modules/` -> `modules/frameworks/`, `modules/languages/`, `modules/testing/`)
- CI smoke test commands
- Manual check commands
- Module specifics section (now references framework + variant)
- The `conventions_file` path convention

- [ ] **Step 2: Update Gotchas section**

Add notes about:
- Convention composition order (variant > framework-testing > framework > language > testing)
- Framework-less projects (`framework: null` or `go-stdlib`)
- `language: null` for infrastructure frameworks (k8s)

- [ ] **Step 3: Commit CLAUDE.md update**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for three-layer module architecture"
```

---

## Task 13: Final Verification

- [ ] **Step 1: Run complete test suite**

```bash
./tests/run-all.sh
```

All tiers must pass.

- [ ] **Step 2: Verify file counts**

```bash
echo "Languages: $(ls modules/languages/*.md | wc -l)"    # Expected: 9
echo "Frameworks: $(ls -d modules/frameworks/*/ | wc -l)"  # Expected: 11
echo "Testing: $(ls modules/testing/*.md | wc -l)"         # Expected: 11
echo "Learnings: $(ls shared/learnings/*.md | wc -l)"      # Expected: 12+
```

- [ ] **Step 3: Verify no old module directories remain**

```bash
# Should return nothing
ls -d modules/*/ 2>/dev/null | grep -v frameworks | grep -v languages | grep -v testing
```

- [ ] **Step 4: Run CI smoke test from CLAUDE.md**

```bash
set -e
test "$(grep -l '^name:' agents/*.md | wc -l)" -ge 20
for m in modules/frameworks/*/; do
  ls "$m"{conventions.md,local-template.md,pipeline-config-template.md,rules-override.json,known-deprecations.json} > /dev/null
done
test -z "$(find modules/ hooks/ shared/ -name '*.sh' ! -perm -111 2>/dev/null)"
echo "Plugin structure OK"
```

- [ ] **Step 5: Final commit if any remaining fixes**

```bash
git add -A
git status
# If changes exist:
git commit -m "fix: final adjustments for module restructuring"
```
