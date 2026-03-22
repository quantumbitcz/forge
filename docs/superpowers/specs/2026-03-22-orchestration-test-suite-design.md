# Orchestration Test Suite Design

**Date:** 2026-03-22
**Scope:** Comprehensive testing for the dev-pipeline plugin orchestration system
**Approach:** Hybrid — standalone structural validator + bats-core behavioral tests

## Problem

The dev-pipeline plugin has zero test coverage. It contains ~16 shell scripts (check engine, hooks, health checks, linter adapters) and ~40+ structured documents (agent frontmatter, module configs, deprecation registries) that must conform to documented contracts. Changes to shared contracts (`scoring.md`, `stage-contract.md`, `state-schema.md`) affect all agents and modules, but there's no automated way to catch regressions.

## Architecture

Three test tiers, each targeting a different layer of the system:

### Tier 1 — Structural Validation (`tests/validate-plugin.sh`)

A standalone bash script (no dependencies beyond bash + jq) that validates plugin integrity. Replaces and extends the ad-hoc validation commands in CLAUDE.md. Designed as the first CI gate.

**Checks (~25):**

1. All agents have valid YAML frontmatter (name, description fields)
2. Agent `name` matches filename without `.md`
3. Pipeline agents follow `pl-{NNN}-{role}` naming
4. Cross-cutting review agents have `tools` list in frontmatter
5. All agents have "Forbidden Actions" section
6. All 12 modules have 5 required files (conventions.md, local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json)
7. All `conventions.md` files have Dos/Don'ts section
8. All `pipeline-config-template.md` files have `total_retries_max` field
9. All `pipeline-config-template.md` files have `oscillation_tolerance` field
10. All `local-template.md` files have `linear:` section
11. All `rules-override.json` files are valid JSON
12. All `known-deprecations.json` files are valid JSON
13. All `known-deprecations.json` files are schema v2 (`"version": 2`)
14. All deprecation entries have required v2 fields (`pattern`, `replacement`, `package`, `since`, `applies_from`, `applies_to`)
15. All shell scripts have shebang line
16. All shell scripts are executable (`chmod +x`)
17. `hooks/hooks.json` is valid JSON
18. `hooks/hooks.json` has expected hook event types (PostToolUse, Stop)
19. Skills have required frontmatter (name, description)
20. `shared/checks/layer-2-linter/config/severity-map.json` is valid JSON
21. All layer-1 pattern files are valid JSON
22. All pattern rules have required fields (id, pattern, severity, category, message)
23. Pattern rule IDs are unique within each language file
24. Shared learnings files exist for each module
25. Plugin manifest (`plugin.json`) version matches CLAUDE.md version

### Tier 2 — Unit Tests (`tests/unit/*.bats`)

bats-core tests for individual scripts in isolation. External tools (linters, git, docker) are mocked or bypassed.

#### `engine.bats` (~13 tests)
- Hook mode: extracts file_path from TOOL_INPUT JSON
- Hook mode: extracts file_path via regex fallback when python3 JSON fails
- Hook mode: skips nonexistent files (silent)
- Hook mode: skips generated sources (`build/generated-sources`)
- Hook mode: prevents double execution via `_ENGINE_RUNNING` (second invocation: exit 0, no stdout)
- Hook mode: increments skip counter on ERR trap
- Verify mode: processes multiple `--files-changed`
- Verify mode: runs Layer 1 + Layer 2
- Review mode: runs Layer 1 + Layer 2 + Layer 3 stub
- Default mode (no args) is `--hook`
- Always exits 0 regardless of errors
- Handles empty TOOL_INPUT gracefully
- python3 unavailable for JSON parsing → falls back to regex → if regex also fails, silent exit 0

#### `patterns.bats` (~15 tests)
- Matches pattern in file and emits finding
- Respects `exclude_pattern` (filters false positives)
- Scope `main`: fires for src/main, silent for src/test
- Scope `test`: fires for src/test, silent for src/main
- Scope `all`: fires for any path
- Scope regex: fires only for matching paths (e.g., `/adapter/`)
- `scope_exclude`: skips files matching exclusion pattern
- Case-insensitive matching when `case_insensitive: true`
- Threshold: file size above default emits WARNING
- Threshold: file size within limit is silent
- Threshold: path-specific override replaces default
- Threshold: function size detection (Kotlin `fun` declarations)
- Rule merging: base + override additional_rules produces union
- Rule merging: `disabled_rules` removes base rules
- Rule merging: `severity_overrides` changes severity
- Boundary checks: forbidden import in scope emits finding
- Boundary checks: forbidden import outside scope is silent
- Output format matches `file:line | CATEGORY | SEVERITY | message | fix_hint`
- Pipe characters in messages are escaped as `\|`

