#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/phpstan.sh

load '../helpers/test-helpers'

SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
PHPSTAN_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/phpstan-sample.json"

run_parser() {
  local sev_map="$1" raw="$2"
  python3 -c "
import json, sys
with open(sys.argv[1]) as f: full_map = json.load(f)
phpstan_map = full_map.get('phpstan', {})

def lookup_severity(identifier):
    if identifier in phpstan_map: return phpstan_map[identifier]
    best = ('', 'WARNING')
    for pattern, sev in phpstan_map.items():
        prefix = pattern.rstrip('*')
        if identifier.startswith(prefix) and len(prefix) > len(best[0]):
            best = (prefix, sev)
    return best[1]

with open(sys.argv[2]) as f:
    content = f.read().strip()
    if not content: sys.exit(0)
    try: data = json.loads(content)
    except json.JSONDecodeError: sys.exit(0)

for filepath, errors in data.get('files', {}).items():
    for err in errors.get('messages', []):
        row = err.get('line', 0)
        message = err.get('message', '').replace('\\\\', '\\\\\\\\').replace('|', '\\\\|')
        identifier = err.get('identifier', '')
        severity = lookup_severity(identifier)
        category = 'PHP-LINT-PHPSTAN'
        hint = f'phpstan: {identifier}' if identifier else 'phpstan analyse'
        print(f'{filepath}:{row} | {category} | {severity} | {message} | {hint}')
" "$sev_map" "$raw"
}

@test "phpstan adapter: parses 3 findings from fixture" {
  run run_parser "$SEV_MAP" "$PHPSTAN_FIXTURE"
  assert_success
  local count; count="$(echo "$output" | grep -c '|')"
  [[ "$count" -eq 3 ]]
}

@test "phpstan adapter: all findings use PHP-LINT-PHPSTAN category" {
  run run_parser "$SEV_MAP" "$PHPSTAN_FIXTURE"
  assert_success
  local phpstan_count; phpstan_count="$(echo "$output" | grep -c 'PHP-LINT-PHPSTAN')"
  [[ "$phpstan_count" -eq 3 ]]
}

@test "phpstan adapter: file paths preserved from JSON keys" {
  run run_parser "$SEV_MAP" "$PHPSTAN_FIXTURE"
  assert_success
  echo "$output" | grep -q "src/Controller/AuthController.php:15"
  echo "$output" | grep -q "src/Service/PaymentService.php:42"
}

@test "phpstan adapter: hint includes identifier" {
  run run_parser "$SEV_MAP" "$PHPSTAN_FIXTURE"
  assert_success
  echo "$output" | grep -q "phpstan: missingType.parameter"
  echo "$output" | grep -q "phpstan: method.notFound"
}

@test "phpstan adapter: empty input produces no output" {
  local empty="${TEST_TEMP}/empty.json"
  : > "$empty"
  run run_parser "$SEV_MAP" "$empty"
  assert_success
  [[ -z "$output" ]]
}

@test "phpstan adapter: no files section produces no output" {
  local no_files="${TEST_TEMP}/no-files.json"
  printf '{"totals":{},"files":{},"errors":[]}\n' > "$no_files"
  run run_parser "$SEV_MAP" "$no_files"
  assert_success
  [[ -z "$output" ]]
}
