#!/usr/bin/env bats
# SEC-INJECTION-* scoring categories registered.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  REG="$ROOT/shared/checks/category-registry.json"
}

@test "all 7 SEC-INJECTION-* categories are registered" {
  # Path passed via argv so MSYS auto-converts /d/a/... to native Windows form on Git Bash.
  python3 - "$REG" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
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
  python3 - "$REG" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
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
    assert "fg-411-security-reviewer" in row.get("agents", []), \
        f"{cid} missing security reviewer in agents"
    assert row.get("priority") == 1, f"{cid} priority should be 1 (CRITICAL routing)"
PY
}
