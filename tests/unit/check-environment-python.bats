#!/usr/bin/env bats
# AC-1: shared/check_environment.py exists, emits identical JSON shape.
load '../helpers/test-helpers'

setup() {
  PY="$PLUGIN_ROOT/shared/check_environment.py"
}

@test "check_environment.py file exists" {
  assert [ -f "$PY" ]
}

@test "check_environment.py is executable" {
  assert [ -x "$PY" ]
}

@test "check_environment.py emits JSON with platform and tools keys" {
  run python3 "$PY"
  assert_success
  python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert 'platform' in d and 'tools' in d" "$output"
}

@test "check_environment.py tools entries have required fields" {
  run python3 "$PY"
  assert_success
  python3 -c "
import json, sys
d = json.loads(sys.argv[1])
required = {'name','available','version','tier','purpose','install'}
for t in d['tools']:
    missing = required - set(t)
    assert not missing, f'missing {missing} in {t}'
" "$output"
}

@test "check_environment.py reports bash/python3/git as required tier" {
  run python3 "$PY"
  assert_success
  python3 -c "
import json, sys
d = json.loads(sys.argv[1])
names = {t['name']: t['tier'] for t in d['tools']}
for n in ('bash','python3','git'):
    assert names.get(n) == 'required', f'{n} tier={names.get(n)}'
" "$output"
}

@test "check_environment.py reports a platform string in the known set" {
  run python3 "$PY"
  assert_success
  python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['platform'] in {'darwin','linux','wsl','gitbash','windows','unknown'}, d['platform']
" "$output"
}

@test "shared/check-environment.sh is deleted" {
  refute [ -f "$PLUGIN_ROOT/shared/check-environment.sh" ]
}
