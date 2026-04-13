#!/usr/bin/env bash
# Centralized config validator for forge-config.md and forge.local.md.
# Validates YAML frontmatter against documented constraints from
# scoring.md, convergence-engine.md, CLAUDE.md, and JSON schemas.
#
# Usage:
#   ./shared/config-validator.sh [OPTIONS] <project-root>
#
# Options:
#   --verbose         Show OK results in addition to errors/warnings
#   --json            Output JSON report instead of human-readable
#   --check-commands  Also verify configured commands are executable
#
# Exit codes:
#   0 — all validations passed
#   1 — one or more errors (CRITICAL or ERROR severity)
#   2 — warnings only (no errors)
#   3 — input error (files not found, invalid args)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source platform helpers
# shellcheck source=platform.sh
source "${SCRIPT_DIR}/platform.sh"

# ── Globals ─────────────────────────────────────────────────────────────────

VERBOSE=false
JSON_OUTPUT=false
CHECK_COMMANDS=false
PROJECT_ROOT=""

# Counters
CRITICAL_COUNT=0
ERROR_COUNT=0
WARNING_COUNT=0
OK_COUNT=0

# Results accumulator (newline-separated records: SEV|FILE|FIELD|MESSAGE)
RESULTS=""

# ── Argument parsing ────────────────────────────────────────────────────────

usage() {
  echo "Usage: config-validator.sh [--verbose] [--json] [--check-commands] <project-root>"
  echo ""
  echo "Validates .claude/forge-config.md and .claude/forge.local.md"
  echo ""
  echo "Exit codes:"
  echo "  0 — all validations passed"
  echo "  1 — one or more errors (CRITICAL or ERROR severity)"
  echo "  2 — warnings only (no errors)"
  echo "  3 — input error (files not found, invalid args)"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose)  VERBOSE=true; shift ;;
    --json)     JSON_OUTPUT=true; shift ;;
    --check-commands) CHECK_COMMANDS=true; shift ;;
    --help|-h)  usage; exit 0 ;;
    -*)         echo "ERROR: Unknown option: $1" >&2; usage >&2; exit 3 ;;
    *)          PROJECT_ROOT="$1"; shift ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  echo "ERROR: project-root argument is required" >&2
  usage >&2
  exit 3
fi

CLAUDE_DIR="${PROJECT_ROOT}/.claude"
CONFIG_FILE="${CLAUDE_DIR}/forge-config.md"
LOCAL_FILE="${CLAUDE_DIR}/forge.local.md"

# ── Result recording ────────────────────────────────────────────────────────

add_result() {
  local severity="$1" file="$2" field="$3" message="$4"
  case "$severity" in
    CRITICAL) CRITICAL_COUNT=$((CRITICAL_COUNT + 1)) ;;
    ERROR)    ERROR_COUNT=$((ERROR_COUNT + 1)) ;;
    WARNING)  WARNING_COUNT=$((WARNING_COUNT + 1)) ;;
    OK)       OK_COUNT=$((OK_COUNT + 1)) ;;
  esac
  RESULTS="${RESULTS}${severity}|${file}|${field}|${message}"$'\n'
}

# ── YAML extraction from markdown ──────────────────────────────────────────
# Extracts YAML content from markdown code fences (```yaml...```) or
# frontmatter (---...---). Returns the YAML text on stdout.

extract_yaml() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return 1
  fi
  # Try frontmatter first (--- delimited), then code fences
  "$FORGE_PYTHON" -c "
import sys, re

content = open(sys.argv[1]).read()

# Strategy 1: YAML frontmatter between --- delimiters
fm = re.match(r'^---\s*\n(.*?)\n---', content, re.DOTALL)
if fm:
    print(fm.group(1))
    sys.exit(0)

# Strategy 2: First yaml code fence
fence = re.search(r'\`\`\`ya?ml\s*\n(.*?)\n\`\`\`', content, re.DOTALL)
if fence:
    print(fence.group(1))
    sys.exit(0)

