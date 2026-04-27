#!/usr/bin/env bats
# AC-17: new Phase 1 Python files construct paths via pathlib.
load '../helpers/test-helpers'

PY_FILES=(
  shared/check_environment.py
  hooks/_py/failure_log.py
  hooks/_py/progress.py
  tests/lib/derive_support_tiers.py
  tests/mutation/state_transitions.py
  tests/scenario/report_coverage.py
  tests/e2e/dry-run-smoke.py
)

@test "Phase 1 Python code uses pathlib not hardcoded separators" {
  for rel in "${PY_FILES[@]}"; do
    f="$PLUGIN_ROOT/$rel"
    [ -f "$f" ] || continue
    run python3 - "$f" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    src = fh.read()

# Allow '/' inside legitimate uses: comments, raw strings (regex patterns),
# URL string literals, and triple-quoted docstrings. Strip those so the
# bad-path scan only sees ordinary string literals.
stripped = src
stripped = re.sub(r'(?s)""".*?"""', "", stripped)               # triple-double docstrings
stripped = re.sub(r"(?s)'''.*?'''", "", stripped)               # triple-single docstrings
stripped = re.sub(r"#.*$", "", stripped, flags=re.M)            # line comments
stripped = re.sub(r"""[rRbB]+(?:"[^"]*"|'[^']*')""", "", stripped)  # raw/byte strings
stripped = re.sub(r"""(?:"[^"]*://[^"]*"|'[^']*://[^']*')""", "", stripped)  # URL literals
stripped = re.sub(r'''(?:"#\s[^"]*"|'#\s[^']*')''', "", stripped)  # markdown-heading literals (report output)

# Flag string literals (single OR double-quoted) that contain '/' or '\\'
# and end in a known source/data extension — i.e. hardcoded paths that
# should be constructed via pathlib instead.
bad_pattern = (
    r'"[^"]*[\\/][^"]*\.(?:py|md|json|sh|jsonl|yml|yaml|toml)"'
    r"|"
    r"'[^']*[\\/][^']*\.(?:py|md|json|sh|jsonl|yml|yaml|toml)'"
)
bad = re.findall(bad_pattern, stripped)
if bad:
    sys.exit(f"{path} has hardcoded-path literals: {bad}")

if "from pathlib import Path" not in src and "pathlib.Path" not in src:
    sys.exit(f"{path} does not import pathlib")
PY
    [ "$status" -eq 0 ] || fail "$output"
  done
}
