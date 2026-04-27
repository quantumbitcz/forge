#!/usr/bin/env bats
# AC-17: new Phase 1 Python files construct paths via pathlib.
load '../helpers/test-helpers'

PY_FILES=(
  shared/check_environment.py
  hooks/_py/failure_log.py
  hooks/_py/progress.py
  tests/lib/derive_support_tiers.py
)

@test "Phase 1 Python code uses pathlib not hardcoded separators" {
  for rel in "${PY_FILES[@]}"; do
    f="$PLUGIN_ROOT/$rel"
    [ -f "$f" ] || continue
    run python3 -c "
import ast, re, sys
src = open(sys.argv[1], encoding='utf-8').read()
# allow / inside regex patterns, URLs, comments, docstrings
stripped = re.sub(r'\"[^\"]*\"|\'[^\']*\'|#.*$', '', src, flags=re.M)
# We only flag literal string containing '/' or '\\\\' that look like path segments
bad = re.findall(r\"'[^']*[\\\\\\/][^']*\\.(py|md|json|sh|jsonl)'\", src)
if bad:
    sys.exit(f'{sys.argv[1]} has hardcoded-path literals: {bad}')
if 'from pathlib import Path' not in src and 'pathlib.Path' not in src:
    sys.exit(f'{sys.argv[1]} does not import pathlib')
" "$f"
    [ "$status" -eq 0 ] || fail "$output"
  done
}