#### `linter-dispatch.bats` (~7 tests)
- Selects primary linter for each language
- Falls back to secondary when primary missing
- Exits silently when no linter available
- Resolves `clippy` → `cargo` for command check
- Passes correct args to adapter script
- Handles non-executable adapter gracefully
- Emits INFO message to stderr when no linter available

#### `detekt-adapter.bats` (~8 tests)
- Parses detekt output format (`path:line:col: message [RuleId]`)
- Exact severity match (e.g., `SwallowedException` → CRITICAL)
- Glob prefix severity match (e.g., `complexity.TooManyFunctions` → WARNING via `complexity.*`)
- Longest glob prefix wins
- Default severity is INFO for unknown rules
- Category mapping: security keywords → SEC-DETEKT
- Category mapping: performance keywords → PERF-DETEKT
- Category mapping: exception keywords → QUAL-ERR
- Exits 1 when detekt not available
- Exits 2 on real linter error (non-zero exit + empty output)

#### `hooks.bats` (~10 tests)
- Check engine hook: runs engine.sh with TOOL_INPUT
- Check engine hook: timeout simulation (skip counter increment)
- Checkpoint hook: updates lastCheckpoint in state.json
- Checkpoint hook: handles missing state.json (exits 0)
- Checkpoint hook: python3 path (JSON manipulation)
- Checkpoint hook: sed fallback when python3 unavailable
- Feedback hook: appends timestamped line to auto-captured.md
- Feedback hook: creates feedback directory if missing
- Feedback hook: exits 0 when .pipeline/ missing
- All hooks exit 0 on any error

#### `health-checks.bats` (~14 tests)
- pre-stage-health: PREFLIGHT requires git + python3
- pre-stage-health: IMPLEMENT checks disk space (mock `df` via PATH override)
- pre-stage-health: IMPLEMENT detects git merge in progress
- pre-stage-health: IMPLEMENT detects git rebase in progress
- pre-stage-health: VERIFY detects module-specific tools (assert stderr WARN/INFO, stdout still OK)
- pre-stage-health: SHIP checks gh CLI (present vs missing)
- pre-stage-health: PREVIEW checks network connectivity + npx
- pre-stage-health: explore/plan/validate/review/docs/learn return OK (no deps)
- pre-stage-health: unknown stage returns OK
- dependency-check: docker daemon running → OK
- dependency-check: docker command exists but daemon down → UNAVAILABLE
- dependency-check: context7 always returns OK (passive check)
- dependency-check: git-remote with reachable remote → OK
- dependency-check: unknown dependency reports UNAVAILABLE

#### `language-detection.bats` (~6 tests)
- File extension → language mapping (all 8 languages)
- Module detection from manifest files (build.gradle.kts + kotlin → kotlin-spring)
- Module detection from explicit config (`dev-pipeline.local.md`)
- Module detection caching (second call reads cache)
- Cache invalidation when config is newer
- Unknown project structure returns empty

### Tier 3 — Contract Tests (`tests/contract/*.bats`)

Validate that all structured documents conform to their documented contracts.

#### `agent-frontmatter.bats` (~8 tests)
- All agent `.md` files have YAML frontmatter (starts with `---`)
- All agents have `name:` field
- All agents have `description:` field
- Pipeline agents: `name` matches `pl-{NNN}-{role}` pattern
- Pipeline agents: `name` matches filename (without `.md`)
- Review agents: frontmatter includes `tools:` list
- Agent count is >= 20 (catches accidental deletion)
- No duplicate agent names

#### `module-completeness.bats` (~6 tests)
- All 12 modules exist
- Each module has all 5 required files
- `conventions.md` contains "Dos" and "Don'ts" sections
- `pipeline-config-template.md` contains `total_retries_max` and `oscillation_tolerance`
- `local-template.md` contains `linear:` section
- Learnings file exists in `shared/learnings/` for each module

#### `deprecation-schema.bats` (~6 tests)
- All deprecation files have `"version": 2`
- All entries have required fields: `pattern`, `replacement`, `package`, `since`, `applies_from`, `applies_to`
- `added` and `addedBy` fields present in all entries
- No empty `pattern` fields
- `removed_in` is either null or a non-empty string
- No duplicate patterns within a module file

