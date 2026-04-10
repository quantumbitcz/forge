#!/usr/bin/env bats
# Unit tests: shared/checks/engine.py — Python check engine entry point.

load '../helpers/test-helpers'

ENGINE_PY="$PLUGIN_ROOT/shared/checks/engine.py"

# ---------------------------------------------------------------------------
# 1. File exists and has shebang
# ---------------------------------------------------------------------------

@test "engine.py: file exists" {
  [[ -f "$ENGINE_PY" ]]
}

@test "engine.py: has python3 shebang" {
  local first_line
  first_line=$(head -1 "$ENGINE_PY")
  [[ "$first_line" == "#!/usr/bin/env python3" ]]
}

@test "engine.py: is executable" {
  [[ -x "$ENGINE_PY" ]]
}

# ---------------------------------------------------------------------------
# 2. Language detection
# ---------------------------------------------------------------------------

@test "engine.py: detects kotlin from .kt extension" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import detect_language
assert detect_language('src/main/kotlin/App.kt') == 'kotlin', 'Expected kotlin'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: detects typescript from .ts extension" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import detect_language
assert detect_language('src/index.ts') == 'typescript', 'Expected typescript'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: detects python from .py extension" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import detect_language
assert detect_language('app/main.py') == 'python', 'Expected python'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: returns None for unknown extension" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import detect_language
assert detect_language('README.md') is None, 'Expected None'
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# 3. Arg parsing
# ---------------------------------------------------------------------------

@test "engine.py: parses --hook mode" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import parse_args
args = parse_args(['--hook', '--files-changed', 'test.kt'])
assert args['mode'] == 'hook', f'Expected hook, got {args[\"mode\"]}'
assert args['files_changed'] == ['test.kt'], f'Expected [test.kt], got {args[\"files_changed\"]}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: parses --verify mode with multiple files" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import parse_args
args = parse_args(['--verify', '--files-changed', 'a.ts', '--files-changed', 'b.py'])
assert args['mode'] == 'verify', f'Expected verify, got {args[\"mode\"]}'
assert args['files_changed'] == ['a.ts', 'b.py'], f'Got {args[\"files_changed\"]}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: parses --project-root" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import parse_args
args = parse_args(['--project-root', '/tmp/myproject', '--hook'])
assert args['project_root'] == '/tmp/myproject', f'Got {args[\"project_root\"]}'
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# 4. Never blocks pipeline (exit 0 on all errors)
# ---------------------------------------------------------------------------

@test "engine.py: exits 0 with no files" {
  run python3 "$ENGINE_PY" --hook
  assert_success
}

@test "engine.py: exits 0 with nonexistent project root" {
  run python3 "$ENGINE_PY" --hook --project-root /nonexistent/path --files-changed test.kt
  assert_success
}
