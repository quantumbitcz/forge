#!/usr/bin/env bash
set -euo pipefail

# Layer 1 fast pattern matching engine
# Usage: run-patterns.sh <file> <rules.json> [override.json]
# Emits findings to stdout in output-format.md format. Always exits 0.

FILE="${1:?Usage: run-patterns.sh <file> <rules.json> [override.json]}"
RULES_JSON="${2:?Usage: run-patterns.sh <file> <rules.json> [override.json]}"
OVERRIDE_JSON="${3:-}"

# Resolve python command (python3 preferred, python as fallback).
# This script does not source platform.sh to avoid overhead on every
# Edit/Write hook invocation (same rationale as engine.sh and linter adapters).
_PY="python3"
command -v python3 &>/dev/null || _PY="python"
if ! command -v "$_PY" &>/dev/null; then
  # No python available — skip all Layer 1 checks silently
  exit 0
fi

# Compute project-relative path (preferred) or fall back to basename
PROJECT_ROOT="$(git -C "$(dirname "$FILE")" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "$PROJECT_ROOT" ]]; then
  DISPLAY_PATH="${FILE#"$PROJECT_ROOT/"}"
else
  DISPLAY_PATH="$(basename "$FILE")"
fi

# --- Build merged config (single Python call) ---
# Produces section-delimited JSON: RULES, THRESHOLDS, BOUNDARIES.
build_merged_config() {
  "$_PY" -c "
import json, sys
rules_path = sys.argv[1]
override_path = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else ''

with open(rules_path) as f:
    base = json.load(f)

rules = list(base.get('rules', []))
thresholds = base.get('thresholds', {})
boundaries = list(base.get('boundaries', []))

disabled, sev_overrides = set(), {}
if override_path:
    with open(override_path) as f:
        ov = json.load(f)

    # Detect language from file extension for variant_rules selection
    import os
    ext_to_lang = {
        '.kt': 'kotlin', '.kts': 'kotlin',
        '.java': 'java',
        '.ts': 'typescript', '.tsx': 'typescript',
        '.js': 'typescript', '.jsx': 'typescript',
        '.py': 'python',
        '.go': 'go',
        '.rs': 'rust',
        '.c': 'c', '.h': 'c',
        '.cs': 'csharp', '.csx': 'csharp',
        '.cpp': 'cpp', '.cc': 'cpp', '.cxx': 'cpp', '.hpp': 'cpp',
        '.swift': 'swift',
        '.rb': 'ruby',
        '.php': 'php',
        '.dart': 'dart',
        '.ex': 'elixir', '.exs': 'elixir',
        '.scala': 'scala', '.sc': 'scala',
        '.yml': 'yaml', '.yaml': 'yaml',
        '.dockerfile': 'dockerfile',
    }
    checked_file = sys.argv[3] if len(sys.argv) > 3 else ''
    basename = os.path.basename(checked_file)
    if basename == 'Dockerfile' or basename.startswith('Dockerfile.'):
        file_lang = 'dockerfile'
    else:
        file_lang = ext_to_lang.get(os.path.splitext(checked_file)[1].lower(), '')

    # Support both flat format and new nested format (variant_rules / shared_rules)
    if 'variant_rules' in ov or 'shared_rules' in ov:
        # New nested format: collect from shared_rules + matching variant
        shared = ov.get('shared_rules', {})
        for r in shared.get('additional_rules', []):
            if 'scope_pattern' in r and 'scope' not in r:
                r['scope'] = r['scope_pattern']
            rules.append(r)
        for b in shared.get('additional_boundaries', []):
            boundaries.append(b)

        variant = ov.get('variant_rules', {}).get(file_lang, {})
        for r in variant.get('additional_rules', []):
            if 'scope_pattern' in r and 'scope' not in r:
                r['scope'] = r['scope_pattern']
            rules.append(r)
        for b in variant.get('additional_boundaries', []):
            boundaries.append(b)
    else:
        # Legacy flat format
        for r in ov.get('additional_rules', []):
            if 'scope_pattern' in r and 'scope' not in r:
                r['scope'] = r['scope_pattern']
            rules.append(r)
        for b in ov.get('additional_boundaries', []):
            boundaries.append(b)

    disabled = set(ov.get('disabled_rules', []))
    sev_overrides = ov.get('severity_overrides', {})

    # Merge threshold overrides
    for tkey, tval in ov.get('threshold_overrides', {}).items():
        if tkey in thresholds and isinstance(tval, dict):
            # Handle default_override: replaces the base default
            if 'default_override' in tval:
                thresholds[tkey]['default'] = tval['default_override']
                tval = {k: v for k, v in tval.items() if k != 'default_override'}
            if 'overrides' not in thresholds[tkey]:
                thresholds[tkey]['overrides'] = {}
            thresholds[tkey]['overrides'].update(tval)

# Apply severity overrides and filter disabled
active_rules = []
for r in rules:
    if r['id'] in disabled:
        continue
    if r['id'] in sev_overrides:
        r['severity'] = sev_overrides[r['id']]
    active_rules.append(r)

print('RULES')
print(json.dumps(active_rules))
print('THRESHOLDS')
print(json.dumps(thresholds))
print('BOUNDARIES')
print(json.dumps(boundaries))
" "$RULES_JSON" "$OVERRIDE_JSON" "$FILE"
}