#### `hooks-json.bats` (~6 tests)
- `hooks/hooks.json` is valid JSON
- Contains `PostToolUse` and `Stop` event types
- Nested structure: each event type entry has a `hooks` array
- Each nested hook entry has `type`, `command`, and `timeout` fields
- `PostToolUse` entries have a `matcher` field; `Stop` entries do not require one
- Timeout values are positive integers

#### `script-permissions.bats` (~4 tests)
- All `.sh` files in `shared/`, `hooks/`, `modules/` have shebang
- All `.sh` files are executable
- No `.sh` files have Windows line endings (CRLF)
- engine.sh, run-patterns.sh, run-linter.sh exist and are executable

#### `output-format.bats` (~5 tests)
- Pattern rules emit findings matching `file:line | CATEGORY | SEVERITY | message | fix_hint`
- SEVERITY is exactly `CRITICAL`, `WARNING`, or `INFO`
- CATEGORY matches known prefixes (ARCH-, SEC-, PERF-, QUAL-, CONV-, DOC-, TEST-, FE-, SCOUT-, HEX-, THEME-, DETEKT-)
- Line number is a positive integer or 0 (file-level)
- Deduplication key `(file, line, category)` is unique in output

### Tier 4 — Scenario Tests (`tests/scenario/*.bats`)

Integration-level tests exercising multi-script workflows with fixture data.

#### `check-engine-flow.bats` (~7 tests)
- Kotlin file with antipatterns → hook mode → correct findings
- TypeScript file with theme violations → hook mode → FE-THEME findings
- Clean file → hook mode → no output
- File change → verify mode → Layer 1 + Layer 2 findings
- Multiple files → verify mode → findings from all files
- Non-code file → all modes → silent
- Generated source path → all modes → silent

#### `module-override-merge.bats` (~6 tests)
- kotlin-spring overrides: adds architecture rules to kotlin base
- kotlin-spring overrides: `disabled_rules` suppresses base rules
- react-vite overrides: adds theme rules to typescript base
- react-vite overrides: threshold overrides (400 line file size)
- Override `scope_pattern` normalized to `scope`
- Empty override file → base rules only

#### `scope-filtering.bats` (~6 tests)
- `main` scope: matches `src/main/`, rejects `src/test/`
- `test` scope: matches `src/test/`, rejects `src/main/`
- `all` scope: matches everything
- Regex scope: `/adapter/` matches `src/main/kotlin/adapter/Foo.kt`
- `scope_exclude`: `src/app/components/ui/` excludes shadcn components
- Combined scope + scope_exclude: both conditions applied

#### `threshold-overrides.bats` (~5 tests)
- Default file size threshold (300 lines for kotlin, 400 for react-vite override)
- Path-specific override: `port/` files get 100-line limit
- Path-specific override: `adapter/` files get 200-line limit
- Function size threshold: large Kotlin function detected
- Function size threshold: function within limit is silent

#### `skip-counter.bats` (~4 tests)
- ERR trap → `.pipeline/.check-engine-skipped` created with count 1
- Second error → count incremented to 2
- Counter file absent → created fresh
- `.pipeline/` directory absent → no counter file created

#### `checkpoint-state.bats` (~5 tests)
- Valid state.json → lastCheckpoint updated
- State.json with existing lastCheckpoint → overwritten
- Missing state.json → no-op (exit 0)
- Malformed state.json → no crash (exit 0), original file not corrupted (mv never executes)
- Timestamp format is ISO 8601 UTC

#### `linter-output-parsing.bats` (~6 tests)
Version-gating logic lives in Layer 3 (agent-driven, not shell). Instead, this file tests linter adapter output parsing end-to-end with pre-recorded linter output fixtures:
- Detekt output → correct findings format
- ESLint output → correct findings format (via eslint adapter parsing)
- Severity map: exact match takes precedence over glob prefix
- Severity map: longest glob prefix wins over shorter
- Unknown rule ID → defaults to INFO
- Empty linter output → no findings (silent)

## Test Infrastructure

### Dependencies

- **bats-core** — installed as git submodule at `tests/lib/bats-core`
- **bats-support** — git submodule at `tests/lib/bats-support`
- **bats-assert** — git submodule at `tests/lib/bats-assert`
- **jq** — required for structural validation (pre-installed on macOS, available in CI)
- **python3** — required (already a pipeline dependency)

### Shared helpers (`tests/helpers/test-helpers.bash`)

