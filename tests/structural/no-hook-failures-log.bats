#!/usr/bin/env bats
# AC-18: no stray references to the old filename remain.
load '../helpers/test-helpers'

@test "no stale hook-failures log-suffix references in tracked docs/code" {
  cd "$PLUGIN_ROOT"
  hits=$(grep -rn '\.hook-failures\.log' \
    --include='*.md' --include='*.json' --include='*.py' \
    --include='*.sh' --include='*.ps1' --include='*.cmd' \
    --include='*.bats' \
    --exclude-dir=.venv --exclude-dir=.git --exclude-dir=.forge \
    --exclude-dir=specs --exclude-dir=plans \
    . 2>/dev/null || true)
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits"
    fail "found stale hook-failures log-suffix references"
  fi
}