# Strategy 3: All yaml code fences combined
fences = re.findall(r'\`\`\`ya?ml\s*\n(.*?)\n\`\`\`', content, re.DOTALL)
if fences:
    print('\n'.join(fences))
    sys.exit(0)

sys.exit(1)
" "$file" 2>/dev/null
}

# ── Inline YAML-to-JSON parser (no PyYAML dependency) ──────────────────────
# Handles the subset of YAML used in forge configs: key-value pairs,
# nested objects (2-space indent), lists (- items), comments, booleans,
# integers, floats, nulls, and quoted strings.

yaml_to_json() {
  local _py_script
  _py_script=$(pipeline_mktemp)
  cat > "$_py_script" << 'PYEOF'
import sys, re, json

def parse_yaml_subset(text):
    result = {}
    stack = [(result, -1)]
    current_list_key = None
    current_list = None
    current_list_indent = -1

    for line in text.split("\n"):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        indent = len(line) - len(line.lstrip())

        list_match = re.match(r"^(\s*)- (.+)$", line)
        if list_match:
            item_indent = len(list_match.group(1))
            item_val = parse_value(list_match.group(2).strip())
            if current_list is not None and item_indent >= current_list_indent:
                current_list.append(item_val)
                continue

        kv_match = re.match(r"^(\s*)([a-zA-Z_][a-zA-Z0-9_.-]*)\s*:\s*(.*?)$", line)
        if not kv_match:
            continue

        key = kv_match.group(2)
        raw_val = kv_match.group(3).strip()

        while len(stack) > 1 and stack[-1][1] >= indent:
            stack.pop()

        parent = stack[-1][0]

        if raw_val and not raw_val.startswith(('"', "'", "[")):
            comment_pos = raw_val.find(" #")
            if comment_pos > 0:
                raw_val = raw_val[:comment_pos].strip()

        if raw_val == "" or raw_val is None:
            new_dict = {}
            parent[key] = new_dict
            stack.append((new_dict, indent))
            current_list = None
            current_list_key = None
        elif raw_val == "[]":
            parent[key] = []
            current_list = parent[key]
            current_list_key = key
            current_list_indent = indent + 2
        else:
            val = parse_value(raw_val)
            parent[key] = val
            current_list = None
            current_list_key = None

            if isinstance(val, list):
                current_list = val
                current_list_key = key
                current_list_indent = indent + 2

    return result

def parse_value(s):
    if not s:
        return None
    s = s.strip()
    if (s.startswith('"') and s.endswith('"')) or (s.startswith("'") and s.endswith("'")):
        return s[1:-1]
    if s.lower() in ("true", "yes", "on"):
        return True
    if s.lower() in ("false", "no", "off"):
        return False
    if s.lower() in ("null", "~", ""):
        return None
    try:
        return int(s)
    except ValueError:
        pass
    try:
        return float(s)
    except ValueError:
        pass
    if s.startswith("[") and s.endswith("]"):
        items = s[1:-1].split(",")
        return [parse_value(i.strip()) for i in items if i.strip()]
    return s

yaml_text = sys.stdin.read()
try:
    data = parse_yaml_subset(yaml_text)
    json.dump(data, sys.stdout, indent=2)
except Exception as e:
    print(json.dumps({"_parse_error": str(e)}), file=sys.stdout)
    sys.exit(1)
PYEOF
  "$FORGE_PYTHON" "$_py_script"
  local rc=$?
  rm -f "$_py_script"
  return $rc
}

# ── JSON field access helper ────────────────────────────────────────────────
# Reads a dotted field path from a JSON string.
# Usage: value=$(json_get "$json" "scoring.pass_threshold")

json_get() {
  local json="$1" path="$2"
  "$FORGE_PYTHON" -c "
import json, sys
data = json.loads(sys.argv[1])
keys = sys.argv[2].split('.')
val = data
for k in keys:
    if isinstance(val, dict) and k in val:
        val = val[k]
    else:
        val = None
        break
if val is None:
    print('')
else:
    print(json.dumps(val) if isinstance(val, (dict, list)) else str(val))
" "$json" "$path" 2>/dev/null
}