```bash
# Loaded by every .bats file via: load '../helpers/test-helpers'
# Provides:
#   - PLUGIN_ROOT: absolute path to plugin root
#   - create_temp_project <module>: creates fake project dir with manifest files
#   - create_temp_file <subpath> <content>: creates file in temp dir
#   - create_state_json <version> [fields...]: creates state.json fixture
#   - assert_finding_format: validates output matches finding format
#   - assert_no_findings: validates empty output
#   - mock_command <name> <behavior>: creates mock in $BATS_TEST_TMPDIR/bin (prepended to PATH)
```

### Mocking strategy

Some tests require mocking external commands:
- **`df`** — mocked via PATH override for disk space tests in `health-checks.bats`
- **`git`** — mocked for module detection cache tests and merge/rebase detection
- **Linter binaries** (detekt, eslint, etc.) — NOT mocked; adapter tests feed pre-recorded output files directly to the parsing logic
- **`python3`** — NOT mocked (too pervasive); tests that need "python3 unavailable" behavior are documented as known limitations

### Fixture files

Pre-built test data committed to `tests/fixtures/`:

- **State fixtures**: Valid v1.1, v1.2, v1.3 state.json files + a corrupted one
- **Project fixtures**: Minimal directory structures that trigger each module detection path
- **Pattern fixtures**: Source files with known antipatterns (Kotlin, TypeScript) and clean files
- **Deprecation fixtures**: Valid v2, legacy v1, and invalid JSON files

### Runner (`tests/run-all.sh`)

```bash
#!/usr/bin/env bash
# Runs all test tiers in order. Exits non-zero on first failure.
# Usage: ./tests/run-all.sh [--tier structural|unit|contract|scenario]

1. validate-plugin.sh (structural, ~2s)
2. bats unit/*.bats (unit, ~10s)
3. bats contract/*.bats (contract, ~5s)
4. bats scenario/*.bats (scenario, ~15s)
```

## Test count summary

| Tier | Files | Est. tests | Runtime |
|------|-------|------------|---------|
| Structural | 1 | ~25 | ~2s |
| Unit | 7 | ~74 | ~10s |
| Contract | 6 | ~35 | ~5s |
| Scenario | 7 | ~39 | ~15s |
| **Total** | **21** | **~173** | **~32s** |

## Design notes

**Tier 1/Tier 3 overlap is intentional.** Structural validation (Tier 1) and contract tests (Tier 3) check many of the same things (agent frontmatter, module files). Tier 1 is a zero-dependency CI gate (bash + jq only); Tier 3 provides more detailed bats assertions. This defense-in-depth ensures the plugin doesn't ship broken even if bats isn't installed.

**Dockerfile/YAML patterns are unreachable.** Layer-1 pattern files exist for `dockerfile.json` and `yaml.json`, but `engine.sh`'s `detect_language` function has no cases for `.dockerfile`/`.yml`/`.yaml` extensions. These patterns are never dispatched. This is a known gap in the engine, not a test gap. Tests document this behavior (language detection returns empty → silent).

## What is NOT tested

- **Agent behavior** — agents are markdown prompts; their logic is executed by AI at runtime. We test the contracts they must conform to, not their reasoning.
- **Version-gating logic** — lives in Layer 3 agent intelligence (not yet implemented as shell). Deferred until shell implementation exists.
- **State schema migration logic** — migration chain (1.1 → 1.2 → 1.3) is agent-driven. Fixtures validate the expected schema structure, not the migration code.
- **Linear MCP integration** — requires live Linear API. Tested via manual pipeline runs.
- **Actual linter execution** — adapter tests validate output parsing, not linter installation.
- **Full pipeline end-to-end** — would require a consuming project with real build tools. The existing `/pipeline-run --dry-run` serves this purpose.
- **python3 unavailability paths** — python3 is too pervasive to mock (used by bats helpers, patterns engine, checkpoint hook). The `sed` fallback in checkpoint is documented but not tested.

## Implementation plan

1. Install bats-core + helpers as git submodules
2. Create `tests/helpers/test-helpers.bash`
3. Create all fixture files
4. Implement `tests/validate-plugin.sh`
5. Implement unit tests (engine → patterns → linter → detekt → hooks → health → language)
6. Implement contract tests
7. Implement scenario tests
8. Create `tests/run-all.sh` runner
9. Run full suite, fix any failures
10. Update CLAUDE.md validation section to reference `tests/run-all.sh`
