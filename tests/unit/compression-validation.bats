#!/usr/bin/env bats
# Unit tests for shared/compression-validation.py

load '../helpers/test-helpers'

VALIDATION_SCRIPT="$PLUGIN_ROOT/shared/compression-validation.py"

@test "compression-validation: script exists" {
  [[ -f "$VALIDATION_SCRIPT" ]]
}

@test "compression-validation: heading count mismatch detected" {
  printf '# Heading 1\n## Heading 2\nBody text\n' > "$TEST_TEMP/original.md"
  printf '# Heading 1\nBody text\n' > "$TEST_TEMP/compressed.md"
  run python3 "$VALIDATION_SCRIPT" "$TEST_TEMP/original.md" "$TEST_TEMP/compressed.md"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"heading_count"* ]]
}

@test "compression-validation: code block mutation detected" {
  printf '# Test\n\n```python\ndef foo():\n    return 42\n```\n' > "$TEST_TEMP/original.md"
  printf '# Test\n\n```python\ndef foo():\n    return 43\n```\n' > "$TEST_TEMP/compressed.md"
  run python3 "$VALIDATION_SCRIPT" "$TEST_TEMP/original.md" "$TEST_TEMP/compressed.md"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"code_blocks"* ]]
}

@test "compression-validation: URL preservation validated" {
  printf 'See https://example.com/docs for details\n' > "$TEST_TEMP/original.md"
  printf 'See docs for details\n' > "$TEST_TEMP/compressed.md"
  run python3 "$VALIDATION_SCRIPT" "$TEST_TEMP/original.md" "$TEST_TEMP/compressed.md"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"urls"* ]]
}

@test "compression-validation: clean file passes" {
  printf '# Test\n\nSome prose text here.\n\n```python\ncode()\n```\n' > "$TEST_TEMP/original.md"
  printf '# Test\n\nProse text.\n\n```python\ncode()\n```\n' > "$TEST_TEMP/compressed.md"
  run python3 "$VALIDATION_SCRIPT" "$TEST_TEMP/original.md" "$TEST_TEMP/compressed.md"
  [[ "$status" -eq 0 ]]
}

@test "compression-validation: bullet drift warns but passes" {
  # Original: 10 bullets, Compressed: 8 bullets (20% drift > 15% threshold)
  printf '# List\n- a\n- b\n- c\n- d\n- e\n- f\n- g\n- h\n- i\n- j\n' > "$TEST_TEMP/original.md"
  printf '# List\n- a\n- b\n- c\n- d\n- e\n- f\n- g\n- h\n' > "$TEST_TEMP/compressed.md"
  run python3 "$VALIDATION_SCRIPT" "$TEST_TEMP/original.md" "$TEST_TEMP/compressed.md"
  [[ "$status" -eq 2 ]]  # WARN, not FAIL
}

@test "compression-validation: frontmatter mutation detected" {
  printf -- '---\nname: fg-410\ndescription: Code reviewer\n---\nBody\n' > "$TEST_TEMP/original.md"
  printf -- '---\nname: fg-410\ndescription: Reviewer\n---\nBody\n' > "$TEST_TEMP/compressed.md"
  run python3 "$VALIDATION_SCRIPT" "$TEST_TEMP/original.md" "$TEST_TEMP/compressed.md"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"frontmatter"* ]]
}

@test "compression-validation: table mutation detected" {
  printf '# Scores\n\n| Level | Name |\n|---|---|\n| 0 | verbose |\n| 1 | standard |\n' > "$TEST_TEMP/original.md"
  printf '# Scores\n\n| Level | Name |\n|---|---|\n| 0 | verbose |\n| 1 | std |\n' > "$TEST_TEMP/compressed.md"
  run python3 "$VALIDATION_SCRIPT" "$TEST_TEMP/original.md" "$TEST_TEMP/compressed.md"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"tables"* ]]
}

@test "compression-validation: heading text mismatch detected" {
  printf '# Authentication Module\n## Error Handling\nBody\n' > "$TEST_TEMP/original.md"
  printf '# Security Module\n## Error Handling\nBody\n' > "$TEST_TEMP/compressed.md"
  run python3 "$VALIDATION_SCRIPT" "$TEST_TEMP/original.md" "$TEST_TEMP/compressed.md"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"heading_text"* ]]
}

@test "compression-validation: file path drift warns" {
  printf 'See shared/output-compression.md for details\n' > "$TEST_TEMP/original.md"
  printf 'See details\n' > "$TEST_TEMP/compressed.md"
  run python3 "$VALIDATION_SCRIPT" "$TEST_TEMP/original.md" "$TEST_TEMP/compressed.md"
  # File paths are WARN severity, so exit code 2
  [[ "$status" -eq 2 ]]
  [[ "$output" == *"file_paths"* ]]
}

@test "compression-validation: check-only mode validates structure" {
  printf '# Valid\n\n```python\ncode()\n```\n' > "$TEST_TEMP/valid.md"
  run python3 "$VALIDATION_SCRIPT" --check-only "$TEST_TEMP/valid.md"
  [[ "$status" -eq 0 ]]
}

@test "compression-validation: check-only detects unclosed fence" {
  printf '# Bad\n\n```python\ncode()\n' > "$TEST_TEMP/bad.md"
  run python3 "$VALIDATION_SCRIPT" --check-only "$TEST_TEMP/bad.md"
  [[ "$status" -eq 1 ]]
}

@test "compression-validation: outputs valid JSON" {
  printf '# Test\nBody\n' > "$TEST_TEMP/original.md"
  printf '# Test\nCompressed body\n' > "$TEST_TEMP/compressed.md"
  run python3 "$VALIDATION_SCRIPT" "$TEST_TEMP/original.md" "$TEST_TEMP/compressed.md"
  # Should be valid JSON (python3 -m json.tool succeeds)
  echo "$output" | python3 -m json.tool > /dev/null 2>&1
}
