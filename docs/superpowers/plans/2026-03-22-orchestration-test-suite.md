# Orchestration Test Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a comprehensive test suite (~173 tests) for the dev-pipeline plugin using bats-core + a standalone structural validator.

**Architecture:** Three-tier hybrid approach: (1) `validate-plugin.sh` for zero-dependency CI structural checks, (2) bats-core unit tests for shell script behavior, (3) bats-core contract + scenario tests for document compliance and multi-script integration. All tests live in `tests/` with shared helpers and committed fixtures.

**Tech Stack:** bats-core (v1.11+), bats-support, bats-assert (git submodules), jq, python3, bash

**Spec:** `docs/superpowers/specs/2026-03-22-orchestration-test-suite-design.md`

---

## Task 1: Install bats-core infrastructure

**Files:**
- Create: `tests/lib/` (git submodules)
- Create: `.gitmodules` entries

- [ ] **Step 1: Add bats-core, bats-support, bats-assert as git submodules**
- [ ] **Step 2: Verify bats runs** (`tests/lib/bats-core/bin/bats --version`)
- [ ] **Step 3: Commit**

## Task 2: Create shared test helpers

**Files:**
- Create: `tests/helpers/test-helpers.bash`

Provides: PLUGIN_ROOT, create_temp_project(), create_temp_file(), create_state_json(), mock_command(), assert_finding_format(), assert_no_findings()

- [ ] **Step 1: Write test-helpers.bash** (see spec for API contract)
- [ ] **Step 2: Write and run smoke test to verify helpers load**
- [ ] **Step 3: Remove smoke test and commit**

## Task 3: Create fixture files

**Files:**
- Create: `tests/fixtures/state/v1.3-valid.json`
- Create: `tests/fixtures/state/v1.3-malformed.json`
- Create: `tests/fixtures/patterns/kotlin-bad.kt`
- Create: `tests/fixtures/patterns/kotlin-clean.kt`
- Create: `tests/fixtures/patterns/typescript-bad.tsx`
- Create: `tests/fixtures/patterns/typescript-clean.tsx`
- Create: `tests/fixtures/linter-output/detekt-sample.txt`
- Create: `tests/fixtures/linter-output/eslint-sample.json`
- Create: `tests/fixtures/overrides/add-rules.json`
- Create: `tests/fixtures/overrides/disable-rules.json`
- Create: `tests/fixtures/overrides/empty.json`

- [ ] **Step 1: Create state fixtures** (valid v1.3 + malformed JSON)
- [ ] **Step 2: Create Kotlin pattern fixtures** (bad with antipatterns + clean)
- [ ] **Step 3: Create TypeScript pattern fixtures** (bad with eval/any + clean)
- [ ] **Step 4: Create linter output fixtures** (detekt text + eslint JSON)
- [ ] **Step 5: Create override fixtures** (add-rules, disable-rules, empty)
- [ ] **Step 6: Commit**

## Task 4: Implement validate-plugin.sh (Tier 1)

**Files:**
- Create: `tests/validate-plugin.sh`

Standalone bash script, 25 structural checks. Each prints PASS/FAIL. Exit 1 on any failure.

Checks: agent frontmatter, name-filename match, Forbidden Actions, review tools list, module completeness (5 files x 12 modules), conventions Dos/Don'ts, template fields, JSON validity, deprecation schema v2, script shebangs + permissions, hooks.json structure, skill frontmatter, pattern rule fields + uniqueness, learnings files, plugin version match.

- [ ] **Step 1: Write validate-plugin.sh**
- [ ] **Step 2: Make executable and run** (`chmod +x tests/validate-plugin.sh && ./tests/validate-plugin.sh`)
- [ ] **Step 3: Fix any failures, commit**

## Task 5: Implement unit tests — engine.bats (~13 tests)

**Files:**
- Create: `tests/unit/engine.bats`

Tests: hook mode file_path extraction (JSON + regex fallback), skip nonexistent files, skip generated sources, _ENGINE_RUNNING guard, ERR trap skip counter, empty/missing TOOL_INPUT, default mode is --hook, verify mode multiple files, exits 0 always, non-code file silent.

- [ ] **Step 1: Write engine.bats**
- [ ] **Step 2: Run and verify** (`tests/lib/bats-core/bin/bats tests/unit/engine.bats`)
- [ ] **Step 3: Commit**

## Task 6: Implement unit tests — patterns.bats (~15 tests)

**Files:**
- Create: `tests/unit/patterns.bats`

