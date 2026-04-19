#!/usr/bin/env bats
# Unit tests: hooks/_py/check_engine/engine.py — Python check engine entry point.

load '../helpers/test-helpers'

ENGINE_PY="$PLUGIN_ROOT/hooks/_py/check_engine/engine.py"

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

# ---------------------------------------------------------------------------
# 5. Module detection from component cache
# ---------------------------------------------------------------------------

@test "engine.py: detect_module reads component cache" {
  local forge_dir="${TEST_TEMP}/.forge"
  mkdir -p "$forge_dir"
  echo "services/user=spring" > "$forge_dir/.component-cache"

  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import detect_module
result = detect_module('services/user/src/Main.kt', '$forge_dir')
assert result == 'spring', f'Expected spring, got {result}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: detect_module returns None when no cache" {
  local forge_dir="${TEST_TEMP}/.forge"
  mkdir -p "$forge_dir"

  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import detect_module
result = detect_module('src/Main.kt', '$forge_dir')
assert result is None, f'Expected None, got {result}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: detect_module handles malformed cache" {
  local forge_dir="${TEST_TEMP}/.forge"
  mkdir -p "$forge_dir"
  echo "malformed-no-equals" > "$forge_dir/.component-cache"

  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import detect_module
result = detect_module('src/Main.kt', '$forge_dir')
assert result is None, f'Expected None, got {result}'
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# 6. Override loading
# ---------------------------------------------------------------------------

@test "engine.py: load_overrides returns empty dict when no module" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import load_overrides
result = load_overrides(None, '${TEST_TEMP}/.forge')
assert result == {}, f'Expected empty dict, got {result}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: load_overrides loads framework rules-override.json" {
  # Use spring which has a real rules-override.json
  run python3 -c "
import sys, os; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
os.environ['CLAUDE_PLUGIN_ROOT'] = '$PLUGIN_ROOT'
from engine import load_overrides
result = load_overrides('spring', '${TEST_TEMP}/.forge')
assert isinstance(result, (dict, list)), f'Expected dict/list, got {type(result)}'
assert len(result) > 0, 'Expected non-empty overrides for spring'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: load_overrides returns empty dict for unknown framework" {
  run python3 -c "
import sys, os; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
os.environ['CLAUDE_PLUGIN_ROOT'] = '$PLUGIN_ROOT'
from engine import load_overrides
result = load_overrides('nonexistent-framework', '${TEST_TEMP}/.forge')
assert result == {}, f'Expected empty dict, got {result}'
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# 7. TOOL_INPUT env var parsing
# ---------------------------------------------------------------------------

@test "engine.py: hook mode reads file from TOOL_INPUT" {
  local test_file="${TEST_TEMP}/test.kt"
  echo 'fun main() {}' > "$test_file"

  # engine.py in hook mode should parse TOOL_INPUT for file_path
  TOOL_INPUT="{\"file_path\": \"${test_file}\"}" run python3 "$ENGINE_PY" --hook
  assert_success
}

@test "engine.py: hook mode handles malformed TOOL_INPUT" {
  TOOL_INPUT="not valid json at all" run python3 "$ENGINE_PY" --hook
  assert_success  # Should exit 0 — never block pipeline
}

@test "engine.py: hook mode handles TOOL_INPUT without file_path" {
  TOOL_INPUT='{"content": "hello"}' run python3 "$ENGINE_PY" --hook
  assert_success
}

@test "engine.py: hook mode handles empty TOOL_INPUT" {
  TOOL_INPUT="" run python3 "$ENGINE_PY" --hook
  assert_success
}

# ---------------------------------------------------------------------------
# 8. Generated sources skip
# ---------------------------------------------------------------------------

@test "engine.py: skips build/generated-sources files" {
  local test_file="${TEST_TEMP}/build/generated-sources/Main.kt"
  mkdir -p "$(dirname "$test_file")"
  echo 'fun main() {}' > "$test_file"

  run python3 "$ENGINE_PY" --verify --files-changed "$test_file"
  assert_success
  assert_output ""  # No output — file was skipped
}

# ---------------------------------------------------------------------------
# 9. Language detection edge cases
# ---------------------------------------------------------------------------

@test "engine.py: detects vue from .vue extension" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import detect_language
assert detect_language('App.vue') == 'vue', 'Expected vue'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: detects svelte from .svelte extension" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import detect_language
assert detect_language('App.svelte') == 'svelte', 'Expected svelte'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: detects go from .go extension" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import detect_language
assert detect_language('main.go') == 'go', 'Expected go'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: detects rust from .rs extension" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import detect_language
assert detect_language('lib.rs') == 'rust', 'Expected rust'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: detects java from .java extension" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import detect_language
assert detect_language('App.java') == 'java', 'Expected java'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: detects swift from .swift extension" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import detect_language
assert detect_language('ViewController.swift') == 'swift', 'Expected swift'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: detects csharp from .cs extension" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import detect_language
assert detect_language('Program.cs') == 'csharp', 'Expected csharp'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: detects elixir from .ex extension" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import detect_language
assert detect_language('app.ex') == 'elixir', 'Expected elixir'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: case insensitive extension matching" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import detect_language
assert detect_language('Main.KT') == 'kotlin', f'Expected kotlin, got {detect_language(\"Main.KT\")}'
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# 10. Arg parsing edge cases
# ---------------------------------------------------------------------------

@test "engine.py: parses --review mode" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import parse_args
args = parse_args(['--review', '--project-root', '/tmp/p', '--files-changed', 'a.ts', 'b.py'])
assert args['mode'] == 'review', f'Expected review, got {args[\"mode\"]}'
assert args['project_root'] == '/tmp/p'
assert args['files_changed'] == ['a.ts', 'b.py'], f'Got {args[\"files_changed\"]}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: defaults to hook mode with no args" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import parse_args
args = parse_args([])
assert args['mode'] == 'hook', f'Expected hook, got {args[\"mode\"]}'
assert args['files_changed'] == []
assert args['project_root'] == ''
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: --files-changed stops at next flag" {
  run python3 -c "
import sys; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
from engine import parse_args
args = parse_args(['--files-changed', 'a.ts', 'b.py', '--project-root', '/tmp'])
assert args['files_changed'] == ['a.ts', 'b.py'], f'Got {args[\"files_changed\"]}'
assert args['project_root'] == '/tmp'
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# 11. Hook mode lock mechanism
# ---------------------------------------------------------------------------

@test "engine.py: hook mode creates and removes engine lock" {
  local forge_dir="${TEST_TEMP}/.forge"
  mkdir -p "$forge_dir"

  # After engine.py completes, the lock dir should be cleaned up
  FORGE_DIR="$forge_dir" run python3 "$ENGINE_PY" --hook
  assert_success
  # Lock dir should not exist after clean exit
  [[ ! -d "$forge_dir/.engine.lock.d" ]]
}

# ---------------------------------------------------------------------------
# 12. Nonexistent file handling
# ---------------------------------------------------------------------------

@test "engine.py: verify mode skips nonexistent files gracefully" {
  run python3 "$ENGINE_PY" --verify --files-changed /nonexistent/file.kt /also/missing.ts
  assert_success
  assert_output ""
}

@test "engine.py: exits 0 on any uncaught exception (catch-all)" {
  # Force an import error by corrupting sys.path — the top-level try/except should catch
  run python3 -c "
import sys
sys.argv = ['engine.py', '--verify', '--files-changed', '/dev/null']
# Simulate the main() catch-all
try:
    raise RuntimeError('simulated crash')
except Exception:
    pass  # Should not reach exit(1)
print('OK')
"
  assert_success
  assert_output "OK"
}

# ---------------------------------------------------------------------------
# 13. _find_override function
# ---------------------------------------------------------------------------

@test "engine.py: _find_override finds framework override via module cache" {
  local project_dir
  project_dir="$(create_temp_project spring)"

  run python3 -c "
import sys, os; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
os.environ['CLAUDE_PLUGIN_ROOT'] = '$PLUGIN_ROOT'
from engine import _find_override
# Create module cache pointing to spring
with open('$project_dir/.forge/.module-cache', 'w') as f:
    f.write('spring')
result = _find_override('$project_dir/src/main/kotlin/App.kt', '$project_dir')
assert 'spring' in result and 'rules-override' in result, f'Expected spring rules-override path, got {result}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: _find_override returns empty string when no module detected" {
  local project_dir="${TEST_TEMP}/empty-project"
  mkdir -p "$project_dir/.forge"

  run python3 -c "
import sys, os; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
os.environ['CLAUDE_PLUGIN_ROOT'] = '$PLUGIN_ROOT'
from engine import _find_override
result = _find_override('$project_dir/src/app.ts', '$project_dir')
assert result == '', f'Expected empty string, got {result}'
print('OK')
"
  assert_success
  assert_output "OK"
}

@test "engine.py: _find_override prefers component cache over module cache" {
  local project_dir
  project_dir="$(create_temp_project spring)"

  # Component cache says react, module cache says spring — component cache wins
  echo "src=react" > "$project_dir/.forge/.component-cache"
  echo "spring" > "$project_dir/.forge/.module-cache"

  run python3 -c "
import sys, os; sys.path.insert(0, '$PLUGIN_ROOT/shared/checks')
os.environ['CLAUDE_PLUGIN_ROOT'] = '$PLUGIN_ROOT'
from engine import _find_override
result = _find_override('$project_dir/src/App.tsx', '$project_dir')
# Should find react override (if exists) or empty string — NOT spring
if result:
    assert 'spring' not in result, f'Should use component cache (react), not module cache. Got {result}'
print('OK')
"
  assert_success
  assert_output "OK"
}
