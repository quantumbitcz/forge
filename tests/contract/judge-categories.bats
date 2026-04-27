#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  REG="$PROJECT_ROOT/shared/checks/category-registry.json"
}

@test "REFLECT categories owned by fg-301-implementer-judge (not -critic)" {
  run grep -F 'fg-301-implementer-critic' "$REG"
  [ "$status" -ne 0 ]
  run grep -F 'fg-301-implementer-judge' "$REG"
  [ "$status" -eq 0 ]
}

@test "JUDGE-TIMEOUT category exists with INFO severity default" {
  run python3 -c "
import json
r = json.load(open('$REG'))
c = r['categories']['JUDGE-TIMEOUT']
assert c['severity'] == 'INFO', c
print('OK')
"
  [ "$status" -eq 0 ]
}