Tests: pattern matching + emit, exclude_pattern, scope main/test/all/regex, scope_exclude, case_insensitive, file size threshold (default + override), function size, rule merging (add + disable + severity override), empty override, output format, TypeScript eval detection, clean file silent.

- [ ] **Step 1: Write patterns.bats**
- [ ] **Step 2: Run and verify**
- [ ] **Step 3: Commit**

## Task 7: Implement unit tests — linter-dispatch.bats + detekt-adapter.bats

**Files:**
- Create: `tests/unit/linter-dispatch.bats` (~7 tests)
- Create: `tests/unit/detekt-adapter.bats` (~8 tests)

Dispatch tests: no linter available, empty language/target, clippy→cargo resolution, non-executable adapter.
Detekt tests: exits 1 when unavailable, parses output format, exact severity match, glob prefix match, longest prefix wins, default INFO for unknown, category mapping.

- [ ] **Step 1: Write both files**
- [ ] **Step 2: Run and verify**
- [ ] **Step 3: Commit**

## Task 8: Implement unit tests — hooks.bats (~10 tests)

**Files:**
- Create: `tests/unit/hooks.bats`

Tests: checkpoint updates lastCheckpoint, ISO 8601 format, missing state.json no-op, malformed state.json not corrupted, feedback appends line, feedback creates dir, feedback exits 0 without .pipeline/, all hooks exit 0 on error.

- [ ] **Step 1: Write hooks.bats**
- [ ] **Step 2: Run and verify**
- [ ] **Step 3: Commit**

## Task 9: Implement unit tests — health-checks.bats + language-detection.bats

**Files:**
- Create: `tests/unit/health-checks.bats` (~14 tests)
- Create: `tests/unit/language-detection.bats` (~6 tests)

Health tests: PREFLIGHT, explore/plan OK, IMPLEMENT disk/merge/rebase, VERIFY module tools, SHIP gh, PREVIEW, unknown stage, case insensitive. dep-check: context7 OK, unknown, empty.
Language tests: all 8 extensions, module detection from manifests, explicit config, caching, unknown empty.

- [ ] **Step 1: Write both files**
- [ ] **Step 2: Run and verify**
- [ ] **Step 3: Commit**

## Task 10: Implement contract tests (6 files, ~35 tests)

**Files:**
- Create: `tests/contract/agent-frontmatter.bats` (8 tests)
- Create: `tests/contract/module-completeness.bats` (6 tests)
- Create: `tests/contract/deprecation-schema.bats` (6 tests)
- Create: `tests/contract/hooks-json.bats` (6 tests)
- Create: `tests/contract/script-permissions.bats` (4 tests)
- Create: `tests/contract/output-format.bats` (5 tests)

- [ ] **Step 1: Write all 6 contract test files**
- [ ] **Step 2: Run all** (`tests/lib/bats-core/bin/bats tests/contract/*.bats`)
- [ ] **Step 3: Commit**

## Task 11: Implement scenario tests (7 files, ~39 tests)

**Files:**
- Create: `tests/scenario/check-engine-flow.bats` (7 tests)
- Create: `tests/scenario/module-override-merge.bats` (6 tests)
- Create: `tests/scenario/scope-filtering.bats` (6 tests)
- Create: `tests/scenario/threshold-overrides.bats` (5 tests)
- Create: `tests/scenario/skip-counter.bats` (4 tests)
- Create: `tests/scenario/checkpoint-state.bats` (5 tests)
- Create: `tests/scenario/linter-output-parsing.bats` (6 tests)

- [ ] **Step 1: Write all 7 scenario test files**
- [ ] **Step 2: Run all** (`tests/lib/bats-core/bin/bats tests/scenario/*.bats`)
- [ ] **Step 3: Commit**

## Task 12: Create run-all.sh and final integration

**Files:**
- Create: `tests/run-all.sh`

Master runner that executes all 4 tiers in order. Accepts `--tier` argument for individual tiers. Exits on first failure.

- [ ] **Step 1: Write run-all.sh**
- [ ] **Step 2: Make executable and run full suite** (`chmod +x tests/run-all.sh && ./tests/run-all.sh`)
- [ ] **Step 3: Commit**

## Task 13: Run full suite and fix failures

- [ ] **Step 1: Run complete test suite** (`./tests/run-all.sh`)
- [ ] **Step 2: Fix any failures** (paths, git init, permissions, etc.)
- [ ] **Step 3: Re-run until clean**
- [ ] **Step 4: Commit fixes**

## Task 14: Update CLAUDE.md validation section

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add test suite reference** (run-all.sh + per-tier commands)
- [ ] **Step 2: Commit**