json_has() {
  local json="$1" path="$2"
  "$FORGE_PYTHON" -c "
import json, sys
data = json.loads(sys.argv[1])
keys = sys.argv[2].split('.')
val = data
for k in keys:
    if isinstance(val, dict) and k in val:
        val = val[k]
    else:
        sys.exit(1)
sys.exit(0)
" "$json" "$path" 2>/dev/null
}

json_keys() {
  local json="$1" path="$2"
  "$FORGE_PYTHON" -c "
import json, sys
data = json.loads(sys.argv[1])
if sys.argv[2]:
    keys = sys.argv[2].split('.')
    for k in keys:
        if isinstance(data, dict) and k in data:
            data = data[k]
        else:
            sys.exit(0)
if isinstance(data, dict):
    for k in data:
        print(k)
" "$json" "$path" 2>/dev/null
}

# ── Prerequisite check ─────────────────────────────────────────────────────

if [[ -z "$FORGE_PYTHON" ]]; then
  echo "ERROR: python3 is required for config validation" >&2
  exit 3
fi

# ── Input validation ───────────────────────────────────────────────────────

if [[ ! -d "$CLAUDE_DIR" ]]; then
  echo "ERROR: .claude/ directory not found in ${PROJECT_ROOT}" >&2
  exit 3
fi

if [[ ! -f "$LOCAL_FILE" ]]; then
  echo "ERROR: forge.local.md not found at ${LOCAL_FILE}" >&2
  echo "Run /forge-init to generate configuration." >&2
  exit 3
fi

# ── Parse config files ─────────────────────────────────────────────────────

LOCAL_YAML=""
LOCAL_JSON=""
CONFIG_YAML=""
CONFIG_JSON=""
HAS_CONFIG=false

LOCAL_YAML=$(extract_yaml "$LOCAL_FILE") || {
  add_result "CRITICAL" "forge.local.md" "_parse" "Could not extract YAML from forge.local.md"
}

if [[ -n "$LOCAL_YAML" ]]; then
  LOCAL_JSON=$(echo "$LOCAL_YAML" | yaml_to_json) || {
    add_result "CRITICAL" "forge.local.md" "_parse" "Could not parse YAML in forge.local.md"
    LOCAL_JSON="{}"
  }
  # Check for parse error
  if json_has "$LOCAL_JSON" "_parse_error"; then
    add_result "CRITICAL" "forge.local.md" "_parse" "YAML parse error: $(json_get "$LOCAL_JSON" "_parse_error")"
    LOCAL_JSON="{}"
  fi
else
  LOCAL_JSON="{}"
fi

if [[ -f "$CONFIG_FILE" ]]; then
  HAS_CONFIG=true
  CONFIG_YAML=$(extract_yaml "$CONFIG_FILE") || {
    add_result "WARNING" "forge-config.md" "_parse" "Could not extract YAML from forge-config.md"
  }
  if [[ -n "$CONFIG_YAML" ]]; then
    CONFIG_JSON=$(echo "$CONFIG_YAML" | yaml_to_json) || {
      add_result "WARNING" "forge-config.md" "_parse" "Could not parse YAML in forge-config.md"
      CONFIG_JSON="{}"
    }
    if json_has "$CONFIG_JSON" "_parse_error"; then
      add_result "WARNING" "forge-config.md" "_parse" "YAML parse error: $(json_get "$CONFIG_JSON" "_parse_error")"
      CONFIG_JSON="{}"
    fi
  else
    CONFIG_JSON="{}"
  fi
else
  CONFIG_JSON="{}"
fi

# ── Category A: Required fields (forge.local.md) ──────────────────────────

FRAMEWORK=$(json_get "$LOCAL_JSON" "components.framework")

