#!/usr/bin/env bats
# Contract tests: shared/modes/ — validates mode overlay files.

load '../helpers/test-helpers'

MODES_DIR="$PLUGIN_ROOT/shared/modes"

# ---------------------------------------------------------------------------
# 1. All 7 mode files exist
# ---------------------------------------------------------------------------

@test "mode-overlays: all 7 mode files exist" {
  for mode in standard bugfix migration bootstrap testing refactor performance; do
    assert [ -f "$MODES_DIR/${mode}.md" ]
  done
}

# ---------------------------------------------------------------------------
# 2. Each has valid YAML frontmatter with mode field
# ---------------------------------------------------------------------------

@test "mode-overlays: each file has YAML frontmatter with mode field" {
  for mode in standard bugfix migration bootstrap testing refactor performance; do
    local file="$MODES_DIR/${mode}.md"
    # Check frontmatter delimiters
    local first_line
    first_line=$(head -1 "$file")
    assert_equal "$first_line" "---"

    # Check mode field exists and matches filename
    grep -q "^mode: ${mode}$" "$file" || fail "${mode}.md missing 'mode: ${mode}' in frontmatter"
  done
}

# ---------------------------------------------------------------------------
# 3. Each mode field matches filename
# ---------------------------------------------------------------------------

@test "mode-overlays: mode field matches filename" {
  for mode in standard bugfix migration bootstrap testing refactor performance; do
    local declared
    declared=$(grep "^mode:" "$MODES_DIR/${mode}.md" | head -1 | awk '{print $2}')
    assert_equal "$declared" "$mode"
  done
}

# ---------------------------------------------------------------------------
# 4. stages keys are valid stage names
# ---------------------------------------------------------------------------

@test "mode-overlays: stages keys are valid stage names" {
  local valid_stages="explore plan validate implement review ship docs learn"
  for mode in standard bugfix migration bootstrap testing refactor performance; do
    local file="$MODES_DIR/${mode}.md"
    # Extract stage keys from frontmatter (lines between --- delimiters that start with 2-space indent under stages:)
    python3 -c "
import sys, re
with open('$file') as f:
    content = f.read()
# Extract frontmatter
m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
if not m:
    sys.exit(0)  # No frontmatter = OK (standard has empty stages)
fm = m.group(1)
# Find stage keys (lines with exactly 2 spaces indent under stages:)
in_stages = False
for line in fm.split('\n'):
    if line.strip() == 'stages: {}':
        break
    if line.strip() == 'stages:':
        in_stages = True
        continue
    if in_stages and re.match(r'^  [a-z]', line):
        key = line.strip().rstrip(':')
        valid = '$valid_stages'.split()
        if key not in valid:
            print(f'ERROR: {key} is not a valid stage name in ${mode}.md', file=sys.stderr)
            sys.exit(1)
    elif in_stages and not line.startswith('  '):
        in_stages = False
"
  done
}

# ---------------------------------------------------------------------------
# 5. Referenced agents exist
# ---------------------------------------------------------------------------

@test "mode-overlays: referenced agents exist in agents/ directory" {
  for mode in bugfix migration bootstrap testing refactor performance; do
    local file="$MODES_DIR/${mode}.md"
    # Extract agent references (fg-NNN-name pattern)
    local agents
    agents=$(grep -oE 'fg-[0-9]+-[a-z-]+' "$file" | sort -u)
    for agent in $agents; do
      # Check if agent file exists (could be in agents/ directory)
      if [[ ! -f "$PLUGIN_ROOT/agents/${agent}.md" ]]; then
        fail "Agent ${agent} referenced in ${mode}.md does not exist"
      fi
    done
  done
}
