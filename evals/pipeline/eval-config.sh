#!/usr/bin/env bash
# Shared configuration for the forge eval framework.
# Sourced by eval-runner.sh and eval-report.sh. Not executed directly.
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
EVAL_DEFAULT_SUITE="lite"
EVAL_DEFAULT_TIMEOUT=30          # minutes per task (range: 5-120)
EVAL_DEFAULT_PARALLEL=1          # concurrent tasks (range: 1-5)
EVAL_DEFAULT_VALIDATION_TIMEOUT=60  # seconds (range: 5-300)
EVAL_DEFAULT_REGRESSION_THRESHOLD=20 # percent (range: 5-50)
EVAL_KEEP_WORKDIRS=false
EVAL_VALID_SUITES=("lite" "convergence" "cost" "compression" "smoke")
EVAL_VALID_LANGUAGES=("python" "typescript" "kotlin" "go" "rust")
EVAL_VALID_DIFFICULTIES=("easy" "medium" "hard")

# ---------------------------------------------------------------------------
# Validation ranges: key -> "min max"
# ---------------------------------------------------------------------------
declare -A EVAL_RANGES=(
  ["timeout_per_task_minutes"]="5 120"
  ["parallel_tasks"]="1 5"
  ["validation_timeout_seconds"]="5 300"
  ["regression_threshold_percent"]="5 50"
)

# ---------------------------------------------------------------------------
# eval_validate_config <key> <value>
# Validates a single config key/value pair against known ranges.
# Returns 0 on valid, 1 on invalid (prints error to stderr).
# ---------------------------------------------------------------------------
eval_validate_config() {
  local key="${1:?key required}"
  local value="${2:?value required}"

  if [[ -v "EVAL_RANGES[$key]" ]]; then
    local range="${EVAL_RANGES[$key]}"
    local min max
    min="${range%% *}"
    max="${range##* }"
    if (( value < min || value > max )); then
      echo "ERROR: ${key}=${value} out of range [${min}, ${max}]" >&2
      return 1
    fi
    return 0
  fi

  # Unknown keys pass validation (forward-compatible)
  return 0
}

# ---------------------------------------------------------------------------
# eval_get_forge_version
# Reads forge plugin version from plugin.json.
# ---------------------------------------------------------------------------
eval_get_forge_version() {
  local plugin_json="${EVAL_PLUGIN_ROOT:-${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}}/plugin.json"
  if [[ -f "$plugin_json" ]] && command -v "${FORGE_PYTHON:-python3}" &>/dev/null; then
    "${FORGE_PYTHON:-python3}" -c "import json; print(json.load(open('${plugin_json}'))['version'])" 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

# ---------------------------------------------------------------------------
# eval_get_environment
# Captures runtime environment info as JSON.
# ---------------------------------------------------------------------------
eval_get_environment() {
  local forge_version
  forge_version="$(eval_get_forge_version)"
  local platform
  platform="$(uname -s | tr '[:upper:]' '[:lower:]')"
  local bash_ver="${BASH_VERSION:-unknown}"
  local python_ver
  python_ver="$("${FORGE_PYTHON:-python3}" --version 2>/dev/null | awk '{print $2}' || echo 'unknown')"

  printf '{"forge_version":"%s","platform":"%s","bash_version":"%s","python_version":"%s"}' \
    "$forge_version" "$platform" "$bash_ver" "$python_ver"
}

# ---------------------------------------------------------------------------
# eval_load_config <config_file>
# Parses eval: section from forge-config.md and validates ranges.
# Returns 0 on success, 1 on validation failure.
# ---------------------------------------------------------------------------
eval_load_config() {
  local config_file="${1:?config file required}"
  if [[ ! -f "$config_file" ]]; then
    echo "ERROR: Config file not found: $config_file" >&2
    return 1
  fi

  if ! command -v "${FORGE_PYTHON:-python3}" &>/dev/null; then
    echo "WARNING: python3 not available, skipping config load" >&2
    return 0
  fi

  local config_json
  config_json="$("${FORGE_PYTHON:-python3}" -c "
import re, sys, json
content = open('${config_file}', 'r').read()
# Extract YAML from fenced code blocks
yaml_blocks = re.findall(r'\`\`\`ya?ml\n(.*?)\`\`\`', content, re.DOTALL)
if not yaml_blocks:
    print('{}')
    sys.exit(0)

yaml_text = '\n'.join(yaml_blocks)
# Simple key-value extraction for eval section
in_eval = False
result = {}
for line in yaml_text.split('\n'):
    stripped = line.strip()
    if stripped == 'eval:':
        in_eval = True
        continue
    if in_eval:
        if stripped and not stripped.startswith('#') and not stripped.startswith('-'):
            if ':' in stripped and not stripped[0].isspace() and line[0] != ' ':
                in_eval = False
                continue
            parts = stripped.split(':', 1)
            if len(parts) == 2:
                key = parts[0].strip()
                val = parts[1].strip()
                try:
                    val = int(val)
                except ValueError:
                    try:
                        val = float(val)
                    except ValueError:
                        if val.lower() in ('true', 'false'):
                            val = val.lower() == 'true'
                result[key] = val
print(json.dumps(result))
" 2>/dev/null)" || {
    echo "WARNING: Failed to parse config, using defaults" >&2
    return 0
  }

  # Validate each numeric key against ranges
  local errors=0
  local key value
  for key in $(echo "$config_json" | "${FORGE_PYTHON:-python3}" -c "import json,sys; [print(k) for k in json.load(sys.stdin)]" 2>/dev/null); do
    value="$(echo "$config_json" | "${FORGE_PYTHON:-python3}" -c "import json,sys; print(json.load(sys.stdin).get('$key',''))" 2>/dev/null)"
    if [[ -v "EVAL_RANGES[$key]" ]]; then
      if ! eval_validate_config "$key" "$value"; then
        errors=$((errors + 1))
      fi
    fi
  done

  if (( errors > 0 )); then
    return 1
  fi

  return 0
}
