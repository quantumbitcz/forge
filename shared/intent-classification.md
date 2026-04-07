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
| **single-feature** | Clear, bounded requirement with identifiable scope | Default when no other intent matches | `fg-100-orchestrator` standard mode |

## Classification Priority

When multiple intents match, use this precedence (highest first):
1. Explicit prefix/flag override (always wins)
2. bugfix (specific, actionable)
3. migration (specific pattern)
4. bootstrap (specific or environmental)
5. multi-feature (structural detection)
6. vague (catch-all for unclear)
7. single-feature (default)

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
    - "Override: choose mode" (description: "Let me pick: bugfix / migration / bootstrap / multi-feature / shape first")
- `autonomous: true`: Use classified mode directly. Log: `[AUTO-ROUTE] Classified as {intent} based on signals: {signal_list}`

## Config

| Parameter | Location | Range | Default | Description |
|-----------|----------|-------|---------|-------------|
| `routing.auto_classify` | `forge-config.md` | boolean | `true` | Enable/disable intent classification |
| `routing.vague_threshold` | `forge-config.md` | low / medium / high | `medium` | How aggressively to route to shaper |
| `scope.auto_decompose` | `forge-config.md` | boolean | `true` | Enable/disable auto-decomposition |
| `scope.decomposition_threshold` | `forge-config.md` | 2-10 | `3` | Domain count that triggers deep scan |
| `scope.fast_scan` | `forge-config.md` | boolean | `true` | Enable pre-exploration text analysis |
