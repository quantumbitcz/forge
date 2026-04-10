#!/usr/bin/env bats
# Contract tests: cross-framework composition correctness.
# Validates that multi-component setups (e.g., spring+react, fastapi+react)
# have no conflicting rule IDs, compatible deprecation schemas, and
# independent inline_checks.

load '../helpers/test-helpers'

FRAMEWORKS_DIR="$PLUGIN_ROOT/modules/frameworks"

# ---------------------------------------------------------------------------
# Helper: extract rule IDs from a framework's rules-override.json
# ---------------------------------------------------------------------------
_rule_ids() {
  local fw="$1"
  local file="$FRAMEWORKS_DIR/$fw/rules-override.json"
  if [[ -f "$file" ]]; then
    jq -r '.additional_rules[]?.id // empty' "$file" 2>/dev/null | sort
  fi
}

# ---------------------------------------------------------------------------
# 1. spring+react composition: no conflicting rule IDs
# ---------------------------------------------------------------------------
@test "cross-composition: spring+react have no conflicting rule IDs" {
  local spring_rules react_rules conflicts

  spring_rules=$(_rule_ids "spring")
  react_rules=$(_rule_ids "react")

  # Skip if either framework has no rules
  if [[ -z "$spring_rules" ]] && [[ -z "$react_rules" ]]; then
    skip "No rules to compare"
  fi

  conflicts=$(comm -12 <(echo "$spring_rules") <(echo "$react_rules"))
  [ -z "$conflicts" ] || fail "Conflicting rule IDs between spring and react: $conflicts"
}

# ---------------------------------------------------------------------------
# 2. fastapi+react composition: no conflicting rule IDs
# ---------------------------------------------------------------------------
@test "cross-composition: fastapi+react have no conflicting rule IDs" {
  local fastapi_rules react_rules conflicts

  fastapi_rules=$(_rule_ids "fastapi")
  react_rules=$(_rule_ids "react")

  if [[ -z "$fastapi_rules" ]] && [[ -z "$react_rules" ]]; then
    skip "No rules to compare"
  fi

  conflicts=$(comm -12 <(echo "$fastapi_rules") <(echo "$react_rules"))
  [ -z "$conflicts" ] || fail "Conflicting rule IDs between fastapi and react: $conflicts"
}

# ---------------------------------------------------------------------------
# 3. k8s+spring composition: both have inline_checks
# ---------------------------------------------------------------------------
@test "cross-composition: k8s+spring both have inline_checks" {
  local spring_template="$FRAMEWORKS_DIR/spring/local-template.md"
  local k8s_template="$FRAMEWORKS_DIR/k8s/local-template.md"

  [ -f "$spring_template" ] || fail "spring local-template.md not found"
  [ -f "$k8s_template" ] || fail "k8s local-template.md not found"

  grep -q "inline_checks" "$spring_template" || \
    fail "spring local-template.md missing inline_checks"
  grep -q "inline_checks" "$k8s_template" || \
    fail "k8s local-template.md missing inline_checks"
}

# ---------------------------------------------------------------------------
# 4. go-stdlib+react composition: deprecation schemas are v2 compatible
# ---------------------------------------------------------------------------
@test "cross-composition: go-stdlib+react deprecations use v2 schema" {
  local go_deps="$FRAMEWORKS_DIR/go-stdlib/known-deprecations.json"
  local react_deps="$FRAMEWORKS_DIR/react/known-deprecations.json"

  [ -f "$go_deps" ] || fail "go-stdlib known-deprecations.json not found"
  [ -f "$react_deps" ] || fail "react known-deprecations.json not found"

  # Both must parse as valid JSON
  jq empty "$go_deps" || fail "go-stdlib known-deprecations.json is invalid JSON"
  jq empty "$react_deps" || fail "react known-deprecations.json is invalid JSON"

  # Both must have v2 schema fields (pattern, replacement, package) on first entry
  # Schema wraps entries in .deprecations[] (v2 format with top-level "version" key)
  jq -e '.deprecations[0] | has("pattern", "replacement", "package")' "$go_deps" >/dev/null || \
    fail "go-stdlib known-deprecations.json missing v2 fields (pattern, replacement, package)"
  jq -e '.deprecations[0] | has("pattern", "replacement", "package")' "$react_deps" >/dev/null || \
    fail "react known-deprecations.json missing v2 fields (pattern, replacement, package)"
}

# ---------------------------------------------------------------------------
# 5. All 21 frameworks: no duplicate rule IDs within any single framework
# ---------------------------------------------------------------------------
@test "cross-composition: no duplicate rule IDs within any framework" {
  local had_dupes=false

  for override in "$FRAMEWORKS_DIR"/*/rules-override.json; do
    [ -f "$override" ] || continue
    local fw
    fw=$(basename "$(dirname "$override")")

    local ids dupes
    ids=$(jq -r '.additional_rules[]?.id // empty' "$override" 2>/dev/null | sort)
    dupes=$(echo "$ids" | uniq -d)

    if [[ -n "$dupes" ]]; then
      echo "Framework $fw has duplicate rule IDs: $dupes" >&2
      had_dupes=true
    fi
  done

  [[ "$had_dupes" == "false" ]] || fail "One or more frameworks have duplicate rule IDs (see above)"
}