# components.language
LANG=$(json_get "$LOCAL_JSON" "components.language")
if [[ -z "$LANG" || "$LANG" == "None" || "$LANG" == "null" ]]; then
  if [[ "$FRAMEWORK" != "k8s" ]]; then
    add_result "ERROR" "forge.local.md" "components.language" "Required (unless framework is k8s). Value: empty"
  else
    add_result "OK" "forge.local.md" "components.language" "null (valid for k8s)"
  fi
else
  VALID_LANGS="kotlin java typescript python go rust swift c csharp ruby php dart elixir scala cpp"
  if echo " $VALID_LANGS " | grep -q " $LANG "; then
    add_result "OK" "forge.local.md" "components.language" "Value \"$LANG\" is valid"
  else
    add_result "ERROR" "forge.local.md" "components.language" "Unknown language \"$LANG\". Must be one of: $VALID_LANGS"
  fi
fi

# components.framework
if [[ -z "$FRAMEWORK" || "$FRAMEWORK" == "None" || "$FRAMEWORK" == "null" ]]; then
  add_result "WARNING" "forge.local.md" "components.framework" "No framework specified"
else
  VALID_FRAMEWORKS="spring react fastapi axum swiftui vapor express sveltekit k8s embedded go-stdlib aspnet django nextjs gin jetpack-compose kotlin-multiplatform angular nestjs vue svelte"
  if echo " $VALID_FRAMEWORKS " | grep -q " $FRAMEWORK "; then
    add_result "OK" "forge.local.md" "components.framework" "Value \"$FRAMEWORK\" is valid"
  else
    add_result "ERROR" "forge.local.md" "components.framework" "Unknown framework \"$FRAMEWORK\". Must be one of: $VALID_FRAMEWORKS"
  fi
fi

# components.testing
TESTING=$(json_get "$LOCAL_JSON" "components.testing")
if [[ -z "$TESTING" || "$TESTING" == "None" || "$TESTING" == "null" ]]; then
  if [[ "$FRAMEWORK" != "k8s" ]]; then
    add_result "WARNING" "forge.local.md" "components.testing" "No testing framework specified"
  else
    add_result "OK" "forge.local.md" "components.testing" "null (valid for k8s)"
  fi
else
  VALID_TESTING="kotest junit5 vitest jest pytest go-testing xctest rust-test xunit-nunit testcontainers playwright cypress cucumber k6 detox rspec phpunit exunit scalatest"
  if echo " $VALID_TESTING " | grep -q " $TESTING "; then
    add_result "OK" "forge.local.md" "components.testing" "Value \"$TESTING\" is valid"
  else
    add_result "ERROR" "forge.local.md" "components.testing" "Unknown testing framework \"$TESTING\". Must be one of: $VALID_TESTING"
  fi
fi

# Helper: check if a command value is a valid non-empty string (not {} from empty YAML key)
is_valid_command() {
  local val="$1"
  [[ -n "$val" && "$val" != "{}" && "$val" != "None" && "$val" != "null" ]]
}

# commands.build
BUILD_CMD=$(json_get "$LOCAL_JSON" "commands.build")
if ! is_valid_command "$BUILD_CMD"; then
  add_result "ERROR" "forge.local.md" "commands.build" "Empty value — build command is required"
  BUILD_CMD=""
else
  add_result "OK" "forge.local.md" "commands.build" "Value \"$BUILD_CMD\" is set"
fi

# commands.test
TEST_CMD=$(json_get "$LOCAL_JSON" "commands.test")
if ! is_valid_command "$TEST_CMD"; then
  add_result "ERROR" "forge.local.md" "commands.test" "Empty value — test command is required"
  TEST_CMD=""
else
  add_result "OK" "forge.local.md" "commands.test" "Value \"$TEST_CMD\" is set"
fi

# commands.lint
LINT_CMD=$(json_get "$LOCAL_JSON" "commands.lint")
if ! is_valid_command "$LINT_CMD"; then
  add_result "WARNING" "forge.local.md" "commands.lint" "No lint command specified"
  LINT_CMD=""