# --- Scope matching ---
# Returns 0 (true) if the file is in scope for a rule.
in_scope() {
  local scope="$1"
  local filepath="$2"
  case "$scope" in
    all)
      return 0
      ;;
    main)
      if echo "$filepath" | grep -qE '/(test|tests|spec|test-fixtures|integrationTest)/'; then
        return 1
      fi
      return 0
      ;;
    test)
      if echo "$filepath" | grep -qE '/(test|tests|spec|test-fixtures|integrationTest)/'; then
        return 0
      fi
      return 1
      ;;
    *)
      # Treat as regex against file path; silently fail for invalid regex
      if echo "$filepath" | grep -qE "$scope" 2>/dev/null; then
        return 0
      fi
      return 1
      ;;
  esac
}

# --- Emit a finding line ---
emit() {
  local line="$1" category="$2" severity="$3" message="$4" fix_hint="$5"
  message="${message//|/\\|}"
  fix_hint="${fix_hint//|/\\|}"
  echo "${DISPLAY_PATH}:${line} | ${category} | ${severity} | ${message} | ${fix_hint}"
}

# --- Binary file detection ---
# Skip binary files to avoid corrupted grep output
is_binary_file() {
  # Check for null bytes in first 8KB — reliable binary indicator
  # Uses Python (already a dependency) instead of grep -P (not available on macOS)
  if "$_PY" -c "import sys; sys.exit(0 if b'\\x00' in open(sys.argv[1],'rb').read(8192) else 1)" "$1" 2>/dev/null; then
    return 0
  fi
  # Fallback: check file command output (if available)
  if command -v file &>/dev/null; then
    local ftype
    ftype="$(file --brief --mime-type "$1" 2>/dev/null || true)"
    case "$ftype" in
      text/*|application/json|application/xml|application/javascript) return 1 ;;
      application/octet-stream|image/*|audio/*|video/*) return 0 ;;
    esac
  fi
  return 1
}

# --- Main ---
main() {
  # Skip binary files entirely
  if is_binary_file "$FILE"; then
    exit 0
  fi

  local config
  config="$(build_merged_config)"

  local rules_json thresholds_json boundaries_json
  rules_json="$(echo "$config" | sed -n '/^RULES$/,/^THRESHOLDS$/{ /^RULES$/d; /^THRESHOLDS$/d; p; }')"
  thresholds_json="$(echo "$config" | sed -n '/^THRESHOLDS$/,/^BOUNDARIES$/{ /^THRESHOLDS$/d; /^BOUNDARIES$/d; p; }')"
  boundaries_json="$(echo "$config" | sed -n '/^BOUNDARIES$/,$ { /^BOUNDARIES$/d; p; }')"

  # --- Rule matching (fields delimited by 0x1F unit separator) ---
  local SEP=$'\x1f'
  local rule_lines
  rule_lines="$(echo "$rules_json" | "$_PY" -c "
import json, sys
SEP = '\x1f'
rules = json.load(sys.stdin)
for r in rules:
    if r.get('pattern') is None:
        continue
    fields = [
        r['id'],
        r['pattern'],
        r.get('exclude_pattern', ''),
        r['severity'],
        r['category'],
        r['message'],
        r.get('fix_hint', ''),
        r.get('scope', r.get('scope_pattern', 'all')),
        str(r.get('case_insensitive', False)),
        r.get('scope_exclude', '')
    ]
    print(SEP.join(fields))
")"

  while IFS="$SEP" read -r id pattern exclude_pattern severity category message fix_hint scope case_insensitive scope_exclude; do
    [[ -z "$id" ]] && continue

    # Check scope
    if ! in_scope "$scope" "$FILE"; then
      continue
    fi

    # Check scope_exclude — skip if file matches exclusion pattern
    if [[ -n "$scope_exclude" ]] && echo "$FILE" | grep -qE "$scope_exclude" 2>/dev/null; then
      continue
    fi

    # Build grep flags
    local grep_flags="-nE"
    if [[ "$case_insensitive" == "True" ]]; then
      grep_flags="-niE"
    fi

    # Run grep, filter excludes, emit findings
    local matches
    matches="$(grep $grep_flags "$pattern" "$FILE" 2>/dev/null || true)"
    if [[ -n "$exclude_pattern" && -n "$matches" ]]; then
      matches="$(echo "$matches" | grep -vE "$exclude_pattern" || true)"
    fi

    if [[ -n "$matches" ]]; then
      while IFS= read -r match_line; do
        local linenum
        linenum="$(echo "$match_line" | cut -d: -f1)"
        emit "$linenum" "$category" "$severity" "$message" "$fix_hint"
      done <<< "$matches"
    fi
  done <<< "$rule_lines"

  # --- Structural checks (file-level absence/presence checks) ---
  local structural_checks
  structural_checks="$(echo "$rules_json" | "$_PY" -c "
import json, sys
SEP = '\x1f'
rules = json.load(sys.stdin)
for r in rules:
    sc = r.get('structural_check')
    if not sc or r.get('pattern') is not None:
        continue
    fields = [r['id'], sc, r['severity'], r['category'], r['message'], r.get('fix_hint', ''),
              r.get('scope', r.get('scope_pattern', 'all')), r.get('scope_exclude', '')]
    print(SEP.join(fields))
" 2>/dev/null || true)"

  if [[ -n "$structural_checks" ]]; then
    while IFS="$SEP" read -r sc_id sc_type sc_severity sc_category sc_message sc_fix_hint sc_scope sc_scope_exclude; do
      [[ -z "$sc_id" ]] && continue

      # Apply scope and scope_exclude filtering (same as regex rules)
      if ! in_scope "$sc_scope" "$FILE"; then
        continue
      fi
      if [[ -n "$sc_scope_exclude" ]] && echo "$FILE" | grep -qE "$sc_scope_exclude" 2>/dev/null; then
        continue
      fi

      case "$sc_type" in
        awk_no_user_instruction)
          # Check if file contains a USER instruction (Dockerfile-specific)
          if ! grep -qiE "^USER\s" "$FILE" 2>/dev/null; then
            emit "1" "$sc_category" "$sc_severity" "$sc_message" "$sc_fix_hint"
          fi
          ;;
        *)
          echo "[run-patterns] WARNING: unknown structural_check type '$sc_type' in rule $sc_id — skipping" >&2
          ;;
      esac
    done <<< "$structural_checks"
  fi

  # --- Threshold checks (single awk pass) ---
  local file_size_default func_size_default file_size_overrides_json
  file_size_default="$(echo "$thresholds_json" | "$_PY" -c "
import json, sys
t = json.load(sys.stdin)
print(t.get('file_size', {}).get('default', 300))
" 2>/dev/null || echo 300)"

  func_size_default="$(echo "$thresholds_json" | "$_PY" -c "
import json, sys
t = json.load(sys.stdin)
print(t.get('function_size', {}).get('default', 30))
" 2>/dev/null || echo 30)"

  file_size_overrides_json="$(echo "$thresholds_json" | "$_PY" -c "
import json, sys
t = json.load(sys.stdin)
print(json.dumps(t.get('file_size', {}).get('overrides', {})))
" 2>/dev/null || echo '{}')"

  # Pick the right file size threshold: first matching override key, or default
  local file_size_threshold="$file_size_default"
  local override_threshold
  override_threshold="$("$_PY" -c "
import json, sys, re
overrides = json.loads(sys.argv[1])
filepath = sys.argv[2]
for key, val in overrides.items():
    # Normalize key: strip trailing slashes to prevent double-slash regex issues
    normalized = key.rstrip('/')
    # Match as path component (e.g., 'build' matches 'src/build/Main.java'
    # but not 'mybuild/settings.xml') or as regex if it contains regex chars
    if re.search(r'[*+?\\[\\]()^$|]', normalized):
        # Regex pattern — use as-is
        if re.search(normalized, filepath):
            print(val)
            sys.exit(0)
    else:
        # Path component match — must be bounded by / or start/end of string
        pattern = r'(^|/)' + re.escape(normalized) + r'(/|$)'
        if re.search(pattern, filepath):
            print(val)
            sys.exit(0)
" "$file_size_overrides_json" "$FILE" 2>/dev/null || true)"
  if [[ -n "$override_threshold" ]]; then
    file_size_threshold="$override_threshold"
  fi

  # Awk pass: line count + function size tracking
  # Function boundary detection uses per-language awk patterns (no shell variable escaping).
  # Patterns avoid literal parens to prevent awk regex portability issues (macOS awk vs gawk).
  # Supports Kotlin, Java, Python, Go, Rust, TypeScript/JS, Swift, and C#.
  # Limitation: TS/JS class methods and typed arrow functions are not detected (regex limitation).
  # File size checking works for all languages.
  local file_ext="${FILE##*.}"

  awk -v display_path="$DISPLAY_PATH" \
      -v file_thresh="$file_size_threshold" \
      -v func_thresh="$func_size_default" \
      -v lang="$file_ext" '
  BEGIN { func_start=0; func_name="" }

  # Per-language function boundary detection — no literal parens in regex
  # to avoid awk portability issues with shell variable escaping
  lang == "kt" || lang == "kts" {
    if ($0 ~ /^[[:space:]]*(override )?(suspend |private |public |internal |protected |open |abstract )*(fun )[a-zA-Z]/) {
      handle_func()
    }
  }
  lang == "java" {
    if ($0 ~ /^[[:space:]]*(public |private |protected |static |abstract |final |synchronized |native )+(void|int|long|boolean|String|[A-Z][a-zA-Z0-9]*) +[a-z][a-zA-Z0-9]*[[:space:]]*[({]/) {
      handle_func()
    }
  }
  lang == "py" {
    if ($0 ~ /^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+[a-zA-Z_]/) {
      handle_func()
    }
  }
  lang == "go" {
    if ($0 ~ /^func[[:space:]]/) {
      handle_func()
    }
  }
  lang == "rs" {
    if ($0 ~ /^[[:space:]]*(pub |async |unsafe )*fn[[:space:]]+[a-zA-Z_]/) {
      handle_func()
    }
  }
  lang == "ts" || lang == "tsx" || lang == "js" || lang == "jsx" {
    if ($0 ~ /^[[:space:]]*(export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+[a-zA-Z_$]/) {
      handle_func()
    }
  }
  lang == "swift" {
    if ($0 ~ /^[[:space:]]*(override |private |public |internal |open |static |class |mutating |nonmutating )*(func )[a-zA-Z_]/) {
      handle_func()
    }
  }
  lang == "cs" || lang == "csx" {
    if ($0 ~ /^[[:space:]]*(public |private |protected |internal |static |virtual |override |abstract |async |sealed )+(void|int|long|bool|string|Task|[A-Z][a-zA-Z0-9]*) +[A-Z][a-zA-Z0-9]*[[:space:]]*[({]/) {
      handle_func()
    }
  }

  function handle_func() {
    if (func_start > 0) {
      func_len = NR - func_start
      if (func_len > func_thresh) {
        printf "%s:%d | QUAL-READ | WARNING | Function %s is %d lines (threshold: %d) | Break into smaller functions with single responsibility.\n", display_path, func_start, func_name, func_len, func_thresh
      }
    }
    func_start = NR
    line = $0
    gsub(/^[[:space:]]+/, "", line)
    func_name = line
    # Go: handle receiver methods BEFORE stripping parens
    # e.g., "func (r *MyType) MethodName(x int) int {" → strip receiver first
    if (lang == "go") {
      sub(/^func[[:space:]]+\([^)]*\)[[:space:]]+/, "func ", func_name)
    }
    # Strip everything from first ( or { onward (args, body)
    sub(/[({].*/, "", func_name)
    # Extract just the function name by stripping known keyword prefixes
    # Generic: strip common function keywords and modifiers
    sub(/.*(fun |func |fn |def |function )/, "", func_name)
    # C#/Java: strip return type — take last space-delimited word
    if (lang == "cs" || lang == "csx" || lang == "java") {
      n = split(func_name, parts, /[[:space:]]+/)
      if (n > 0) func_name = parts[n]
    }
    # Trim remaining whitespace
    gsub(/[[:space:]]+$/, "", func_name)
  }

  END {
    # Check last function
    if (func_start > 0) {
      func_len = NR - func_start
      if (func_len > func_thresh) {
        printf "%s:%d | QUAL-READ | WARNING | Function %s is %d lines (threshold: %d) | Break into smaller functions with single responsibility.\n", display_path, func_start, func_name, func_len, func_thresh
      }
    }
    # File size check
    if (NR > file_thresh) {
      printf "%s:0 | QUAL-READ | WARNING | File is %d lines (threshold: %d) | Split into smaller, focused files.\n", display_path, NR, file_thresh
    }
  }
  ' "$FILE"

  # --- Boundary checks ---
  local boundary_count
  boundary_count="$(echo "$boundaries_json" | "$_PY" -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)"

  for (( b=0; b<boundary_count; b++ )); do
    local b_scope b_severity b_category b_message b_fields
    b_fields="$(echo "$boundaries_json" | "$_PY" -c "
