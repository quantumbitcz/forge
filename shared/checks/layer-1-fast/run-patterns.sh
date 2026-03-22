#!/usr/bin/env bash
set -euo pipefail

# Layer 1 fast pattern matching engine
# Usage: run-patterns.sh <file> <rules.json> [override.json]
# Emits findings to stdout in output-format.md format. Always exits 0.

FILE="${1:?Usage: run-patterns.sh <file> <rules.json> [override.json]}"
RULES_JSON="${2:?Usage: run-patterns.sh <file> <rules.json> [override.json]}"
OVERRIDE_JSON="${3:-}"

# Compute project-relative path (preferred) or fall back to basename
PROJECT_ROOT="$(git -C "$(dirname "$FILE")" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "$PROJECT_ROOT" ]]; then
  DISPLAY_PATH="${FILE#"$PROJECT_ROOT/"}"
else
  DISPLAY_PATH="$(basename "$FILE")"
fi

# --- Build merged config (single python3 call) ---
# Produces section-delimited JSON: RULES, THRESHOLDS, BOUNDARIES.
build_merged_config() {
  python3 -c "
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

    # Additional rules use scope_pattern instead of scope — normalize
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
" "$RULES_JSON" "$OVERRIDE_JSON"
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
      # Treat as regex against file path
      if echo "$filepath" | grep -qE "$scope"; then
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

# --- Main ---
main() {
  local config
  config="$(build_merged_config)"

  local rules_json thresholds_json boundaries_json
  rules_json="$(echo "$config" | sed -n '/^RULES$/,/^THRESHOLDS$/{ /^RULES$/d; /^THRESHOLDS$/d; p; }')"
  thresholds_json="$(echo "$config" | sed -n '/^THRESHOLDS$/,/^BOUNDARIES$/{ /^THRESHOLDS$/d; /^BOUNDARIES$/d; p; }')"
  boundaries_json="$(echo "$config" | sed -n '/^BOUNDARIES$/,$ { /^BOUNDARIES$/d; p; }')"

  # --- Rule matching (fields delimited by 0x1F unit separator) ---
  local SEP=$'\x1f'
  local rule_lines
  rule_lines="$(echo "$rules_json" | python3 -c "
import json, sys
SEP = '\x1f'
rules = json.load(sys.stdin)
for r in rules:
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
    if [[ -n "$scope_exclude" ]] && echo "$FILE" | grep -qE "$scope_exclude"; then
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

  # --- Threshold checks (single awk pass) ---
  local file_size_default func_size_default file_size_overrides_json
  file_size_default="$(echo "$thresholds_json" | python3 -c "
import json, sys
t = json.load(sys.stdin)
print(t.get('file_size', {}).get('default', 300))
" 2>/dev/null || echo 300)"

  func_size_default="$(echo "$thresholds_json" | python3 -c "
import json, sys
t = json.load(sys.stdin)
print(t.get('function_size', {}).get('default', 30))
" 2>/dev/null || echo 30)"

  file_size_overrides_json="$(echo "$thresholds_json" | python3 -c "
import json, sys
t = json.load(sys.stdin)
print(json.dumps(t.get('file_size', {}).get('overrides', {})))
" 2>/dev/null || echo '{}')"

  # Pick the right file size threshold: first matching override key, or default
  local file_size_threshold="$file_size_default"
  local override_threshold
  override_threshold="$(python3 -c "
import json, sys
overrides = json.loads(sys.argv[1])
filepath = sys.argv[2]
for key, val in overrides.items():
    if key in filepath:
        print(val)
        sys.exit(0)
" "$file_size_overrides_json" "$FILE" 2>/dev/null || true)"
  if [[ -n "$override_threshold" ]]; then
    file_size_threshold="$override_threshold"
  fi

  # Awk pass: line count + function size tracking
  # NOTE: Function boundary detection is currently Kotlin-only (matches `fun ` declarations).
  # Other languages need their own patterns (def for Python, func for Go, fn for Rust, etc.).
  # File size checking works for all languages. This is a known Phase 1 limitation.
  awk -v display_path="$DISPLAY_PATH" \
      -v file_thresh="$file_size_threshold" \
      -v func_thresh="$func_size_default" '
  BEGIN { func_start=0; func_name="" }
  # Track Kotlin fun declarations
  /^[[:space:]]*(override )?((suspend|private|public|internal|protected|open|abstract) )*(fun )/ {
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
    sub(/\(.*/, "", func_name)
    sub(/.* fun /, "", func_name)
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
  boundary_count="$(echo "$boundaries_json" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)"

  for (( b=0; b<boundary_count; b++ )); do
    local b_scope b_severity b_category b_message b_fields
    b_fields="$(echo "$boundaries_json" | python3 -c "
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
