#!/usr/bin/env bats
# Tests for shared/check-environment.sh

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/check-environment.sh"

@test "check-environment: script exists and is executable" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

@test "check-environment: exits 0 always" {
  run bash "$SCRIPT"
  assert_success
}

@test "check-environment: outputs valid JSON" {
  run bash "$SCRIPT"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'platform' in d; assert 'tools' in d"
}

@test "check-environment: reports bash as required and available" {
  run bash "$SCRIPT"
  assert_success
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
bash_entry = [t for t in d['tools'] if t['name'] == 'bash'][0]
assert bash_entry['available'] == True, 'bash should be available'
assert bash_entry['tier'] == 'required', 'bash should be required tier'
assert len(bash_entry['version']) > 0, 'bash version should be non-empty'
"
}

@test "check-environment: reports platform field" {
  run bash "$SCRIPT"
  assert_success
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['platform'] in ('darwin', 'linux', 'windows', 'wsl', 'gitbash', 'unknown'), f\"unexpected platform: {d['platform']}\"
"
}

@test "check-environment: includes jq in recommended tier" {
  run bash "$SCRIPT"
  assert_success
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
jq_entries = [t for t in d['tools'] if t['name'] == 'jq']
assert len(jq_entries) == 1, 'jq should appear exactly once'
assert jq_entries[0]['tier'] == 'recommended'
"
}

@test "check-environment: includes docker in recommended tier" {
  run bash "$SCRIPT"
  assert_success
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
docker_entries = [t for t in d['tools'] if t['name'] == 'docker']
assert len(docker_entries) == 1
assert docker_entries[0]['tier'] == 'recommended'
"
}

@test "check-environment: includes sqlite3 in recommended tier" {
  run bash "$SCRIPT"
  assert_success
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
sqlite_entries = [t for t in d['tools'] if t['name'] == 'sqlite3']
assert len(sqlite_entries) == 1
assert sqlite_entries[0]['tier'] == 'recommended'
"
}

@test "check-environment: provides install hints for unavailable recommended tools" {
  run bash "$SCRIPT"
  assert_success
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for t in d['tools']:
    if t['tier'] == 'recommended' and not t['available']:
        assert len(t['install']) > 0, f\"missing install hint for {t['name']}\"
"
}

@test "check-environment: JSON output is safe (round-trip parseable)" {
  run bash "$SCRIPT"
  assert_success
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
json.loads(json.dumps(d))
"
}
