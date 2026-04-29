#!/usr/bin/env bats
# AC-16: no emoji codepoints in new/modified Phase 1 files.
load '../helpers/test-helpers'

FILES=(
  install.sh
  install.ps1
  shared/check_environment.py
  hooks/_py/failure_log.py
  hooks/_py/progress.py
  tests/run-all.ps1
  tests/run-all.cmd
  tests/lib/derive_support_tiers.py
  docs/support-tiers.md
  shared/schemas/hook-failures.schema.json
  shared/schemas/progress-status.schema.json
  shared/schemas/run-history-trends.schema.json
)

@test "Phase 1 files contain no emoji codepoints" {
  for rel in "${FILES[@]}"; do
    f="$PLUGIN_ROOT/$rel"
    [ -f "$f" ] || continue
    run python3 -c "
import re, sys
p = sys.argv[1]
text = open(p, encoding='utf-8', errors='ignore').read()
bad = re.findall(r'[\U0001F100-\U0001FAFF\U00002600-\U000027BF]', text)
if bad: sys.exit(f'{p} has emoji: {bad[:5]}')
" "$f"
    [ "$status" -eq 0 ] || fail "$output"
  done
}
