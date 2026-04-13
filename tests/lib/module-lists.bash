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

# Build systems: .md files under modules/build-systems/
DISCOVERED_BUILD_SYSTEMS=()
for f in "$PLUGIN_ROOT"/modules/build-systems/*.md; do
  [[ -f "$f" ]] && DISCOVERED_BUILD_SYSTEMS+=("$(basename "$f" .md)")
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

# ---------------------------------------------------------------------------
# Minimum count guards (update these when intentionally adding/removing modules)
# ---------------------------------------------------------------------------
MIN_FRAMEWORKS=21
MIN_LANGUAGES=15
MIN_TESTING_FILES=19
MIN_BUILD_SYSTEMS=7
MIN_CI_PLATFORMS=7
MIN_CONTAINER_ORCH=11
MIN_LAYERS=12

DISCOVERED_DOC_BINDINGS=()
for d in "$PLUGIN_ROOT"/modules/frameworks/*/documentation/; do
  [[ -d "$d" ]] && DISCOVERED_DOC_BINDINGS+=("$(basename "$(dirname "$d")")")
done

MIN_DOCUMENTATION_BINDINGS=21

# ---------------------------------------------------------------------------
# Test file count guards (update when adding new test files)
# ---------------------------------------------------------------------------
MIN_UNIT_TESTS=55         # Current: 55 files (54 existing + 1 new discovery-detection.bats)
MIN_CONTRACT_TESTS=78     # Current: 78 files
MIN_SCENARIO_TESTS=29     # Current: 29 files

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
