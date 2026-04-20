#!/usr/bin/env bats
# Phase 08: asserts modules/languages/swift.md contains the 8 structured-concurrency subsections.

PLUGIN_ROOT="${BATS_TEST_DIRNAME}/../.."
SWIFT_FILE="$PLUGIN_ROOT/modules/languages/swift.md"

@test "swift.md exists" {
  [ -f "$SWIFT_FILE" ]
}

@test "swift.md contains all 8 concurrency subsections" {
  for header in \
    "### Task basics" \
    "### TaskGroup and async let" \
    "### Structured vs unstructured concurrency" \
    "### Actor isolation" \
    "### Sendable and data-race safety" \
    "### AsyncSequence / AsyncStream" \
    "### Bridging legacy callbacks" \
    "### Concurrency anti-patterns"; do
      grep -qF "$header" "$SWIFT_FILE" || {
        echo "missing header: $header"
        return 1
      }
  done
}

@test "swift.md line count is within 280-350 (target ~315)" {
  local lines
  lines=$(wc -l < "$SWIFT_FILE")
  [ "$lines" -ge 280 ]
  [ "$lines" -le 350 ]
}
