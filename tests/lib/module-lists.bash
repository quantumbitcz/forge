#!/usr/bin/env bash
# Shared module list discovery for forge tests.
# Reads module lists from disk instead of hardcoding them.
# Provides minimum count guards to catch accidental deletions.
#
# Usage: source this file, then use the arrays and guard functions.
#   source "tests/lib/module-lists.bash"
#   for fw in "${DISCOVERED_FRAMEWORKS[@]}"; do ... done
#   guard_min_count "frameworks" "${#DISCOVERED_FRAMEWORKS[@]}" 21

PLUGIN_ROOT="${PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# ---------------------------------------------------------------------------
# Discover modules from disk
# ---------------------------------------------------------------------------

# Frameworks: directories under modules/frameworks/
DISCOVERED_FRAMEWORKS=()
for d in "$PLUGIN_ROOT"/modules/frameworks/*/; do
  [[ -d "$d" ]] && DISCOVERED_FRAMEWORKS+=("$(basename "$d")")
done

# Languages: .md files under modules/languages/
DISCOVERED_LANGUAGES=()
for f in "$PLUGIN_ROOT"/modules/languages/*.md; do
  [[ -f "$f" ]] && DISCOVERED_LANGUAGES+=("$(basename "$f" .md)")
done

# Testing: .md files under modules/testing/
DISCOVERED_TESTING_FILES=()
for f in "$PLUGIN_ROOT"/modules/testing/*.md; do
  [[ -f "$f" ]] && DISCOVERED_TESTING_FILES+=("$(basename "$f")")
done

# Build systems: .md files and directories (with conventions.md) under modules/build-systems/
DISCOVERED_BUILD_SYSTEMS=()
for f in "$PLUGIN_ROOT"/modules/build-systems/*.md; do
  [[ -f "$f" ]] && DISCOVERED_BUILD_SYSTEMS+=("$(basename "$f" .md)")
done
for d in "$PLUGIN_ROOT"/modules/build-systems/*/; do
  [[ -d "$d" && -f "$d/conventions.md" ]] && DISCOVERED_BUILD_SYSTEMS+=("$(basename "$d")")
done

# CI/CD platforms: .md files under modules/ci-cd/
DISCOVERED_CI_PLATFORMS=()
for f in "$PLUGIN_ROOT"/modules/ci-cd/*.md; do
  [[ -f "$f" ]] && DISCOVERED_CI_PLATFORMS+=("$(basename "$f" .md)")
done

# Container orchestration: .md files under modules/container-orchestration/
DISCOVERED_CONTAINER_ORCH=()
for f in "$PLUGIN_ROOT"/modules/container-orchestration/*.md; do
  [[ -f "$f" ]] && DISCOVERED_CONTAINER_ORCH+=("$(basename "$f" .md)")
done

# Crosscutting layers: directories under modules/ excluding known non-layer directories
DISCOVERED_LAYERS=()
for d in "$PLUGIN_ROOT"/modules/*/; do
  [[ -d "$d" ]] || continue
  local_name="$(basename "$d")"
  # Exclude non-layer module categories
  case "$local_name" in
    frameworks|languages|testing|build-systems|ci-cd|container-orchestration) continue ;;
    *) DISCOVERED_LAYERS+=("$local_name") ;;
  esac
done

# Required files per framework directory
REQUIRED_FRAMEWORK_FILES=(conventions.md local-template.md forge-config-template.md rules-override.json known-deprecations.json)

# Skills: directories under skills/ containing SKILL.md
DISCOVERED_SKILLS=()
for d in "$PLUGIN_ROOT"/skills/*/; do
  [[ -d "$d" && -f "$d/SKILL.md" ]] && DISCOVERED_SKILLS+=("$(basename "$d")")
done

# ---------------------------------------------------------------------------
# Minimum count guards (update these when intentionally adding/removing modules)
# ---------------------------------------------------------------------------
MIN_AGENTS=48
MIN_FRAMEWORKS=24
MIN_SKILLS=29

# Canonical post-Phase-05 skill names. Tasks are written to ensure the skills
# directory contains exactly this set. `DISCOVERED_SKILLS` is compared to
# `EXPECTED_SKILL_NAMES` by `tests/structural/skill-consolidation.bats`.
EXPECTED_SKILL_NAMES=(
  forge-abort
  forge-ask
  forge-automation
  forge-bootstrap
  forge-commit
  forge-compress
  forge-config
  forge-deploy
  forge-docs-generate
  forge-fix
  forge-graph
  forge-handoff
  forge-help
  forge-history
  forge-init
  forge-insights
  forge-migration
  forge-playbook-refine
  forge-playbooks
  forge-profile
  forge-recover
  forge-review
  forge-run
  forge-security-audit
  forge-shape
  forge-sprint
  forge-status
  forge-tour
  forge-verify
)
MIN_LANGUAGES=15
MIN_TESTING_FILES=19
MIN_BUILD_SYSTEMS=9
MIN_CI_PLATFORMS=7
MIN_CONTAINER_ORCH=11
MIN_LAYERS=12

# Cross-cutting module file counts per directory (accidental-deletion guards)
MIN_AUTH_MODULES=10
MIN_OBSERVABILITY_MODULES=10
MIN_MESSAGING_MODULES=5
MIN_CACHING_MODULES=3
MIN_SEARCH_MODULES=2
MIN_STORAGE_MODULES=3
MIN_DATABASES_MODULES=5
MIN_PERSISTENCE_MODULES=3
MIN_MIGRATIONS_MODULES=3
MIN_API_PROTOCOLS_MODULES=3

DISCOVERED_DOC_BINDINGS=()
for d in "$PLUGIN_ROOT"/modules/frameworks/*/documentation/; do
  [[ -d "$d" ]] && DISCOVERED_DOC_BINDINGS+=("$(basename "$(dirname "$d")")")
done

MIN_DOCUMENTATION_BINDINGS=21

# ---------------------------------------------------------------------------
# Test file count guards (update when adding new test files)
# ---------------------------------------------------------------------------
MIN_UNIT_TESTS=108        # Current: 132 files (added 4 phase-08 structural tests)
MIN_CONTRACT_TESTS=83     # Current: 85 files
MIN_SCENARIO_TESTS=40     # Current: 41 files

# guard_min_count <label> <actual> <minimum>
# Returns 0 if actual >= minimum, 1 otherwise. Prints message on failure.
guard_min_count() {
  local label="$1" actual="$2" minimum="$3"
  if (( actual < minimum )); then
    echo "GUARD FAIL: Expected >= $minimum $label, found $actual (possible accidental deletion)" >&2
    return 1
  fi
  return 0
}
