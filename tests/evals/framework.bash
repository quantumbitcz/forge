#!/usr/bin/env bash
# Shared eval harness for agent evaluation suite.
# Loaded by every eval.bats file via: load '../../evals/framework'
# Provides validation functions for input/expected pairs and convention coverage.

# ---------------------------------------------------------------------------
# PLUGIN_ROOT: resolve from tests/evals/ -> plugin root (two levels up)
# ---------------------------------------------------------------------------
EVAL_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ---------------------------------------------------------------------------
# Supported languages (from modules/languages/)
# ---------------------------------------------------------------------------
SUPPORTED_LANGUAGES=(
  kotlin java typescript python go rust swift c csharp ruby php dart elixir scala cpp
)

# ---------------------------------------------------------------------------
# validate_input_file <path>
# Validates that an input .md file conforms to the eval input format.
# Returns 0 if valid, 1 with error message if not.
# ---------------------------------------------------------------------------
validate_input_file() {
  local path="${1:?validate_input_file requires a path}"

  if [[ ! -f "$path" ]]; then
    echo "File not found: $path"
    return 1
  fi

  # Must have '# Eval:' title line
  if ! grep -q '^# Eval:' "$path"; then
    echo "Missing '# Eval:' title line in $(basename "$path")"
    return 1
  fi

  # Must have '## Language:' line with a supported language
  local lang_line
  lang_line="$(grep '^## Language:' "$path" | head -1)"
  if [[ -z "$lang_line" ]]; then
    echo "Missing '## Language:' line in $(basename "$path")"
    return 1
  fi

  local lang
  lang="$(echo "$lang_line" | sed 's/^## Language:[[:space:]]*//' | tr -d '[:space:]')"
  local found=0
  for supported in "${SUPPORTED_LANGUAGES[@]}"; do
    if [[ "$lang" == "$supported" ]]; then
      found=1
      break
    fi
  done
  # Also accept special pseudo-languages for non-code files
  if [[ "$lang" == "json" || "$lang" == "yaml" || "$lang" == "markdown" || "$lang" == "dockerfile" ]]; then
    found=1
  fi
  if [[ "$found" -eq 0 ]]; then
    echo "Unsupported language '$lang' in $(basename "$path")"
    return 1
  fi

  # Must have '## Code Under Review' section
  if ! grep -q '^## Code Under Review' "$path"; then
    echo "Missing '## Code Under Review' section in $(basename "$path")"
    return 1
  fi

  # Must have a fenced code block (triple backtick)
  if ! grep -q '```' "$path"; then
    echo "Missing fenced code block in $(basename "$path")"
    return 1
  fi

  # Must have '## Expected Behavior' section
  if ! grep -q '^## Expected Behavior' "$path"; then
    echo "Missing '## Expected Behavior' section in $(basename "$path")"
    return 1
  fi

  return 0
}

# ---------------------------------------------------------------------------
# validate_expected_file <path>
# Validates that an expected .expected file has valid pattern syntax.
# Returns 0 if valid, 1 with error message if not.
# ---------------------------------------------------------------------------
validate_expected_file() {
  local path="${1:?validate_expected_file requires a path}"

  if [[ ! -f "$path" ]]; then
    echo "File not found: $path"
    return 1
  fi

  local line_num=0
  local has_min="" has_max=""
  local min_val=0 max_val=0

  while IFS= read -r line; do
    line_num=$((line_num + 1))

    # Skip blank lines and comments
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    # Every non-comment, non-blank line must start with a known directive
    if ! echo "$line" | grep -qE '^(PATTERN:|NOT:|MIN_FINDINGS:|MAX_FINDINGS:|HAS_CATEGORY:|NOT_CATEGORY:|VERDICT:)'; then
      echo "Line $line_num: unknown directive in $(basename "$path"): $line"
      return 1
    fi

    # PATTERN: lines must contain at least one | delimiter
    if echo "$line" | grep -qE '^PATTERN:'; then
      local pattern_val
      pattern_val="$(echo "$line" | sed 's/^PATTERN:[[:space:]]*//')"
      if ! echo "$pattern_val" | grep -q '|'; then
        echo "Line $line_num: PATTERN must contain at least one '|' delimiter in $(basename "$path")"
        return 1
      fi
    fi

    # MIN_FINDINGS: must be non-negative integer
    if echo "$line" | grep -qE '^MIN_FINDINGS:'; then
      min_val="$(echo "$line" | sed 's/^MIN_FINDINGS:[[:space:]]*//' | tr -d '[:space:]')"
      if ! echo "$min_val" | grep -qE '^[0-9]+$'; then
        echo "Line $line_num: MIN_FINDINGS must be a non-negative integer in $(basename "$path")"
        return 1
      fi
      has_min="true"
    fi

    # MAX_FINDINGS: must be non-negative integer
    if echo "$line" | grep -qE '^MAX_FINDINGS:'; then
      max_val="$(echo "$line" | sed 's/^MAX_FINDINGS:[[:space:]]*//' | tr -d '[:space:]')"
      if ! echo "$max_val" | grep -qE '^[0-9]+$'; then
        echo "Line $line_num: MAX_FINDINGS must be a non-negative integer in $(basename "$path")"
        return 1
      fi
      has_max="true"
    fi

    # HAS_CATEGORY: / NOT_CATEGORY: must match category pattern
    if echo "$line" | grep -qE '^(HAS_CATEGORY|NOT_CATEGORY):'; then
      local cat_val
      cat_val="$(echo "$line" | sed 's/^[A-Z_]*:[[:space:]]*//' | tr -d '[:space:]')"
      if ! echo "$cat_val" | grep -qE '^[A-Z]+-[A-Z0-9_-]+$'; then
        echo "Line $line_num: category code must match [A-Z]+-[A-Z0-9_-]+ pattern in $(basename "$path"): $cat_val"
        return 1
      fi
    fi

    # VERDICT: must be PASS, CONCERNS, or FAIL (pipe-separated alternatives OK)
    if echo "$line" | grep -qE '^VERDICT:'; then
      local verdict_val
      verdict_val="$(echo "$line" | sed 's/^VERDICT:[[:space:]]*//' | tr -d '[:space:]')"
      # Split on pipe and validate each
      local IFS='|'
      local valid=1
      for v in $verdict_val; do
        if [[ "$v" != "PASS" && "$v" != "CONCERNS" && "$v" != "FAIL" ]]; then
          valid=0
        fi
      done
      if [[ "$valid" -eq 0 ]]; then
        echo "Line $line_num: VERDICT must be PASS, CONCERNS, or FAIL in $(basename "$path"): $verdict_val"
        return 1
      fi
    fi
  done < "$path"

  # If both MIN and MAX present, MIN <= MAX
  if [[ -n "$has_min" && -n "$has_max" ]]; then
    if (( min_val > max_val )); then
      echo "Inconsistent: MIN_FINDINGS=$min_val > MAX_FINDINGS=$max_val in $(basename "$path")"
      return 1
    fi
  fi

  return 0
}

