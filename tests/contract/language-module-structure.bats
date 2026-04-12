#!/usr/bin/env bats
# Contract test: language module structural validation.
# Each language module in modules/languages/ must exist, be non-empty,
# and contain required sections (overview, Dos, Don'ts).

load '../helpers/test-helpers'

source "$PLUGIN_ROOT/tests/lib/module-lists.bash"

@test "language-modules: minimum count guard (>= $MIN_LANGUAGES)" {
  guard_min_count "languages" "${#DISCOVERED_LANGUAGES[@]}" "$MIN_LANGUAGES"
}

@test "language-modules: all discovered modules are non-empty" {
  local failures=()
  for lang in "${DISCOVERED_LANGUAGES[@]}"; do
    local file="$PLUGIN_ROOT/modules/languages/${lang}.md"
    [[ -s "$file" ]] || failures+=("${lang}: file is empty or missing")
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Empty/missing language modules: ${#failures[@]}"
  fi
}

@test "language-modules: each module contains required sections" {
  local failures=()
  for lang in "${DISCOVERED_LANGUAGES[@]}"; do
    local file="$PLUGIN_ROOT/modules/languages/${lang}.md"
    [[ -f "$file" ]] || continue

    # Must have at least one level-2 heading (overview)
    grep -q "^## " "$file" || failures+=("${lang}: no ## heading (overview)")

    # Must have Dos section (case-insensitive, handles "Dos", "Do", "Best Practices")
    grep -qi "^##.*\(Dos\|Do \|Best Practice\|Recommended\)" "$file" || \
      failures+=("${lang}: no Dos/Best Practices section")

    # Must have Don'ts section (case-insensitive, handles "Don'ts", "Avoid", "Anti-patterns")
    grep -qi "^##.*\(Don.t\|Avoid\|Anti.pattern\)" "$file" || \
      failures+=("${lang}: no Don'ts/Avoid section")
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Language module section violations: ${#failures[@]}"
  fi
}