else
  add_result "OK" "forge.local.md" "commands.lint" "Value \"$LINT_CMD\" is set"
fi

# ── Category B: Range constraints (forge-config.md) ───────────────────────

validate_range() {
  local file="$1" field="$2" min="$3" max="$4" default="$5" json="$6"
  local val
  val=$(json_get "$json" "$field")

  if [[ -z "$val" ]]; then
    add_result "OK" "$file" "$field" "Not set (default: $default)"
    return
  fi

  # Check it's a number
  if ! [[ "$val" =~ ^-?[0-9]+$ ]]; then
    add_result "ERROR" "$file" "$field" "Value \"$val\" is not an integer"
    return
  fi

  local failed=false
  local msg=""
  if [[ -n "$min" ]] && [[ "$val" -lt "$min" ]]; then
    failed=true
    msg="Value $val is below minimum $min"
  fi
  if [[ -n "$max" ]] && [[ "$val" -gt "$max" ]]; then
    failed=true
    msg="Value $val exceeds maximum $max"
  fi

  if $failed; then
    add_result "ERROR" "$file" "$field" "$msg"
  else
    add_result "OK" "$file" "$field" "Value $val is within range [$min, $max]"
  fi
}

validate_enum() {
  local file="$1" field="$2" allowed="$3" default="$4" json="$5"
  local val
  val=$(json_get "$json" "$field")

  if [[ -z "$val" ]]; then
    add_result "OK" "$file" "$field" "Not set (default: $default)"
    return
  fi

  if echo " $allowed " | grep -q " $val "; then
    add_result "OK" "$file" "$field" "Value \"$val\" is valid"
  else
    add_result "ERROR" "$file" "$field" "Value \"$val\" is not one of: $allowed"
  fi
}

if $HAS_CONFIG; then
  # Scoring
  validate_range "forge-config.md" "scoring.critical_weight" 10 "" 20 "$CONFIG_JSON"
  validate_range "forge-config.md" "scoring.warning_weight" 1 "" 5 "$CONFIG_JSON"
  validate_range "forge-config.md" "scoring.info_weight" 0 "" 2 "$CONFIG_JSON"
  validate_range "forge-config.md" "scoring.pass_threshold" 60 100 80 "$CONFIG_JSON"
  validate_range "forge-config.md" "scoring.concerns_threshold" 40 "" 60 "$CONFIG_JSON"
  validate_range "forge-config.md" "scoring.oscillation_tolerance" 0 20 5 "$CONFIG_JSON"

  # Convergence
  validate_range "forge-config.md" "convergence.max_iterations" 3 20 15 "$CONFIG_JSON"
  validate_range "forge-config.md" "convergence.plateau_threshold" 0 10 3 "$CONFIG_JSON"
  validate_range "forge-config.md" "convergence.plateau_patience" 1 5 3 "$CONFIG_JSON"
  validate_range "forge-config.md" "convergence.target_score" 60 100 90 "$CONFIG_JSON"

  # Top-level
  validate_range "forge-config.md" "total_retries_max" 5 30 10 "$CONFIG_JSON"

  # Shipping
  validate_range "forge-config.md" "shipping.min_score" 60 100 90 "$CONFIG_JSON"
  validate_range "forge-config.md" "shipping.evidence_max_age_minutes" 5 60 30 "$CONFIG_JSON"

  # Sprint
  validate_range "forge-config.md" "sprint.poll_interval_seconds" 10 120 30 "$CONFIG_JSON"
  validate_range "forge-config.md" "sprint.dependency_timeout_minutes" 5 180 60 "$CONFIG_JSON"

  # Tracking
  # archive_after_days: 30-365 or 0 — special case
  ARCHIVE_VAL=$(json_get "$CONFIG_JSON" "tracking.archive_after_days")
  if [[ -n "$ARCHIVE_VAL" ]]; then
    if [[ "$ARCHIVE_VAL" =~ ^[0-9]+$ ]]; then
      if [[ "$ARCHIVE_VAL" -eq 0 ]] || { [[ "$ARCHIVE_VAL" -ge 30 ]] && [[ "$ARCHIVE_VAL" -le 365 ]]; }; then
        add_result "OK" "forge-config.md" "tracking.archive_after_days" "Value $ARCHIVE_VAL is valid (0 or 30-365)"
      else
        add_result "ERROR" "forge-config.md" "tracking.archive_after_days" "Value $ARCHIVE_VAL must be 0 (disabled) or 30-365"
      fi
    else
      add_result "ERROR" "forge-config.md" "tracking.archive_after_days" "Value \"$ARCHIVE_VAL\" is not an integer"
    fi
  else
    add_result "OK" "forge-config.md" "tracking.archive_after_days" "Not set (default: 90)"
  fi

  # Scope
  validate_range "forge-config.md" "scope.decomposition_threshold" 2 10 3 "$CONFIG_JSON"

  # Routing
  validate_enum "forge-config.md" "routing.vague_threshold" "low medium high" "medium" "$CONFIG_JSON"

  # Model routing
  if json_has "$CONFIG_JSON" "model_routing"; then
    validate_enum "forge-config.md" "model_routing.default_tier" "fast standard premium" "standard" "$CONFIG_JSON"
  fi

  # Infra
  validate_range "forge-config.md" "infra.max_verification_tier" 1 5 3 "$CONFIG_JSON"

  # Preview
  validate_range "forge-config.md" "preview.max_fix_loops" 1 10 3 "$CONFIG_JSON"
