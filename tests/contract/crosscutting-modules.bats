#!/usr/bin/env bats
# Contract tests: cross-cutting module structural consistency.
# Validates .md files in auth/, observability/, messaging/, caching/, search/,
# storage/, databases/, persistence/, migrations/, api-protocols/.

load '../helpers/test-helpers'

# shellcheck source=../lib/module-lists.bash
source "$PLUGIN_ROOT/tests/lib/module-lists.bash"

MODULES_DIR="$PLUGIN_ROOT/modules"

# Cross-cutting directories to validate
CROSSCUTTING_DIRS=(auth observability messaging caching search storage databases persistence migrations api-protocols)

# ---------------------------------------------------------------------------
# Helper: collect all .md files across cross-cutting directories
# ---------------------------------------------------------------------------
_collect_crosscutting_files() {
  local files=()
  for dir in "${CROSSCUTTING_DIRS[@]}"; do
    local dir_path="$MODULES_DIR/$dir"
    [[ -d "$dir_path" ]] || continue
    for f in "$dir_path"/*.md; do
      [[ -f "$f" ]] || continue
      local basename
      basename="$(basename "$f")"
      # Skip READMEs and index files
      [[ "$basename" == "README.md" || "$basename" == "index.md" ]] && continue
      files+=("$f")
    done
  done
  printf '%s\n' "${files[@]}"
}

# ---------------------------------------------------------------------------
# 1. Minimum module counts per cross-cutting directory
# ---------------------------------------------------------------------------
@test "crosscutting-modules: minimum module counts not violated" {
  local dir count
  for dir in "${CROSSCUTTING_DIRS[@]}"; do
    count=0
    for f in "$MODULES_DIR/$dir"/*.md; do
      [[ -f "$f" ]] && (( ++count ))
    done
    local min_var="MIN_${dir^^}_MODULES"
    min_var="${min_var//-/_}"
    local min_count="${!min_var:-0}"
    if (( min_count > 0 )); then
      guard_min_count "$dir modules" "$count" "$min_count"
    fi
  done
}

# ---------------------------------------------------------------------------
# 2. Each module has required sections (4-of-7 minimum)
# ---------------------------------------------------------------------------
@test "crosscutting-modules: each module has at least 4 of 7 standard sections" {
  local failures=()
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    local section_count=0
    grep -q '^## Overview' "$f" && (( section_count++ )) || true
    grep -qE '^## (Architecture|Config)' "$f" && (( section_count++ )) || true
    grep -q '^## Performance' "$f" && (( section_count++ )) || true
    grep -q '^## Security' "$f" && (( section_count++ )) || true
    grep -q '^## Testing' "$f" && (( section_count++ )) || true
    grep -q '^## Dos' "$f" && (( section_count++ )) || true
    grep -q "^## Don" "$f" && (( section_count++ )) || true
    if (( section_count < 4 )); then
      local rel_path="${f#$MODULES_DIR/}"
      failures+=("$rel_path ($section_count/7)")
    fi
  done < <(_collect_crosscutting_files)
  if (( ${#failures[@]} > 0 )); then
    fail "Modules with fewer than 4 standard sections: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 3. Minimum file size check (>500 bytes -- not just a stub)
# ---------------------------------------------------------------------------
@test "crosscutting-modules: each module is substantive (>500 bytes)" {
  local failures=()
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    local size
    size="$(wc -c < "$f" | tr -d ' ')"
    if (( size < 500 )); then
      local rel_path="${f#$MODULES_DIR/}"
      failures+=("$rel_path (${size}B)")
    fi
  done < <(_collect_crosscutting_files)
  if (( ${#failures[@]} > 0 )); then
    fail "Modules below 500-byte minimum (stubs): ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 4. Minimum line count check (>50 lines)
# ---------------------------------------------------------------------------
@test "crosscutting-modules: each module has at least 50 lines" {
  local failures=()
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    local line_count
    line_count="$(wc -l < "$f" | tr -d ' ')"
    if (( line_count < 50 )); then
      local rel_path="${f#$MODULES_DIR/}"
      failures+=("$rel_path (${line_count} lines)")
    fi
  done < <(_collect_crosscutting_files)
  if (( ${#failures[@]} > 0 )); then
    fail "Modules below 50-line minimum: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 5. Overview section is present in every module
# ---------------------------------------------------------------------------
@test "crosscutting-modules: every module has an Overview section" {
  local failures=()
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if ! grep -q '^## Overview' "$f"; then
      local rel_path="${f#$MODULES_DIR/}"
      failures+=("$rel_path")
    fi
  done < <(_collect_crosscutting_files)
  if (( ${#failures[@]} > 0 )); then
    fail "Modules missing ## Overview section: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 6. Dos section is present in every module
# ---------------------------------------------------------------------------
@test "crosscutting-modules: every module has a Dos section" {
  local failures=()
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if ! grep -q '^## Dos' "$f"; then
      local rel_path="${f#$MODULES_DIR/}"
      failures+=("$rel_path")
    fi
  done < <(_collect_crosscutting_files)
  if (( ${#failures[@]} > 0 )); then
    fail "Modules missing ## Dos section: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 7. Don'ts section is present in every module
# ---------------------------------------------------------------------------
@test "crosscutting-modules: every module has a Don'ts section" {
  local failures=()
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if ! grep -q "^## Don" "$f"; then
      local rel_path="${f#$MODULES_DIR/}"
      failures+=("$rel_path")
    fi
  done < <(_collect_crosscutting_files)
  if (( ${#failures[@]} > 0 )); then
    fail "Modules missing ## Don'ts section: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 8. Dos/Don'ts section quality: at least 3 entries each
# ---------------------------------------------------------------------------
@test "crosscutting-modules: Dos sections have at least 3 entries" {
  local failures=()
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if grep -q '^## Dos' "$f"; then
      local dos_count
      # Count bullet items between ## Dos and next ## heading
      dos_count="$(sed -n '/^## Dos/,/^## /{ /^- /p; }' "$f" | wc -l | tr -d ' ')"
      if (( dos_count < 3 )); then
        local rel_path="${f#$MODULES_DIR/}"
        failures+=("$rel_path ($dos_count entries)")
      fi
    fi
  done < <(_collect_crosscutting_files)
  if (( ${#failures[@]} > 0 )); then
    fail "Modules with fewer than 3 Dos entries: ${failures[*]}"
  fi
}
