# Intent Classification

Reference document for the intent classification system used by `/forge-run` to auto-route requirements to the correct pipeline mode.

## Classification Table

| Intent | Signals | Confidence Threshold | Route |
|--------|---------|---------------------|-------|
| **bugfix** | "fix", "bug", "broken", "regression", "error", "crash", "404", "500", stack traces, ticket with `bug` label | Any 2+ signals or 1 strong signal (stack trace, error code) | `fg-020-bug-investigator` → `fg-100` bugfix mode |
| **migration** | "upgrade", "migrate", "replace X with Y", "move from X to Y", version numbers in context | Pattern: `{verb} {from} to/with {to}` | `fg-100` migration mode → `fg-160` |
| **bootstrap** | "scaffold", "create new", "start from scratch", "initialize", "new project", empty project root | Any 1+ signal or empty project detection | `fg-100` bootstrap mode → `fg-050` |
| **multi-feature** | 3+ distinct domain nouns joined by conjunctions, enumerated capabilities ("1. X 2. Y 3. Z"), "also add", "plus", "on top of" | 3+ distinct features detected | `fg-015-scope-decomposer` → `fg-090` |
| **vague** | Very short (<10 words with no specifics), very long (>500 words), no acceptance criteria, exploratory language ("something like", "maybe", "could we", "what if"), OR under 50 words missing 3+ completeness signals (actors, entities, surface, criteria) | Qualitative assessment per `routing.vague_threshold` | `fg-010-shaper` → shaped spec → re-enter |
| **testing** | "add tests", "test coverage", "e2e tests", "integration tests", "unit tests", testing frameworks, coverage thresholds | Any 2+ signals or 1 strong signal (coverage percentage, test framework name) | `fg-100-orchestrator` standard mode (implementer focuses on test files only; quality gate uses reduced reviewer set) |
| **documentation** | "document", "write docs", "generate API docs", "ADR", "architecture docs", "changelog" | Any 2+ signals or 1 strong signal (specific doc type like "ADR", "OpenAPI") | `fg-350-docs-generator` standalone mode (skip pipeline stages 4-6) |
| **refactor** | "refactor", "extract", "consolidate", "reduce duplication", "technical debt", "cleanup", "restructure" | Any 2+ signals or 1 strong signal with clear scope (file or module named) | `fg-100-orchestrator` standard mode (planner uses refactor constraints: same behavior, no new features, maintain test suite) |
| **performance** | "optimize", "performance", "slow", "latency", "bundle size", "memory", "N+1", "throughput", "cache" | Any 2+ signals or 1 strong signal with measurable target | `fg-100-orchestrator` standard mode (EXPLORE includes profiling/benchmarking, REVIEW uses performance-focused reviewer set) |
| **single-feature** | Clear, bounded requirement with identifiable scope | Default when no other intent matches | `fg-100-orchestrator` standard mode |

## Hybrid-grammar verbs (added 2026-04-27)

The new `/forge` skill (per spec §1) recognizes 11 explicit verbs as the FIRST token of input. When present, the verb wins outright — no signal-counting, no NL classification. The classifier still runs to populate downstream telemetry but its outcome is overridden.

| Verb | Mode |
|---|---|
| `run` | `single-feature` (or downstream split via multi-feature detection) |
| `fix` | `bugfix` |
| `sprint` | `multi-feature` (sprint orchestration) |
| `review` | `review` (read or fix scope, per `--scope`/`--fix` flags) |
| `verify` | `verify` (build/lint/test or config) |
| `deploy` | `deploy` |
| `commit` | `commit` |
| `migrate` | `migration` |
| `bootstrap` | `bootstrap` (greenfield) |
| `docs` | `documentation` |
| `audit` | `security-audit` |

Detection rule: `^\s*(run|fix|sprint|review|verify|deploy|commit|migrate|bootstrap|docs|audit)\b`. The match is case-sensitive and operates on the trimmed input. Anything matching falls into the verb's mode unconditionally.

When the input does NOT match the verb regex, the rest of this document's classifier runs as before — including the `vague` outcome below.

## Vague outcome (concrete threshold, added 2026-04-27)

The `vague` row in the table above is now defined concretely:

> **Vague triggers when:** the input contains fewer than 2 of the four completeness signals (actors, entities, surface, criteria) AND the input does not match any explicit verb regex AND no other intent reaches its confidence threshold.

When `vague` fires, the dispatcher routes to `run` mode (single-feature). The `run` pipeline immediately enters BRAINSTORMING (per spec §3), where `fg-010-shaper` resolves the ambiguity through clarifying questions.

This keeps the classifier deterministic — it never returns `vague` and walks away. It always returns a route; `vague` is just the route that says "go through BRAINSTORMING first."

## Classification Priority

When multiple intents match, use this precedence (highest first):
1. Explicit hybrid-grammar verb (always wins — see "Hybrid-grammar verbs" above)
2. Explicit prefix/flag override (always wins)
3. bugfix (specific, actionable)
4. migration (specific pattern)
5. bootstrap (specific or environmental)
6. multi-feature (structural detection)
7. testing (specific — test-focused requests)
8. documentation (specific — doc-focused requests)
9. refactor (specific — improvement-focused requests)
10. performance (specific — performance-focused requests)
11. vague (catch-all for unclear)
12. single-feature (default)

## Signal Detection Rules

