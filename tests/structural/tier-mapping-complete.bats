#!/usr/bin/env bats
# Phase 03 Task 2: every CONSUMER_SOURCES entry in the filter has a tier-table row.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "every source referenced in filter has a tier row" {
  python3 - <<PY
import re, sys, pathlib
filt_path = pathlib.Path("$ROOT/hooks/_py/mcp_response_filter.py")
doc_path = pathlib.Path("$ROOT/shared/untrusted-envelope.md")
if not filt_path.exists():
    # Filter not yet present (Task 3 not landed) — skip.
    print("filter not yet present, skipping")
    sys.exit(0)
filt = filt_path.read_text()
doc = doc_path.read_text()
m = re.search(r"CONSUMER_SOURCES\s*=\s*\{([^}]*)\}", filt, re.DOTALL)
assert m, "CONSUMER_SOURCES constant not found in filter"
sources = re.findall(r'"([^"]+)"', m.group(1))
missing = [s for s in sources if f"\`{s}\`" not in doc]
if missing:
    print(f"sources missing from tier table: {missing}", file=sys.stderr)
    sys.exit(1)
PY
}
