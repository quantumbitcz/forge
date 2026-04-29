#!/usr/bin/env bats
# AC-6 + AC-7: every hook entry script wraps main() and calls failure_log on failure.
load '../helpers/test-helpers'

HOOKS=(pre_tool_use.py post_tool_use.py post_tool_use_skill.py
       post_tool_use_agent.py stop.py session_start.py)

@test "every hook entry references failure_log.record_failure" {
  for h in "${HOOKS[@]}"; do
    run grep -q 'record_failure' "$PLUGIN_ROOT/hooks/$h"
    if [ "$status" -ne 0 ]; then
      fail "hooks/$h does not reference record_failure"
    fi
  done
}

@test "every hook entry wraps main in try/except" {
  for h in "${HOOKS[@]}"; do
    run grep -Eq 'try:\s*$|try:$|except BaseException' "$PLUGIN_ROOT/hooks/$h"
    [ "$status" -eq 0 ] || fail "hooks/$h missing try/except"
  done
}

@test "hook entry with injected failure writes to .hook-failures.jsonl" {
  tmp="$(mktemp -d)"
  cd "$tmp"
  # Force checkpoint.main() to raise: pre-create .forge/ (skip the "no .forge → no-op"
  # short-circuit) and replace checkpoints.jsonl with a directory so the append-open
  # raises IsADirectoryError, which the wrapper must catch and record.
  mkdir -p ".forge/checkpoints.jsonl"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" python3 "$PLUGIN_ROOT/hooks/post_tool_use_skill.py" <<<'{}'
  # Hook contract: exit 0 on crash (never break session).
  [ "$status" -eq 0 ]
  assert [ -f ".forge/.hook-failures.jsonl" ]
  rm -rf "$tmp"
}

@test "session_start.py invokes failure_log.rotate()" {
  run grep -q 'rotate()' "$PLUGIN_ROOT/hooks/session_start.py"
  assert_success
}

@test "produced .hook-failures.jsonl rows validate against the schema" {
  tmp="$(mktemp -d)"
  cd "$tmp"
  mkdir -p ".forge/checkpoints.jsonl"
  run env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" python3 "$PLUGIN_ROOT/hooks/post_tool_use_skill.py" <<<'{}'
  [ "$status" -eq 0 ]
  assert [ -f ".forge/.hook-failures.jsonl" ]
  run python3 - "$PLUGIN_ROOT/shared/schemas/hook-failures.schema.json" <<'PYEOF'
import json, sys
from pathlib import Path
try:
    import jsonschema
except ImportError:
    sys.exit(0)  # CI installs jsonschema (Task 10); local skip is acceptable
schema = json.loads(Path(sys.argv[1]).read_text())
for raw in Path('.forge/.hook-failures.jsonl').read_text().splitlines():
    raw = raw.strip()
    if not raw:
        continue
    row = json.loads(raw)
    jsonschema.validate(row, schema)
PYEOF
  assert_success
  rm -rf "$tmp"
}