fi

# ── Category C: Cross-field constraints ────────────────────────────────────

if $HAS_CONFIG; then
  # Pass/concerns gap
  PASS_T=$(json_get "$CONFIG_JSON" "scoring.pass_threshold")
  CONCERNS_T=$(json_get "$CONFIG_JSON" "scoring.concerns_threshold")
  PASS_T=${PASS_T:-80}
  CONCERNS_T=${CONCERNS_T:-60}
  if [[ "$PASS_T" =~ ^[0-9]+$ ]] && [[ "$CONCERNS_T" =~ ^[0-9]+$ ]]; then
    GAP=$((PASS_T - CONCERNS_T))
    if [[ $GAP -lt 10 ]]; then
      add_result "ERROR" "forge-config.md" "scoring.pass_threshold - concerns_threshold" "Gap is $GAP (must be >= 10)"
    else
      add_result "OK" "forge-config.md" "scoring.pass_threshold - concerns_threshold" "Gap is $GAP (>= 10)"
    fi
  fi

  # Weight ordering: warning_weight > info_weight
  WARN_W=$(json_get "$CONFIG_JSON" "scoring.warning_weight")
  INFO_W=$(json_get "$CONFIG_JSON" "scoring.info_weight")
  WARN_W=${WARN_W:-5}
  INFO_W=${INFO_W:-2}
  if [[ "$WARN_W" =~ ^[0-9]+$ ]] && [[ "$INFO_W" =~ ^[0-9]+$ ]]; then
    if [[ "$WARN_W" -le "$INFO_W" ]]; then
      add_result "ERROR" "forge-config.md" "scoring.warning_weight > info_weight" "warning_weight ($WARN_W) must be greater than info_weight ($INFO_W)"
    else
      add_result "OK" "forge-config.md" "scoring.warning_weight > info_weight" "warning_weight ($WARN_W) > info_weight ($INFO_W)"
    fi
  fi

  # target_score >= pass_threshold
  TARGET_S=$(json_get "$CONFIG_JSON" "convergence.target_score")
  TARGET_S=${TARGET_S:-90}
  if [[ "$TARGET_S" =~ ^[0-9]+$ ]] && [[ "$PASS_T" =~ ^[0-9]+$ ]]; then
    if [[ "$TARGET_S" -lt "$PASS_T" ]]; then
      add_result "ERROR" "forge-config.md" "convergence.target_score >= pass_threshold" "target_score ($TARGET_S) must be >= pass_threshold ($PASS_T)"
    else
      add_result "OK" "forge-config.md" "convergence.target_score >= pass_threshold" "target_score ($TARGET_S) >= pass_threshold ($PASS_T)"
    fi
  fi

  # shipping.min_score >= pass_threshold
  MIN_SCORE=$(json_get "$CONFIG_JSON" "shipping.min_score")
  MIN_SCORE=${MIN_SCORE:-90}
  if [[ "$MIN_SCORE" =~ ^[0-9]+$ ]] && [[ "$PASS_T" =~ ^[0-9]+$ ]]; then
    if [[ "$MIN_SCORE" -lt "$PASS_T" ]]; then
      add_result "ERROR" "forge-config.md" "shipping.min_score >= pass_threshold" "min_score ($MIN_SCORE) must be >= pass_threshold ($PASS_T)"
    else
      add_result "OK" "forge-config.md" "shipping.min_score >= pass_threshold" "min_score ($MIN_SCORE) >= pass_threshold ($PASS_T)"
    fi
  fi