# ---------------------------------------------------------------------------
# check_convention_coverage <agent_eval_dir> <input_file>
# Verifies that the agent's convention files contain rules relevant
# to the tested pattern.
# ---------------------------------------------------------------------------
check_convention_coverage() {
  local agent_dir="${1:?check_convention_coverage requires agent_eval_dir}"
  local input_file="${2:?check_convention_coverage requires input_file}"

  local basename_input
  basename_input="$(basename "$input_file" .md)"

  # Find matching expected file
  local expected_file="$agent_dir/expected/${basename_input}.expected"
  if [[ ! -f "$expected_file" ]]; then
    echo "No matching expected file for $basename_input"
    return 1
  fi

  # Extract HAS_CATEGORY lines from expected file
  local categories=()
  while IFS= read -r line; do
    local cat
    cat="$(echo "$line" | sed 's/^HAS_CATEGORY:[[:space:]]*//' | tr -d '[:space:]')"
    categories+=("$cat")
  done < <(grep '^HAS_CATEGORY:' "$expected_file")

  # If no HAS_CATEGORY (e.g., clean-code / PASS scenarios), skip coverage check
  if [[ ${#categories[@]} -eq 0 ]]; then
    return 0
  fi

  # Extract the category prefix (e.g., SEC from SEC-INJECTION, QUAL from QUAL-DEFENSIVE)
  # Search in: category-registry.json, modules/, agent .md files
  local found_any=0
  for cat in "${categories[@]}"; do
    local prefix
    prefix="$(echo "$cat" | sed 's/-.*$//')"

    # Check category-registry.json for the category or its prefix
    if grep -q "\"$cat\"" "$EVAL_PLUGIN_ROOT/shared/checks/category-registry.json" 2>/dev/null; then
      found_any=1
      continue
    fi
    if grep -q "\"$prefix\"" "$EVAL_PLUGIN_ROOT/shared/checks/category-registry.json" 2>/dev/null; then
      found_any=1
      continue
    fi

    # Check modules/ for the category code
    if grep -rq "$cat" "$EVAL_PLUGIN_ROOT/modules/" 2>/dev/null; then
      found_any=1
      continue
    fi

    # Check the agent's own .md file
    local agent_name
    agent_name="$(basename "$agent_dir")"
    if grep -q "$cat\|$prefix" "$EVAL_PLUGIN_ROOT/agents/${agent_name}.md" 2>/dev/null; then
      found_any=1
      continue
    fi
  done

  if [[ "$found_any" -eq 0 ]]; then
    echo "No convention coverage found for categories: ${categories[*]}"
    return 1
  fi

  return 0
}

# ---------------------------------------------------------------------------
# count_input_expected_pairs <agent_eval_dir>
# Counts matched input/expected pairs. Fails if any input has no matching
# expected file, or vice versa.
# ---------------------------------------------------------------------------
count_input_expected_pairs() {
  local agent_dir="${1:?count_input_expected_pairs requires agent_eval_dir}"

  local input_dir="$agent_dir/inputs"
  local expected_dir="$agent_dir/expected"

  if [[ ! -d "$input_dir" ]]; then
    echo "Missing inputs/ directory in $(basename "$agent_dir")"
    return 1
  fi
  if [[ ! -d "$expected_dir" ]]; then
    echo "Missing expected/ directory in $(basename "$agent_dir")"
    return 1
  fi

  # Check every input has a matching expected
  for input in "$input_dir"/*.md; do
    [[ -f "$input" ]] || continue
    local base
    base="$(basename "$input" .md)"
    if [[ ! -f "$expected_dir/${base}.expected" ]]; then
      echo "Input '$base.md' has no matching expected file"
      return 1
    fi
  done

  # Check every expected has a matching input
  for expected in "$expected_dir"/*.expected; do
    [[ -f "$expected" ]] || continue
    local base
    base="$(basename "$expected" .expected)"
    if [[ ! -f "$input_dir/${base}.md" ]]; then
      echo "Expected '$base.expected' has no matching input file"
      return 1
    fi
  done

  return 0
}