import json, sys
boundaries = json.load(sys.stdin)
b = boundaries[$b]
SEP = '\x1f'
fields = [
    b.get('scope_pattern', ''),
    b.get('severity', 'WARNING'),
    b.get('category', 'ARCH-BOUNDARY'),
    b.get('message', 'Boundary violation'),
    str(len(b.get('forbidden_imports', [])))
]
print(SEP.join(fields))
for p in b.get('forbidden_imports', []):
    print(p)
")"

    # First line has the fields, subsequent lines are forbidden patterns
    b_scope="$(echo "$b_fields" | head -1 | cut -d$'\x1f' -f1)"
    b_severity="$(echo "$b_fields" | head -1 | cut -d$'\x1f' -f2)"
    b_category="$(echo "$b_fields" | head -1 | cut -d$'\x1f' -f3)"
    b_message="$(echo "$b_fields" | head -1 | cut -d$'\x1f' -f4)"

    # Check if file matches boundary scope
    if [[ -n "$b_scope" ]]; then
      if ! echo "$FILE" | grep -qE "$b_scope"; then
        continue
      fi
    fi

    # Process each forbidden import pattern (lines 2+)
    echo "$b_fields" | tail -n +2 | while IFS= read -r forbidden_pattern; do
      [[ -z "$forbidden_pattern" ]] && continue
      local matches
      matches="$(grep -nE "$forbidden_pattern" "$FILE" 2>/dev/null || true)"
      if [[ -n "$matches" ]]; then
        while IFS= read -r match_line; do
          local linenum
          linenum="$(echo "$match_line" | cut -d: -f1)"
          emit "$linenum" "$b_category" "$b_severity" "$b_message" ""
        done <<< "$matches"
      fi
    done
  done
}

# Wrap everything so we always exit 0
main "$@" || true
exit 0
