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
  # Pass the registry path via argv so Windows-native Python never sees
  # backslashes inside a string literal (which it would interpret as escapes).
  run python3 - "$REG" <<'PYEOF'
import json, sys
r = json.load(open(sys.argv[1]))
c = r['categories']['JUDGE-TIMEOUT']
assert c['severity'] == 'INFO', c
print('OK')
PYEOF
  [ "$status" -eq 0 ]
}
