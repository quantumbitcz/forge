#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0

assert_output() {
  local test_name="$1" expected="$2" actual="$3"
  if echo "$actual" | grep -q "$expected"; then
    echo "  PASS: $test_name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (expected '$expected' in output)"
    echo "  Got: $actual"
    FAIL=$((FAIL + 1))
  fi
}

assert_silent() {
  local test_name="$1" actual="$2"
  if [ -z "$actual" ]; then
    echo "  PASS: $test_name (silent)"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $test_name (expected silent, got output)"
    echo "  Got: $actual"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Check Engine Integration Tests ==="

# Setup: temp project with realistic directory structure
TEST_TMPDIR=$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/forge-test.XXXXXX")
trap 'rm -rf "$TEST_TMPDIR"' EXIT
mkdir -p "$TEST_TMPDIR/src/main/kotlin/core/domain"
mkdir -p "$TEST_TMPDIR/src/test/kotlin"
mkdir -p "$TEST_TMPDIR/build/generated-sources"

# Test 1: Kotlin file with antipatterns
echo "--- Test 1: Kotlin antipatterns ---"
cat > "$TEST_TMPDIR/src/main/kotlin/core/domain/Bad.kt" << 'EOF'
package com.example.core.domain

import java.util.UUID
import org.springframework.data.annotation.Id

class TestDomain {
    val id = UUID.randomUUID()!!
    fun doWork() {
        Thread.sleep(1000)
        println("debug")
        throw RuntimeException("oops")
    }
}
EOF

OUTPUT=$(TOOL_INPUT="{\"file_path\": \"$TEST_TMPDIR/src/main/kotlin/core/domain/Bad.kt\"}" \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$PLUGIN_ROOT/shared/checks/engine.sh" --hook 2>/dev/null || true)

assert_output "Non-null assertion detected" "QUAL-NULL" "$OUTPUT"
assert_output "Blocking call detected" "PERF-BLOCK" "$OUTPUT"
assert_output "Console output detected" "CONV-LOG" "$OUTPUT"
assert_output "Generic exception detected" "QUAL-EXCEPT" "$OUTPUT"
assert_output "Framework import boundary" "ARCH-BOUNDARY" "$OUTPUT"

# Test 2: Non-Kotlin file (should be silent)
echo "--- Test 2: Non-code file ---"
touch "$TEST_TMPDIR/readme.md"
OUTPUT=$(TOOL_INPUT="{\"file_path\": \"$TEST_TMPDIR/readme.md\"}" \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$PLUGIN_ROOT/shared/checks/engine.sh" --hook 2>/dev/null || true)
assert_silent "Non-code file skipped" "$OUTPUT"

# Test 3: Generated source (should be silent)
echo "--- Test 3: Generated source ---"
cat > "$TEST_TMPDIR/build/generated-sources/Gen.kt" << 'EOF'
class Generated { val x = something!! }
EOF
OUTPUT=$(TOOL_INPUT="{\"file_path\": \"$TEST_TMPDIR/build/generated-sources/Gen.kt\"}" \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$PLUGIN_ROOT/shared/checks/engine.sh" --hook 2>/dev/null || true)
assert_silent "Generated source skipped" "$OUTPUT"

# Test 4: Test file — main-scoped rules should NOT fire
echo "--- Test 4: Test file scope ---"
cat > "$TEST_TMPDIR/src/test/kotlin/TestFile.kt" << 'EOF'
class TestFile {
    fun testSomething() {
        println("test output ok")
        Thread.sleep(100) // ok in tests? depends on scope
    }
}
EOF
OUTPUT=$(TOOL_INPUT="{\"file_path\": \"$TEST_TMPDIR/src/test/kotlin/TestFile.kt\"}" \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$PLUGIN_ROOT/shared/checks/engine.sh" --hook 2>/dev/null || true)
# println has scope: main, should NOT fire for test files
# Thread.sleep has scope: main, should NOT fire for test files
assert_silent "main-scoped rules skipped for test file" "$OUTPUT"

# Test 5: Nonexistent file (should be silent)
echo "--- Test 5: Nonexistent file ---"
OUTPUT=$(TOOL_INPUT='{"file_path": "/tmp/does-not-exist.kt"}' \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$PLUGIN_ROOT/shared/checks/engine.sh" --hook 2>/dev/null || true)
assert_silent "Nonexistent file skipped" "$OUTPUT"

# Test 6: Verify mode with a file
echo "--- Test 6: Verify mode with file ---"
OUTPUT=$(CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$PLUGIN_ROOT/shared/checks/engine.sh" --verify \
  --project-root "$TEST_TMPDIR" \
  --files-changed "$TEST_TMPDIR/src/main/kotlin/core/domain/Bad.kt" 2>/dev/null || true)
assert_output "Verify mode finds antipatterns" "QUAL-NULL" "$OUTPUT"

# Summary
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