### Bugfix Signals
- Keywords: fix, bug, broken, regression, error, crash, fail, wrong, incorrect, 404, 500, exception, null, undefined
- Patterns: error codes (`HTTP 4xx/5xx`), stack traces (multi-line with `at` or `File` prefixes), "doesn't work", "stopped working"
- Ticket context: ticket with `bug` label, priority `urgent`/`critical`

### Migration Signals
- Keywords: upgrade, migrate, replace, move, switch, transition, update (in context of library/framework)
- Patterns: "from X to Y", "replace X with Y", "upgrade X to version Y", version numbers (e.g., "3.2 to 3.4")
- NOT migration: database migrations (these are implementation details, not pipeline mode)

### Bootstrap Signals
- Keywords: scaffold, create new, start from scratch, initialize, new project, greenfield, setup
- Environmental: empty project root (no source files), missing build configuration
- NOT bootstrap: adding a new module to an existing project (that's a standard feature)

### Multi-Feature Signals
- Conjunctions joining distinct domains: "auth AND billing AND notifications"
- Enumerated items: "1. user auth 2. payment processing 3. email notifications"
- Additive language: "also add", "plus", "on top of that", "additionally"
- Domain count: 3+ unrelated bounded contexts in a single requirement
- NOT multi-feature: a single feature with multiple implementation steps ("add auth with JWT tokens, refresh tokens, and session management" — this is one feature with sub-tasks)

### Testing Signals
- Keywords: test, tests, testing, coverage, e2e, integration test, unit test, snapshot test, test suite, TDD
- Patterns: coverage percentages ("increase to 80%"), test framework names ("add vitest", "set up playwright"), "test the X module"
- NOT testing: "test if this works" (exploratory language, route to vague), bug reports containing test failures (route to bugfix)
- Modifier: requests that mention both testing AND a feature ("add auth with tests") are single-feature — the "tests" part is an implementation detail, not the primary intent

### Documentation Signals
- Keywords: document, documentation, docs, write docs, generate docs, ADR, architecture decision record, README, changelog, API docs, OpenAPI, Swagger
- Patterns: "document the X", "generate API docs from Y", "write ADR for Z", "update README"
- NOT documentation: "document as we go" (this is a process instruction, not an intent)

### Refactor Signals
- Keywords: refactor, extract, consolidate, reduce duplication, technical debt, cleanup, restructure, simplify, decompose, decouple
- Patterns: "extract X into Y", "refactor X to use Y", "consolidate X and Y", "reduce complexity in Z"
- NOT refactor: "refactor" used loosely ("let's refactor this approach" — exploratory, route to vague)
- Scope requirement: refactor intent requires naming at least one file, module, or bounded context. "Refactor everything" is vague.

### Performance Signals
- Keywords: optimize, performance, slow, latency, bundle size, memory, N+1, throughput, cache, profiling, benchmark, response time
- Patterns: measurable targets ("reduce from 500ms to 100ms"), specific bottlenecks ("N+1 queries in user list"), resource metrics ("reduce bundle size by 30%")
- NOT performance: "optimize the codebase" (too vague — no specific bottleneck or target)

### Vague Signals
- Length extremes: <10 words with no technical specifics, or >500 words of stream-of-consciousness
- Exploratory language: "something like", "maybe we could", "what if", "I'm thinking about"
- Missing specifics: no endpoints, no data models, no user flows, no acceptance criteria
- **Feature completeness check** (NEW): Requirements under 50 words that lack 3+ of the following are vague regardless of how "clear" the noun sounds:
  - Specific user roles or actors ("admin can", "logged-in users")
  - Data entities or models ("creates an order", "updates the user profile")
  - UI surface or endpoint ("on the dashboard", "POST /api/shares", "in the settings page")
  - Acceptance criteria or success conditions ("should display X", "must validate Y")
  - A requirement like "Add user sharing" or "Add notifications" is vague — it has a verb+noun but no specifics about what, how, or for whom
  - Exception: well-known feature names ("OAuth2", "TOTP", "SSO", "MFA", "dark mode", "i18n") or clear improvement verbs ("fix", "optimize", "refactor") count as 1 implicit signal
- Threshold levels: `low` (aggressively route to shaper — almost everything gets shaped), `medium` (default — shapes anything missing 3+ completeness signals), `high` (rarely shape — only shapes extremely vague input)

## Autonomous Mode

- `autonomous: false` (default): Present classification result via AskUserQuestion with structured options:
  - Header: "Intent Classification"
  - Question: "This looks like a **{classified_mode}** based on: {signal_summary}. Proceed with this routing?"
  - Options:
    - "{classified_mode} mode" (description: "Route to {target_agent}")
    - "Override: standard feature" (description: "Treat as single feature, route to fg-100")
    - "Override: choose mode" (description: "Let me pick: bugfix / migration / bootstrap / multi-feature / testing / documentation / refactor / performance / shape first")
- `autonomous: true`: Use classified mode directly. Log: `[AUTO-ROUTE] Classified as {intent} based on signals: {signal_list}`

## Config

| Parameter | Location | Range | Default | Description |
|-----------|----------|-------|---------|-------------|
| `routing.auto_classify` | `forge-config.md` | boolean | `true` | Enable/disable intent classification |
| `routing.vague_threshold` | `forge-config.md` | low / medium / high | `medium` | How aggressively to route to shaper |
| `scope.auto_decompose` | `forge-config.md` | boolean | `true` | Enable/disable auto-decomposition |
| `scope.decomposition_threshold` | `forge-config.md` | 2-10 | `3` | Domain count that triggers deep scan |
| `scope.fast_scan` | `forge-config.md` | boolean | `true` | Enable pre-exploration text analysis |
