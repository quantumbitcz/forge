# Q07: Module Structural Tests

## Status
DRAFT — 2026-04-13

## Problem Statement

Module System scored A (95/100) in the system review. Three issues prevent reaching A+:

1. **No automated framework conformance test against `base-template.md`.** The file `modules/frameworks/base-template.md` defines required files per framework (`conventions.md`, `local-template.md`, `forge-config-template.md`, `rules-override.json`, `known-deprecations.json`), required sections in conventions files, and required fields in config templates. While `tests/lib/module-lists.bash` discovers frameworks and defines `REQUIRED_FRAMEWORK_FILES`, no bats test validates the content conformance (only file existence). A framework could ship with an empty `conventions.md` or a `forge-config-template.md` missing `total_retries_max` and pass all current tests.

2. **Cross-cutting modules have no structural consistency test.** The 10 cross-cutting module directories (`auth/`, `observability/`, `messaging/`, `caching/`, `search/`, `storage/`, `databases/`, `persistence/`, `migrations/`, `api-protocols/`) each contain `.md` files with varying structures. Some follow the pattern documented in CLAUDE.md (Overview, Architecture, Config, Performance, Security, Testing, Dos, Don'ts), others do not. There is no test enforcing consistency.

3. **Variant coverage analysis is absent.** Spring has Kotlin/Java variants. No other framework has variants, but some arguably should (React TypeScript/JavaScript, Next.js TypeScript/JavaScript). More importantly, there is no documented rationale for why most frameworks lack variants -- is it intentional or an oversight?

## Target
Module System A -> A+ (95 -> 98+)

## Detailed Changes

### 1. Framework Conformance Test Suite

**New file:** `tests/structural/framework-conformance.bats`

This test suite validates every framework directory under `modules/frameworks/` against the requirements in `base-template.md`.

#### Test 1.1: Required Files Exist

Already partially covered by existing tests via `REQUIRED_FRAMEWORK_FILES` in `module-lists.bash`. This test makes it explicit:

```bash
@test "framework ${fw} has all required files" {
  for required in conventions.md local-template.md forge-config-template.md rules-override.json known-deprecations.json; do
    [ -f "$PLUGIN_ROOT/modules/frameworks/${fw}/${required}" ]
  done
}
```

Run for all 21 frameworks via bats `--filter-tags` or loop.

#### Test 1.2: conventions.md Has Required Sections

Every framework's `conventions.md` must contain `## Dos` and `## Don'ts` sections at minimum. These sections are the primary input for code review agents.

```bash
@test "framework ${fw} conventions.md has Dos and Don'ts sections" {
  local conv="$PLUGIN_ROOT/modules/frameworks/${fw}/conventions.md"
  grep -q '^## Dos' "$conv"
  grep -q "^## Don'ts" "$conv"
}
```

#### Test 1.3: forge-config-template.md Contains Required Fields

The config template must include `total_retries_max` and `oscillation_tolerance` as documented in CLAUDE.md ("New framework" section).

```bash
@test "framework ${fw} forge-config-template.md has total_retries_max" {
  local cfg="$PLUGIN_ROOT/modules/frameworks/${fw}/forge-config-template.md"
  grep -q 'total_retries_max' "$cfg"
}

@test "framework ${fw} forge-config-template.md has oscillation_tolerance" {
  local cfg="$PLUGIN_ROOT/modules/frameworks/${fw}/forge-config-template.md"
  grep -q 'oscillation_tolerance' "$cfg"
}
```

#### Test 1.4: known-deprecations.json Validates Against v2 Schema

Every `known-deprecations.json` must be valid JSON and contain entries with at least the v2 required fields (`pattern`, `replacement`, `since`).

```bash
@test "framework ${fw} known-deprecations.json is valid v2 schema" {
  local dep="$PLUGIN_ROOT/modules/frameworks/${fw}/known-deprecations.json"
  # Must be valid JSON
  python3 -c "import json; json.load(open('$dep'))"
  # Must be a non-empty array (at least 5 entries per CLAUDE.md)
  local count
  count=$(python3 -c "import json; d=json.load(open('$dep')); print(len(d.get('deprecations', d if isinstance(d, list) else [])))")
  [ "$count" -ge 5 ]
  # Each entry must have pattern, replacement, since
  python3 -c "
import json, sys
data = json.load(open('$dep'))
entries = data.get('deprecations', data) if isinstance(data, dict) else data
for i, e in enumerate(entries):
    for field in ['pattern', 'replacement', 'since']:
        if field not in e:
            print(f'Entry {i} missing {field}', file=sys.stderr)
            sys.exit(1)
"
}
```

#### Test 1.5: rules-override.json is Valid JSON

```bash
@test "framework ${fw} rules-override.json is valid JSON" {
  python3 -c "import json; json.load(open('$PLUGIN_ROOT/modules/frameworks/${fw}/rules-override.json'))"
}
```

#### Test 1.6: local-template.md Has YAML Frontmatter

Every `local-template.md` must have YAML frontmatter delimited by `---` containing at least `components:` and `commands:`.

```bash
@test "framework ${fw} local-template.md has required frontmatter fields" {
  local tpl="$PLUGIN_ROOT/modules/frameworks/${fw}/local-template.md"
  # Has frontmatter delimiters
  head -1 "$tpl" | grep -q '^---'
  # Has components and commands sections
  grep -q '^components:' "$tpl" || grep -q '^  components:' "$tpl"
  grep -q '^commands:' "$tpl" || grep -q '^  commands:' "$tpl"
}
```

#### Test 1.7: Shared Default Drift Detection

Validate that shared default sections in each framework's `local-template.md` match the canonical values in `base-template.md`. Focus on the most critical shared defaults:

```bash
@test "framework ${fw} local-template.md has correct implementation defaults" {
  local tpl="$PLUGIN_ROOT/modules/frameworks/${fw}/local-template.md"
  grep -q 'parallel_threshold: 3' "$tpl"
  grep -q 'max_fix_loops: 3' "$tpl"
  grep -q 'tdd: true' "$tpl"
}
```

### 2. Cross-Cutting Module Consistency Test Suite

**New file:** `tests/structural/crosscutting-modules.bats`

Validates that all `.md` files in cross-cutting module directories follow a consistent structure.

#### Target directories

The 10 cross-cutting directories containing domain-specific best practice modules:
- `modules/auth/` (10 files: auth0, cognito, firebase-auth, jwt, keycloak, oauth2, passport, saml, session-based, supabase-auth)
- `modules/observability/` (10 files: datadog, grafana, health-checks, jaeger, loki, micrometer, opentelemetry, prometheus, sentry, structured-logging)
- `modules/messaging/` (files: kafka, rabbitmq, sqs, nats, redis-pubsub, etc.)
- `modules/caching/` (files: redis, memcached, caffeine, etc.)
- `modules/search/` (files: elasticsearch, algolia, etc.)
- `modules/storage/` (files: s3, azure-blob, gcs, etc.)
- `modules/databases/` (files: postgresql, mysql, mongodb, etc.)
- `modules/persistence/` (files: hibernate, prisma, etc.)
- `modules/migrations/` (files: flyway, liquibase, alembic, etc.)
- `modules/api-protocols/` (files: rest, graphql, grpc, etc.)

#### Test 2.1: Required Sections Present

Each `.md` file (excluding READMEs and index files) must contain at minimum:

```bash
@test "crosscutting module ${module_file} has required sections" {
  local f="$module_file"
  # Must have at least 4 of these 8 standard sections
  local section_count=0
  grep -q '^## Overview' "$f" && ((section_count++)) || true
  grep -q '^## Architecture\|^## Config' "$f" && ((section_count++)) || true
  grep -q '^## Performance' "$f" && ((section_count++)) || true
  grep -q '^## Security' "$f" && ((section_count++)) || true
  grep -q '^## Testing' "$f" && ((section_count++)) || true
  grep -q '^## Dos' "$f" && ((section_count++)) || true
  grep -q "^## Don'ts" "$f" && ((section_count++)) || true
  # At least 4 sections required (Overview + 3 of the domain sections)
  [ "$section_count" -ge 4 ]
}
```

**Rationale for 4-of-7 threshold:** Not every module needs every section (e.g., a caching module may not have a meaningful "Security" section beyond "use TLS"). Requiring 4 ensures a minimum level of completeness while allowing flexibility.

#### Test 2.2: Minimum File Size

Cross-cutting modules should be substantive, not stubs:

```bash
@test "crosscutting module ${module_file} is substantive (>50 lines)" {
  local line_count
  line_count=$(wc -l < "$module_file")
  [ "$line_count" -ge 50 ]
}
```

#### Test 2.3: Dos/Don'ts Section Quality

If `## Dos` or `## Don'ts` sections exist, they should contain at least 3 entries each:

```bash
@test "crosscutting module ${module_file} has substantive Dos/Don'ts" {
  local f="$module_file"
  if grep -q '^## Dos' "$f"; then
    local dos_count
    dos_count=$(sed -n '/^## Dos/,/^## /p' "$f" | grep -c '^- ' || echo 0)
    [ "$dos_count" -ge 3 ]
  fi
}
```

### 3. Variant Analysis and Documentation

**New file:** `modules/frameworks/VARIANTS.md`

A living document that records the variant analysis for each framework.

**Content structure:**

```markdown
# Framework Variant Analysis

## Existing Variants

### Spring: kotlin / java
- **Rationale:** Kotlin variant uses hexagonal architecture with sealed interfaces, ports & adapters.
  Java variant uses layered architecture with standard Spring patterns. The architectural
  differences are significant enough to warrant separate convention files.
- **Files:** `variants/kotlin.md`, `variants/java.md`

## Frameworks That Do NOT Need Variants

### React, Vue, Svelte, Angular, SvelteKit, Next.js
- **Rationale:** These frameworks are TypeScript-first. JavaScript usage is legacy and declining.
  The convention differences between TS and JS are limited to type annotations and build config,
  which are handled by the language module (`modules/languages/typescript.md`). A separate variant
  would duplicate 95% of content.
- **Exception:** If a project explicitly uses JavaScript without TypeScript, the language detection
  in `engine.sh` already handles this (`.js`/`.jsx` map to `typescript` language module which
  covers both).

### FastAPI, Django
- **Rationale:** Python-only. No meaningful variant axis.

### Axum, Vapor, Embedded
- **Rationale:** Single-language frameworks. No variant axis.

### Go-stdlib, Gin
- **Rationale:** Go-only. No variant axis.

### ASP.NET
- **Rationale:** C#-only in practice. F# is theoretically possible but would be a separate
  framework module, not a variant.

### Jetpack Compose, Kotlin Multiplatform
- **Rationale:** Kotlin-only. Platform target (Android/iOS/Desktop/Web) is handled by the
  framework's conventions directly, not via variants.

### K8s
- **Rationale:** Infrastructure, no language. No variant axis.

### Express, NestJS
- **Rationale:** TypeScript-first. Same reasoning as React group above.

## Future Variant Candidates

None currently identified. If a framework develops a meaningful architectural axis
(not just language syntax differences), add a variant directory with conventions.
```

**Integration:** Link from `CLAUDE.md` gotchas section: "Variants exist only for Spring (kotlin/java). See `modules/frameworks/VARIANTS.md` for rationale."

### 4. Learnings File Coverage Test

**New test in** `tests/structural/framework-conformance.bats`:

```bash
@test "framework ${fw} has learnings file" {
  [ -f "$PLUGIN_ROOT/shared/learnings/${fw}.md" ]
}
```

**New test for languages:**

```bash
@test "language ${lang} has learnings file" {
  [ -f "$PLUGIN_ROOT/shared/learnings/${lang}.md" ]
}
```

This validates the requirement from CLAUDE.md: "New framework -> also `shared/learnings/{name}.md`."

**Discovery:** Run `ls shared/learnings/` against `DISCOVERED_FRAMEWORKS` and `DISCOVERED_LANGUAGES` arrays from `module-lists.bash` to identify any missing learnings files before committing the test.

### 5. Update module-lists.bash Minimum Counts

After implementing the above tests, update `tests/lib/module-lists.bash` if new modules or files have been added. Current minimums:

```bash
MIN_FRAMEWORKS=21      # Unchanged unless new frameworks added
MIN_LANGUAGES=15       # Unchanged unless new languages added
MIN_TESTING_FILES=19   # Unchanged unless new testing modules added
MIN_LAYERS=12          # Verify current count matches
```

Add new minimum counts for cross-cutting module validation:

```bash
# Cross-cutting module file counts (per directory)
MIN_AUTH_MODULES=10
MIN_OBSERVABILITY_MODULES=10
MIN_MESSAGING_MODULES=5
MIN_CACHING_MODULES=3
MIN_SEARCH_MODULES=2
MIN_STORAGE_MODULES=3
MIN_DATABASE_MODULES=5
MIN_PERSISTENCE_MODULES=3
MIN_MIGRATION_MODULES=3
MIN_API_PROTOCOL_MODULES=3
```

These counts serve as accidental-deletion guards, same as the existing framework/language counts.

## Testing Approach

1. **Run all new bats tests** against the current module tree to identify existing conformance gaps.

2. **Fix conformance gaps first:** Before committing the tests, ensure all 21 frameworks pass the conformance checks. This may require:
   - Adding missing sections to `conventions.md` files
   - Adding missing fields to `forge-config-template.md` files
   - Adding missing deprecation entries to `known-deprecations.json` files
   - Creating missing `shared/learnings/{name}.md` files

3. **Run `validate-plugin.sh`** to ensure no structural regressions.

4. **Run the full test suite** (`./tests/run-all.sh`) to ensure new tests integrate cleanly.

## Acceptance Criteria

- [ ] `tests/structural/framework-conformance.bats` exists and passes for all 21 frameworks
- [ ] Test validates: required files, conventions sections, config fields, deprecations schema, rules-override JSON, local-template frontmatter, shared default drift
- [ ] `tests/structural/crosscutting-modules.bats` exists and passes for all cross-cutting module files
- [ ] Test validates: required sections (4-of-7 minimum), minimum file size (50 lines), Dos/Don'ts quality
- [ ] `modules/frameworks/VARIANTS.md` documents variant rationale for all 21 frameworks
- [ ] Learnings file coverage test passes for all frameworks and languages
- [ ] `tests/lib/module-lists.bash` updated with cross-cutting module minimum counts
- [ ] All conformance gaps in existing modules are fixed before tests are committed
- [ ] `validate-plugin.sh` continues to pass (51+ checks)

## Effort Estimate

Medium (3-4 days). Test writing is straightforward; the bulk of effort is fixing any conformance gaps discovered in existing modules.

- Framework conformance tests: 1 day
- Cross-cutting module tests: 0.5 day
- Variant analysis document: 0.5 day
- Learnings coverage test: 0.25 day
- Fixing discovered conformance gaps: 1-2 days (depends on gap count)
- module-lists.bash updates: 0.25 day

## Dependencies

- Requires `tests/lib/module-lists.bash` to be sourced (already the standard pattern)
- Requires Python 3 for JSON schema validation in deprecations test (already a prerequisite per `check-prerequisites.sh`)
- No dependency on other Q-series specs
- Should be implemented before Q08 (documentation completeness) since conformance fixes may create documentation updates
