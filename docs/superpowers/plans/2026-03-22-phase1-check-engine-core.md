# Phase 1: Check Engine Core — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the generalized three-layer check engine that replaces per-module bash scripts, including the first language rule file (kotlin.json) and migration of the kotlin-spring module as a proof-of-concept.

**Architecture:** A unified `engine.sh` entry point detects language from file extensions, loads JSON rule files, dispatches checks across three layers (fast grep patterns, linter bridge, agent intelligence). Module overrides add framework-specific rules on top of base language rules. All output uses the unified finding format from `scoring.md`.

**Tech Stack:** Bash, Python 3 (stdlib `json` module for parsing), grep, awk (for structural checks)

**Spec:** `docs/superpowers/specs/2026-03-21-generalized-check-engine-design.md` — Foundational Contracts + Phase 1 sections

**Convention:** All work in git worktrees. No Co-Authored-By in commits. Conventional commit format.

---

## File Structure

### New files (PR #1: check-engine-core)

| File | Responsibility |
|---|---|
| `shared/checks/engine.sh` | Unified entry point: parse args, detect language, detect module, dispatch to run-patterns.sh |
| `shared/checks/layer-1-fast/run-patterns.sh` | Load JSON rules via python3, iterate rules, run grep/awk, format findings |
| `shared/checks/output-format.md` | Documented finding format contract |
| `shared/checks/layer-1-fast/patterns/kotlin.json` | Kotlin language rules (first language, proves the schema) |
| `modules/kotlin-spring/rules-override.json` | Spring-specific overrides for kotlin rules (migrated from check-antipatterns.sh) |

### Modified files (PR #1)

| File | Change |
|---|---|
| `modules/kotlin-spring/scripts/check-antipatterns.sh` | Convert to thin wrapper calling engine.sh (backward compat) |
| `modules/kotlin-spring/scripts/check-core-boundary.sh` | Convert to thin wrapper calling engine.sh |
| `modules/kotlin-spring/scripts/check-file-size.sh` | Convert to thin wrapper calling engine.sh |

### Subsequent PRs (outlined, not task-by-task)

| PR | Key files | Notes |
|---|---|---|
| #2 `feat/language-rules` | `patterns/{java,typescript,python,go,rust,c,swift}.json` + `examples/**/*.md` (~35 files) | Follow kotlin.json schema exactly |
| #3 `feat/linter-bridge` | `layer-2-linter/{run-linter.sh,adapters/*.sh,config/severity-map.json,defaults/*}` | Each adapter is a standalone script |
| #4 `feat/agent-intelligence` | `layer-3-agent/{deprecation-refresh.md,version-compat.md,known-deprecations/*.json}` | Two agent .md files + 8 seed JSONs |
| #5 `feat/new-modules` | `modules/{9 dirs}/conventions.md,local-template.md,rules-override.json` | Follow kotlin-spring pattern |
| #6 `feat/migrate-existing-modules` | Update kotlin-spring + react-vite, delete old scripts | Depends on #1 and #2 |

---

## PR #1: Check Engine Core (detailed tasks)

### Task 1: Output format contract

**Files:**
- Create: `shared/checks/output-format.md`

- [ ] **Step 1: Write the output format document**

```markdown
# Check Engine Output Format

All three layers (fast patterns, linter bridge, agent intelligence) emit findings in this format.

## Finding Format

One finding per line:

```
file:line | CATEGORY-CODE | SEVERITY | message | fix_hint
```

### Field definitions

- `file` — project-relative path (e.g., `src/main/kotlin/domain/User.kt`)
- `line` — 1-based line number. `0` for file-level findings (e.g., file too large).
- `CATEGORY-CODE` — from scoring.md taxonomy: `ARCH-*`, `SEC-*`, `PERF-*`, `QUAL-*`, `CONV-*`, `DOC-*`, `TEST-*`. Module-specific: `HEX-*`, `THEME-*`. Subcategories: `QUAL-NULL`, `QUAL-READ`, `PERF-BLOCK`, `PERF-ASYNC`. (Reserved for Phase 2: `CONTRACT-BREAK`, `CONTRACT-CHANGE`, `CONTRACT-ADD`.)
- `SEVERITY` — exactly one of: `CRITICAL`, `WARNING`, `INFO`.
- `message` — human-readable description.
- `fix_hint` — one-line suggested fix. Empty string if no hint.

### Delimiter

Pipe `|` with spaces. If message or hint contains `|`, escape as `\|`.

### Deduplication

Deduplication key: `(file, line, category)`. When duplicates exist across layers, keep the finding with the highest severity and the longest description.

### Multi-line findings

Emit one line per finding location. Group in post-processing.

### JSON metadata keys

Underscore-prefixed keys (`_match_order`, `_severity_map`, `_note`) in any JSON config file are documentation/metadata. Parsers must skip keys starting with `_`.
```

