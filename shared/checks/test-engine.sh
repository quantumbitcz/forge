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
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT
mkdir -p "$TMPDIR/src/main/kotlin/core/domain"
mkdir -p "$TMPDIR/src/test/kotlin"
mkdir -p "$TMPDIR/build/generated-sources"

# Test 1: Kotlin file with antipatterns
echo "--- Test 1: Kotlin antipatterns ---"
cat > "$TMPDIR/src/main/kotlin/core/domain/Bad.kt" << 'EOF'
package cz.quantumbit.wellplanned.core.domain

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

OUTPUT=$(TOOL_INPUT="{\"file_path\": \"$TMPDIR/src/main/kotlin/core/domain/Bad.kt\"}" \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$PLUGIN_ROOT/shared/checks/engine.sh" --hook 2>/dev/null || true)

assert_output "Non-null assertion detected" "QUAL-NULL" "$OUTPUT"
assert_output "Blocking call detected" "PERF-BLOCK" "$OUTPUT"
assert_output "Console output detected" "CONV-LOG" "$OUTPUT"
assert_output "Generic exception detected" "QUAL-EXCEPT" "$OUTPUT"
assert_output "Framework import boundary" "ARCH-BOUNDARY" "$OUTPUT"

# Test 2: Non-Kotlin file (should be silent)
echo "--- Test 2: Non-code file ---"
touch "$TMPDIR/readme.md"
OUTPUT=$(TOOL_INPUT="{\"file_path\": \"$TMPDIR/readme.md\"}" \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$PLUGIN_ROOT/shared/checks/engine.sh" --hook 2>/dev/null || true)
assert_silent "Non-code file skipped" "$OUTPUT"

# Test 3: Generated source (should be silent)
echo "--- Test 3: Generated source ---"
cat > "$TMPDIR/build/generated-sources/Gen.kt" << 'EOF'
class Generated { val x = something!! }
EOF
OUTPUT=$(TOOL_INPUT="{\"file_path\": \"$TMPDIR/build/generated-sources/Gen.kt\"}" \
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
  bash "$PLUGIN_ROOT/shared/checks/engine.sh" --hook 2>/dev/null || true)
assert_silent "Generated source skipped" "$OUTPUT"

# Test 4: Test file — main-scoped rules should NOT fire
echo "--- Test 4: Test file scope ---"
cat > "$TMPDIR/src/test/kotlin/TestFile.kt" << 'EOF'
class TestFile {
    fun testSomething() {
        println("test output ok")
        Thread.sleep(100) // ok in tests? depends on scope
    }
}
EOF
OUTPUT=$(TOOL_INPUT="{\"file_path\": \"$TMPDIR/src/test/kotlin/TestFile.kt\"}" \
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

# Test 6: Verify mode stub
echo "--- Test 6: Verify mode stub ---"
OUTPUT=$(bash "$PLUGIN_ROOT/shared/checks/engine.sh" --verify --project-root "$TMPDIR" 2>&1 || true)
assert_output "Verify mode responds" "Layer 2" "$OUTPUT"

# Summary
echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