fi

# ── Category D: Command executability (optional) ──────────────────────────

if $CHECK_COMMANDS; then
  check_command_executable() {
    local name="$1" cmd="$2"
    if [[ -z "$cmd" ]]; then
      return
    fi
    # Extract the first word (the binary)
    local binary
    binary=$(echo "$cmd" | awk '{print $1}')

    # Handle relative paths like ./gradlew
    if [[ "$binary" == ./* ]]; then
      local full_path="${PROJECT_ROOT}/${binary}"
      if [[ -x "$full_path" ]]; then
        add_result "OK" "forge.local.md" "commands.$name" "Executable \"$binary\" found at $full_path"
      else
        add_result "WARNING" "forge.local.md" "commands.$name" "Executable \"$binary\" not found or not executable at $full_path"
      fi
    else
      if command -v "$binary" &>/dev/null; then
        add_result "OK" "forge.local.md" "commands.$name" "Executable \"$binary\" found on PATH"
      else
        add_result "CRITICAL" "forge.local.md" "commands.$name" "Executable \"$binary\" not found on PATH"
      fi
    fi
  }

  check_command_executable "build" "$BUILD_CMD"
  check_command_executable "test" "$TEST_CMD"
  check_command_executable "lint" "$LINT_CMD"
  FORMAT_CMD=$(json_get "$LOCAL_JSON" "commands.format")
  if [[ -n "$FORMAT_CMD" ]]; then
    check_command_executable "format" "$FORMAT_CMD"
  fi
fi

# ── Category E: Unknown field detection ────────────────────────────────────

if $HAS_CONFIG; then
  KNOWN_CONFIG_FIELDS="scoring convergence total_retries_max shipping sprint tracking scope routing model_routing quality_gate mutation_testing visual_verification lsp observability data_classification automations wiki memory_discovery forge_ask graph linear frontend_polish preview infra autonomous documentation explore plan_cache confidence test_history condensation check_engine code_graph living_specs events playbooks mode_config"

  while IFS= read -r key; do
    if [[ -n "$key" ]] && ! echo " $KNOWN_CONFIG_FIELDS " | grep -q " $key "; then
      # Try to find a close match for typo detection
      SUGGESTION=""
      for known in $KNOWN_CONFIG_FIELDS; do
        # Simple Levenshtein-like check: same prefix (3+ chars)
        if [[ "${key:0:3}" == "${known:0:3}" ]] && [[ "$key" != "$known" ]]; then
          SUGGESTION=" (did you mean $known?)"
          break
        fi
      done
      add_result "WARNING" "forge-config.md" "$key" "Unknown top-level field${SUGGESTION}"
    fi
  done < <(json_keys "$CONFIG_JSON" "")
fi

# ── Framework-component compatibility checks ──────────────────────────────

if [[ -n "$FRAMEWORK" && "$FRAMEWORK" != "None" && "$FRAMEWORK" != "null" ]]; then
  # k8s: language should be null
  if [[ "$FRAMEWORK" == "k8s" ]]; then
    if [[ -n "$LANG" && "$LANG" != "None" && "$LANG" != "null" ]]; then
      add_result "WARNING" "forge.local.md" "components (k8s+language)" "k8s framework typically has language: null, got \"$LANG\""
    fi
  fi
  # go-stdlib: language should be go
  if [[ "$FRAMEWORK" == "go-stdlib" ]]; then
    if [[ "$LANG" != "go" ]]; then
      add_result "WARNING" "forge.local.md" "components (go-stdlib+language)" "go-stdlib framework should have language: go, got \"$LANG\""
    fi
  fi
  # embedded: language should be c or cpp
  if [[ "$FRAMEWORK" == "embedded" ]]; then
    if [[ "$LANG" != "c" && "$LANG" != "cpp" ]]; then
      add_result "WARNING" "forge.local.md" "components (embedded+language)" "embedded framework should have language: c or cpp, got \"$LANG\""
    fi
  fi
fi

# ── Output ──────────────────────────────────────────────────────────────────

if $JSON_OUTPUT; then
  # Build JSON output
  "$FORGE_PYTHON" -c "
import json, sys

results = []
files_checked = ['forge.local.md']

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    parts = line.split('|', 3)
    if len(parts) != 4:
        continue
    sev, f, field, msg = parts
    results.append({
        'severity': sev,
        'file': f,
        'field': field,
        'message': msg
    })
    if f not in files_checked:
        files_checked.append(f)

critical = sum(1 for r in results if r['severity'] == 'CRITICAL')
error = sum(1 for r in results if r['severity'] == 'ERROR')
warning = sum(1 for r in results if r['severity'] == 'WARNING')
ok = sum(1 for r in results if r['severity'] == 'OK')

# Filter out OK results unless verbose
show_results = results if $( $VERBOSE && echo 'True' || echo 'False' ) else [r for r in results if r['severity'] != 'OK']

report = {
    'validator_version': '1.0.0',
    'files_checked': files_checked,
    'results': show_results,
    'summary': {
        'critical': critical,
        'error': error,
        'warning': warning,
        'ok': ok
    }
}

print(json.dumps(report, indent=2))
" <<< "$RESULTS"
else
  # Human-readable output
  echo "Config Validation Report"
  echo "========================"
  echo ""
  echo "Project:         ${PROJECT_ROOT}"
  echo "forge.local.md:  ${LOCAL_FILE}"
  echo "forge-config.md: $( $HAS_CONFIG && echo "$CONFIG_FILE" || echo "(not found — using defaults)" )"
  echo ""

  # Print results
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    IFS='|' read -r sev file field msg <<< "$line"
    if [[ "$sev" == "OK" ]] && ! $VERBOSE; then
      continue
    fi
    printf "%-9s %-17s %-40s %s\n" "$sev" "$file" "$field" "$msg"
  done <<< "$RESULTS"

  echo ""
  echo "Summary: ${CRITICAL_COUNT} critical, ${ERROR_COUNT} errors, ${WARNING_COUNT} warnings, ${OK_COUNT} ok"

  # Recommendation
  if [[ $CRITICAL_COUNT -gt 0 ]] || [[ $ERROR_COUNT -gt 0 ]]; then
    echo "Fix errors before running the pipeline."
  elif [[ $WARNING_COUNT -gt 0 ]]; then
    echo "Warnings found. Pipeline will use defaults for unset values."
  else
    echo "Configuration is valid. Ready for /forge-run."
  fi
fi

# ── Exit code ───────────────────────────────────────────────────────────────

if [[ $CRITICAL_COUNT -gt 0 ]] || [[ $ERROR_COUNT -gt 0 ]]; then
  exit 1
elif [[ $WARNING_COUNT -gt 0 ]]; then
  exit 2
else
  exit 0
fi