- [ ] **Step 2: Commit**

```bash
git add shared/checks/output-format.md
git commit -m "docs: add check engine output format contract"
```

---

### Task 2: Kotlin language rules JSON

**Files:**
- Create: `shared/checks/layer-1-fast/patterns/kotlin.json`

This migrates the 7 checks from `check-antipatterns.sh` + boundary checks from `check-core-boundary.sh` + thresholds from `check-file-size.sh` into a single JSON file, plus adds readability rules.

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p shared/checks/layer-1-fast/patterns
```

- [ ] **Step 2: Write kotlin.json**

The JSON contains rules migrated from:
- `check-antipatterns.sh` lines 23-109 → rules KT-NULL-001 through KT-EXCEPT-001
- `check-core-boundary.sh` lines 20-38 → boundaries
- `check-file-size.sh` lines 19-45 → thresholds

Plus new readability rules (KT-READ-001 through KT-READ-003).

See spec section "Rule JSON schema" for the exact schema. The JSON should have:
- `language`: "kotlin"
- `extensions`: [".kt", ".kts"]
- `rules`: array of ~12 rules covering null assertions, blocking calls, thread usage, hardcoded credentials, console output, transactional misuse, java UUID in core, java time in core, raw exceptions, deep nesting, magic numbers, abbreviated names
- `thresholds`: file_size (default 300, overrides for impl/controller/mapper/test), function_size (default 30)
- `boundaries`: framework imports in domain, Spring Data/R2DBC in domain
- `deprecations`: pointer to `layer-3-agent/known-deprecations/kotlin.json`

- [ ] **Step 3: Validate JSON is parseable**

```bash
python3 -c "import json; json.load(open('shared/checks/layer-1-fast/patterns/kotlin.json'))" && echo "Valid JSON"
```

Expected: "Valid JSON"

- [ ] **Step 4: Commit**

```bash
git add shared/checks/layer-1-fast/patterns/kotlin.json
git commit -m "feat: add kotlin language rules for check engine"
```

---

### Task 3: Kotlin-Spring module override JSON

**Files:**
- Create: `modules/kotlin-spring/rules-override.json`

- [ ] **Step 1: Write rules-override.json**

Migrates the framework-specific checks from `check-antipatterns.sh` (transactional on adapter, java UUID/time in core) and `check-core-boundary.sh` (adapter imports in core) into the override format.

Must include:
- `extends`: "kotlin"
- `framework`: "spring"
- `additional_rules`: transactional-on-adapter (KS-ARCH-001), java-uuid-in-core (KS-ARCH-002), java-time-in-core (KS-ARCH-003), console-output (KS-CONV-001). Note: KS-ARCH-002/003 and KS-CONV-001 are intentional additions migrated from check-antipatterns.sh lines 79-76 — the spec's override example only shows KS-ARCH-001 as illustration. Override rules use `scope_pattern` (regex on path), not `scope` (semantic value).
- `additional_boundaries`: core must not import adapters (CRITICAL)
- `disabled_rules`: empty array `[]` (placeholder, proves the field works)
- `severity_overrides`: empty object `{}` (placeholder, proves the field works)
- `threshold_overrides`: port/ 100, adapter/ 200, use case impl/ 150

- [ ] **Step 2: Validate JSON**

```bash
python3 -c "import json; json.load(open('modules/kotlin-spring/rules-override.json'))" && echo "Valid JSON"
```

- [ ] **Step 3: Commit**

```bash
git add modules/kotlin-spring/rules-override.json
git commit -m "feat: add kotlin-spring module override rules"
```

---

### Task 4: run-patterns.sh — the pattern matching engine

**Files:**
- Create: `shared/checks/layer-1-fast/run-patterns.sh`

This is the core of Layer 1. It:
1. Receives a file path and the loaded rules (as JSON via stdin or temp file)
2. For each rule: checks scope, runs grep with the pattern, excludes matches by exclude_pattern, formats output
3. Checks file-size and function-size thresholds (awk pass)
4. Checks boundary rules (grep for forbidden imports in scoped files)
5. Checks deprecation patterns (loads known-deprecations JSON if referenced)

- [ ] **Step 1: Write run-patterns.sh skeleton**

Create the script with:
- Shebang `#!/usr/bin/env bash`, `set -euo pipefail`
- Input: `$1` = file path, `$2` = rules JSON path, `$3` = override JSON path (optional)
- Python3 helper function that extracts fields from JSON (reusable for rules, thresholds, boundaries)
- Main loop structure: load rules → iterate → grep → format
- Exit 0 always (warnings only, never blocks)

