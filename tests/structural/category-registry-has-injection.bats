#!/usr/bin/env bats
# Phase 03 Task 5: SEC-INJECTION-* scoring categories registered.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  REG="$ROOT/shared/checks/category-registry.json"
}

@test "all 7 SEC-INJECTION-* categories are registered" {
  python3 - <<PY
import json
d = json.load(open("$REG"))
ids = set(d["categories"].keys())
required = {
  "SEC-INJECTION-OVERRIDE",
  "SEC-INJECTION-EXFIL",
  "SEC-INJECTION-TOOL-MISUSE",
  "SEC-INJECTION-BLOCKED",
  "SEC-INJECTION-TRUNCATED",
  "SEC-INJECTION-DISABLED",
  "SEC-INJECTION-HISTORICAL",
}
missing = required - ids
assert not missing, f"missing: {missing}"
PY
}

@test "each new category has the security-reviewer agent" {
  python3 - <<PY
import json
d = json.load(open("$REG"))
cats = d["categories"]
ids = [
  "SEC-INJECTION-OVERRIDE",
  "SEC-INJECTION-EXFIL",
  "SEC-INJECTION-TOOL-MISUSE",
  "SEC-INJECTION-BLOCKED",
  "SEC-INJECTION-TRUNCATED",
  "SEC-INJECTION-DISABLED",
  "SEC-INJECTION-HISTORICAL",
]
for cid in ids:
    row = cats[cid]
    assert "fg-411-security-reviewer" in row.get("agents", []), \\
        f"{cid} missing security reviewer in agents"
    assert row.get("priority") == 1, f"{cid} priority should be 1 (CRITICAL routing)"
PY
}
