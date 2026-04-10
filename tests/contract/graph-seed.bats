#!/usr/bin/env bats
# Contract tests: graph seed.cypher correctness and freshness.

load '../helpers/test-helpers'

SEED_FILE="$PLUGIN_ROOT/shared/graph/seed.cypher"
GENERATOR="$PLUGIN_ROOT/shared/graph/generate-seed.sh"

LAYERS=(databases persistence migrations api-protocols messaging caching search storage auth observability build-systems ci-cd container-orchestration documentation code-quality)

# ---------------------------------------------------------------------------
# 1. seed-freshness: dry-run output must match committed seed.cypher
# ---------------------------------------------------------------------------
@test "graph-seed: seed.cypher is fresh (matches generate-seed.sh --dry-run)" {
  [[ -f "$SEED_FILE" ]]    || fail "seed.cypher not found: $SEED_FILE"
  [[ -x "$GENERATOR" ]]   || fail "generate-seed.sh not executable: $GENERATOR"

  local committed_hash generated_hash
  committed_hash="$(shasum -a 256 "$SEED_FILE" | awk '{print $1}')"
  generated_hash="$("$GENERATOR" --dry-run | shasum -a 256 | awk '{print $1}')"

  if [[ "$committed_hash" != "$generated_hash" ]]; then
    fail "seed.cypher is stale. Run shared/graph/generate-seed.sh to regenerate. committed=$committed_hash generated=$generated_hash"
  fi
}

# ---------------------------------------------------------------------------
# 2. node-coverage-languages: every modules/languages/*.md has a CREATE line
# ---------------------------------------------------------------------------
@test "graph-seed: every language file has a CREATE (:Language ...) node" {
  local missing=()
  for f in "$PLUGIN_ROOT"/modules/languages/*.md; do
    [[ -f "$f" ]] || continue
    local name
    name="$(basename "$f" .md)"
    if ! grep -qF "CREATE (:Language {name: '${name}'" "$SEED_FILE"; then
      missing+=("$name")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Languages missing from seed.cypher: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 3. node-coverage-frameworks: every modules/frameworks/*/ dir has a CREATE line
# ---------------------------------------------------------------------------
@test "graph-seed: every framework directory has a CREATE (:Framework ...) node" {
  local missing=()
  for d in "$PLUGIN_ROOT"/modules/frameworks/*/; do
    [[ -d "$d" ]] || continue
    local name
    name="$(basename "$d")"
    if ! grep -qF "CREATE (:Framework {name: '${name}'" "$SEED_FILE"; then
      missing+=("$name")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Frameworks missing from seed.cypher: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 4. node-coverage-testing: every modules/testing/*.md has a CREATE line
# ---------------------------------------------------------------------------
@test "graph-seed: every testing file has a CREATE (:TestingFramework ...) node" {
  local missing=()
  for f in "$PLUGIN_ROOT"/modules/testing/*.md; do
    [[ -f "$f" ]] || continue
    local name
    name="$(basename "$f" .md)"
    if ! grep -qF "CREATE (:TestingFramework {name: '${name}'" "$SEED_FILE"; then
      missing+=("$name")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Testing frameworks missing from seed.cypher: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 5. node-coverage-layers: every module in crosscutting layer dirs has a CREATE line
# ---------------------------------------------------------------------------
@test "graph-seed: every crosscutting layer module has a CREATE (:LayerModule ...) node" {
  local missing=()
  for layer in "${LAYERS[@]}"; do
    local layer_dir="$PLUGIN_ROOT/modules/$layer"
    [[ -d "$layer_dir" ]] || continue
    for f in "$layer_dir"/*.md; do
      [[ -f "$f" ]] || continue
      local name
      name="$(basename "$f" .md)"
      if ! grep -qF "CREATE (:LayerModule {name: '${name}'" "$SEED_FILE"; then
        missing+=("$layer/$name")
      fi
    done
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Layer modules missing from seed.cypher: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 6. agent-coverage: every agents/*.md has a CREATE (:Agent ...) node
# ---------------------------------------------------------------------------
@test "graph-seed: every agent file has a CREATE (:Agent ...) node" {
  local missing=()
  for f in "$PLUGIN_ROOT"/agents/*.md; do
    [[ -f "$f" ]] || continue
    local name
    name="$(basename "$f" .md)"
    # Orchestrator phase files are includes, not standalone agents
    [[ "$name" == fg-100-orchestrator ]] && continue
    [[ "$name" == fg-100-orchestrator ]] && continue
    [[ "$name" == fg-100-orchestrator ]] && continue
    if ! grep -qF "CREATE (:Agent" "$SEED_FILE" || ! grep -qF "name: '${name}'" <(grep "CREATE (:Agent" "$SEED_FILE"); then
      missing+=("$name")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Agents missing from seed.cypher: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 7. learnings-coverage: every shared/learnings/*.md has a CREATE line
# ---------------------------------------------------------------------------
@test "graph-seed: every learnings file has a CREATE (:Learnings ...) node" {
  local missing=()
  for f in "$PLUGIN_ROOT"/shared/learnings/*.md; do
    [[ -f "$f" ]] || continue
    local name
    name="$(basename "$f" .md)"
    if ! grep -qF "CREATE (:Learnings {name: '${name}'" "$SEED_FILE"; then
      missing+=("$name")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Learnings files missing from seed.cypher: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 8. edge-integrity-extends: every EXTENDS edge references existing nodes
# ---------------------------------------------------------------------------
@test "graph-seed: every EXTENDS edge has matching source FrameworkBinding and target LayerModule nodes" {
  local failures=()
  while IFS= read -r line; do
    # Extract binding name: FrameworkBinding {name: '...'}
    local binding_name
    binding_name="$(printf '%s' "$line" | sed "s/.*FrameworkBinding {name: '\([^']*\)'.*/\1/")"
    # Extract layer module name: LayerModule {name: '...'}
    local module_name
    module_name="$(printf '%s' "$line" | sed "s/.*LayerModule {name: '\([^']*\)'.*/\1/")"

    if [[ -z "$binding_name" || -z "$module_name" ]]; then
      failures+=("Could not parse: $line")
      continue
    fi

    if ! grep -qF "CREATE (:FrameworkBinding {name: '${binding_name}'" "$SEED_FILE"; then
      failures+=("EXTENDS source missing FrameworkBinding node: '${binding_name}'")
    fi
    if ! grep -qF "CREATE (:LayerModule {name: '${module_name}'" "$SEED_FILE"; then
      failures+=("EXTENDS target missing LayerModule node: '${module_name}'")
    fi
  done < <(grep "\-\[:EXTENDS\]->" "$SEED_FILE")

  if (( ${#failures[@]} > 0 )); then
    fail "EXTENDS edge integrity failures:$(printf '\n  %s' "${failures[@]}")"
  fi
}