- [ ] **Step 2: Implement rule matching**

For each rule in the JSON `rules` array:
1. Check `scope` against file path (skip if file doesn't match scope)
2. Run `grep -nE "$pattern" "$FILE"` to find matches
3. Filter out lines matching `exclude_pattern`
4. If `case_insensitive` is true, use `grep -niE`
5. Format each match as: `relative_path:line | category | severity | message | fix_hint`

- [ ] **Step 3: Implement threshold checks**

Single awk pass for both file-size and function-size:
- Count total lines → compare against file_size threshold (choose threshold by matching path against overrides)
- Track function boundaries (language-specific: `fun ` for Kotlin) and count lines between them → compare against function_size threshold

- [ ] **Step 4: Implement boundary checks**

For each boundary rule:
1. Check `scope_pattern` against file path
2. If in scope: grep for each `forbidden_imports` pattern
3. Format matches as findings

- [ ] **Step 5: Implement override merging**

If override JSON path is provided:
1. Load override JSON
2. Add `additional_rules` to rule list
3. Add `additional_boundaries` to boundary list
4. Apply `threshold_overrides` (replace matching path entries)
5. Apply `severity_overrides` (change severity for matching rule IDs)
6. Filter out `disabled_rules` (skip rules with matching IDs)

- [ ] **Step 6: Test manually against a Kotlin file**

```bash
# Create a test file with known antipatterns
cat > /tmp/test-antipatterns.kt << 'KOTLIN'
package cz.quantumbit.wellplanned.core.domain

import java.util.UUID
import org.springframework.data.annotation.Id

class TestDomain {
    val id = UUID.randomUUID()!!
    fun doWork() {
        Thread.sleep(1000)
        println("debug")
        throw RuntimeException("oops")
    }
}
KOTLIN

chmod +x shared/checks/layer-1-fast/run-patterns.sh
bash shared/checks/layer-1-fast/run-patterns.sh /tmp/test-antipatterns.kt \
  shared/checks/layer-1-fast/patterns/kotlin.json \
  modules/kotlin-spring/rules-override.json
```

Expected: findings for `!!`, `Thread.sleep`, `java.util.UUID`, `org.springframework.data`, `println`, `RuntimeException`

- [ ] **Step 7: Commit**

```bash
chmod +x shared/checks/layer-1-fast/run-patterns.sh
git add shared/checks/layer-1-fast/run-patterns.sh
git commit -m "feat: implement pattern matching engine for Layer 1 checks"
```

---

### Task 5: engine.sh — unified entry point

**Files:**
- Create: `shared/checks/engine.sh`

This is the dispatcher. Handles three modes (--hook, --verify, --review), detects language, detects module, and calls run-patterns.sh.

- [ ] **Step 1: Write engine.sh with mode parsing**

Handle `--hook`, `--verify`, and `--review` modes per the spec's Invocation Contract. In `--hook` mode:
1. Extract file path from `$TOOL_INPUT` (same logic as current scripts)
2. Skip non-code files, generated sources
3. Detect language from file extension
4. Find rules JSON at `${CLAUDE_PLUGIN_ROOT}/shared/checks/layer-1-fast/patterns/{language}.json`
5. Detect module from `.claude/dev-pipeline.local.md` (cache in `.pipeline/.module-cache`)
6. Find override JSON at `${CLAUDE_PLUGIN_ROOT}/modules/{module}/rules-override.json`
7. Call `run-patterns.sh "$FILE" "$RULES_JSON" "$OVERRIDE_JSON"`

- [ ] **Step 2: Implement language detection**

Map file extensions to language names:
- `.kt`, `.kts` → kotlin
- `.java` → java
- `.ts`, `.tsx` → typescript
- `.js`, `.jsx` → typescript (uses same rules)
- `.py` → python
- `.go` → go
- `.rs` → rust
- `.c`, `.h` → c
- `.swift` → swift

Skip files with extensions not in this map.

- [ ] **Step 3: Implement module detection**

Read `module:` from `.claude/dev-pipeline.local.md` YAML frontmatter (grep + sed). Cache result in `.pipeline/.module-cache`. Invalidate cache if local.md is newer than cache file.

Fallback: auto-detect from project markers per spec.

- [ ] **Step 4: Test engine.sh in hook mode**

```bash
chmod +x shared/checks/engine.sh
TOOL_INPUT='{"file_path": "/tmp/test-antipatterns.kt"}' \
CLAUDE_PLUGIN_ROOT="$(pwd)" \
  bash shared/checks/engine.sh --hook
```

Expected: same findings as Task 4 Step 6

- [ ] **Step 5: Commit**

```bash
chmod +x shared/checks/engine.sh
git add shared/checks/engine.sh
git commit -m "feat: implement check engine entry point with language and module detection"
```

---

### Task 6: Update plugin.json with engine.sh hook

**Files:**
- Modify: `plugin.json`

- [ ] **Step 1: Add Edit|Write hook entry to plugin.json**

Add a new `PostToolUse` entry with `"matcher": "Edit|Write"` that calls `${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --hook`. Keep existing Skill matcher for checkpoint hook. Bump version to `0.2.0`.

See spec section "Hook Registration in plugin.json" for exact JSON structure.

- [ ] **Step 2: Validate JSON**

```bash
python3 -c "import json; json.load(open('plugin.json'))" && echo "Valid JSON"
```

- [ ] **Step 3: Commit**

```bash
git add plugin.json
git commit -m "feat: register check engine as PostToolUse hook for Edit/Write"
```

---

### Task 7: Backward compatibility wrappers

**Files:**
- Modify: `modules/kotlin-spring/scripts/check-antipatterns.sh`
- Modify: `modules/kotlin-spring/scripts/check-core-boundary.sh`
- Modify: `modules/kotlin-spring/scripts/check-file-size.sh`

**Note:** Consuming projects that have old per-script hooks in `.claude/settings.json` AND the new plugin.json `Edit|Write` hook will get duplicate checks. The wrappers detect this: if `CLAUDE_PLUGIN_ROOT` is already set (meaning engine.sh was invoked by the plugin hook), the wrapper exits silently to avoid duplication. Consuming projects should remove old hook entries from settings.json.

- [ ] **Step 1: Convert check-antipatterns.sh to a wrapper**

Replace the body with:
```bash
#!/usr/bin/env bash
# DEPRECATED: This script is a thin wrapper. Use shared/checks/engine.sh instead.
# Will be removed in the next release.

# Avoid duplicate checks if engine.sh was already invoked by plugin hook
if [ -n "${_ENGINE_RUNNING:-}" ]; then exit 0; fi

echo "WARNING: check-antipatterns.sh is deprecated. Use engine.sh --hook instead." >&2
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" _ENGINE_RUNNING=1 exec "$PLUGIN_ROOT/shared/checks/engine.sh" --hook
```

- [ ] **Step 2: Convert check-core-boundary.sh and check-file-size.sh similarly**

Same pattern — thin wrappers with duplication guard.

- [ ] **Step 3: Test that old invocation still works**

```bash
TOOL_INPUT='{"file_path": "/tmp/test-antipatterns.kt"}' \
  bash modules/kotlin-spring/scripts/check-antipatterns.sh
```

Expected: deprecation warning on stderr + findings on stdout

- [ ] **Step 4: Commit**

```bash
git add modules/kotlin-spring/scripts/
git commit -m "refactor: convert kotlin-spring scripts to engine.sh wrappers"
```

---

### Task 8: Integration test — full pipeline hook simulation

- [ ] **Step 1: Create an integration test script**

```bash
cat > shared/checks/test-engine.sh << 'TEST'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Check Engine Integration Test ==="

# Create temp project structure for realistic path-based scope matching
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/src/main/kotlin/core/domain"
mkdir -p "$TMPDIR/build/generated-sources"

# Test 1: Kotlin file with known antipatterns (in core/domain scope)
cat > "$TMPDIR/src/main/kotlin/core/domain/Bad.kt" << 'KOTLIN'
package cz.quantumbit.wellplanned.core.domain
import java.util.UUID
class Bad {
    val id = UUID.randomUUID()!!
    fun work() { Thread.sleep(100) }
}
KOTLIN

echo "--- Test 1: Kotlin antipatterns in core/domain ---"
TOOL_INPUT="{\"file_path\": \"$TMPDIR/src/main/kotlin/core/domain/Bad.kt\"}" \
CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$PLUGIN_ROOT/shared/checks/engine.sh" --hook || true

# Test 2: Non-Kotlin file (should be skipped silently)
echo "--- Test 2: Non-code file (should be silent) ---"
TOOL_INPUT="{\"file_path\": \"$TMPDIR/readme.md\"}" \
CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$PLUGIN_ROOT/shared/checks/engine.sh" --hook || true

# Test 3: Generated file (should be skipped)
cat > "$TMPDIR/build/generated-sources/Test.kt" << 'KOTLIN'
class Test {}
KOTLIN
echo "--- Test 3: Generated source (should be silent) ---"
TOOL_INPUT="{\"file_path\": \"$TMPDIR/build/generated-sources/Test.kt\"}" \
CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$PLUGIN_ROOT/shared/checks/engine.sh" --hook || true

# Cleanup
rm -rf "$TMPDIR"

echo "=== All tests complete ==="
TEST
chmod +x shared/checks/test-engine.sh
```

- [ ] **Step 2: Run the integration test**

```bash
bash shared/checks/test-engine.sh
```

Expected: Test 1 shows findings, Tests 2 and 3 are silent.

- [ ] **Step 3: Commit**

```bash
git add shared/checks/test-engine.sh
git commit -m "test: add check engine integration test"
```

---

## PRs #2-6: Outlined Tasks

These follow the patterns established in PR #1. Each PR is a separate worktree branch.

### PR #2: Language Rules + Examples (`feat/language-rules`)

| Task | Description | Files |
|---|---|---|
| 1 | Create java.json | `patterns/java.json` — adapt kotlin rules, add JPA/null patterns |
| 2 | Create typescript.json | `patterns/typescript.json` — any/eval/console, React-specific via override |
| 3 | Create python.json | `patterns/python.json` — bare except, mutable defaults, print |
| 4 | Create go.json | `patterns/go.json` — error not checked, fmt.Print, panic |
| 5 | Create rust.json | `patterns/rust.json` — unwrap, expect, unsafe blocks |
| 6 | Create c.json | `patterns/c.json` — malloc without free, buffer overflow patterns |
| 7 | Create swift.json | `patterns/swift.json` — force unwrap, implicitly unwrapped optionals |
| 8-15 | Create example files (one per language) | `examples/{lang}/error-handling.md` as first example per language |
| 16-35 | Create remaining example files | `examples/{lang}/{topic}.md` — 4-5 files per language |

Each JSON follows kotlin.json schema exactly. Validate with `python3 -c "import json; ..."`.

### PR #3: Linter Bridge (`feat/linter-bridge`)

| Task | Description | Files |
|---|---|---|
| 1 | Create run-linter.sh | Detect installed linter, dispatch adapter, normalize output |
| 2 | Create severity-map.json | Linter rule ID → pipeline severity mapping |
| 3 | Create detekt adapter | `adapters/detekt.sh` — run detekt, parse XML output, normalize |
| 4 | Create eslint adapter | `adapters/eslint.sh` — run eslint, parse JSON output, normalize |
| 5 | Create clippy adapter | `adapters/clippy.sh` — run cargo clippy, parse output |
| 6 | Create ruff adapter | `adapters/ruff.sh` — run ruff, parse JSON output |
| 7 | Create remaining adapters | go-vet.sh, clang-tidy.sh, swiftlint.sh, checkstyle.sh |
| 8 | Create default linter configs | `defaults/detekt.yml`, `defaults/eslint.config.js`, `defaults/ruff.toml` |
| 9 | Wire into engine.sh --verify mode | Add Layer 2 dispatch to engine.sh |

### PR #4: Agent Intelligence (`feat/agent-intelligence`)

| Task | Description | Files |
|---|---|---|
| 1 | Create deprecation-refresh.md agent | Agent instructions for refreshing known-deprecations |
| 2 | Create version-compat.md agent | Agent instructions for version compatibility checks |
| 3-10 | Create seed known-deprecations JSONs | One per language, seeded with well-known deprecations |

### PR #5: New Modules (`feat/new-modules`)

| Task | Description | Files per module |
|---|---|---|
| 1-9 | Create each module directory | `conventions.md`, `local-template.md`, `rules-override.json` |

Modules: java-spring, typescript-node, typescript-svelte, python-fastapi, go-stdlib, rust-axum, c-embedded, swift-vapor, swift-ios. Follow kotlin-spring pattern.

### PR #6: Migrate Existing Modules (`feat/migrate-existing-modules`)

| Task | Description |
|---|---|
| 1 | Migrate react-vite known-deprecations.json to new schema |
| 2 | Create react-vite rules-override.json (from guard hooks) |
| 3 | Convert react-vite guard hooks to wrappers |
| 4 | Update kotlin-spring local-template.md to reference engine.sh |
| 5 | Update react-vite local-template.md to reference engine.sh |
| 6 | Delete old scripts (kotlin-spring) and hooks (react-vite) — or keep as wrappers for one release |
