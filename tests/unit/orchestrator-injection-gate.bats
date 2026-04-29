#!/usr/bin/env bats
# orchestrator-injection-gate.sh decisions.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMP="$(mktemp -d)"
  export FORGE_DIR="$TMP/.forge"
  mkdir -p "$FORGE_DIR"
}

teardown() { rm -rf "$TMP"; }

@test "gate: non-confirmed tier + Bash tool → allow (no alert)" {
  run bash "$ROOT/shared/orchestrator-injection-gate.sh" \
    --tier logged --has-bash true --autonomous true --forge-dir "$FORGE_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$FORGE_DIR/alerts.json" ]
}

@test "gate: confirmed tier + no Bash → allow (no alert)" {
  run bash "$ROOT/shared/orchestrator-injection-gate.sh" \
    --tier confirmed --has-bash false --autonomous true --forge-dir "$FORGE_DIR"
  [ "$status" -eq 0 ]
  [ ! -f "$FORGE_DIR/alerts.json" ]
}

@test "gate: confirmed + Bash + autonomous → writes alerts.json and pauses" {
  run bash "$ROOT/shared/orchestrator-injection-gate.sh" \
    --tier confirmed --has-bash true --autonomous true --forge-dir "$FORGE_DIR" \
    --agent fg-020-bug-investigator --source mcp:playwright
  [ "$status" -ne 0 ]
  [ -f "$FORGE_DIR/alerts.json" ]
  run python3 - "$FORGE_DIR/alerts.json" <<'PYEOF'
import json, sys
a = json.load(open(sys.argv[1]))
assert a['severity'] == 'high'
assert a['reason'] == 'T-C + Bash dispatch blocked'
assert a['agent'] == 'fg-020-bug-investigator'
assert a['source'] == 'mcp:playwright'
PYEOF
  [ "$status" -eq 0 ]
}

@test "gate: confirmed + Bash + interactive → returns 3 (programming error)" {
  run bash "$ROOT/shared/orchestrator-injection-gate.sh" \
    --tier confirmed --has-bash true --autonomous false --forge-dir "$FORGE_DIR"
  [ "$status" -eq 3 ]
}

@test "gate: unknown arg → exit 2" {
  run bash "$ROOT/shared/orchestrator-injection-gate.sh" --unknown-flag
  [ "$status" -eq 2 ]
}
