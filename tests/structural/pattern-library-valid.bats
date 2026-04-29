#!/usr/bin/env bats
# Structural validity of the prompt-injection pattern library.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  PATTERNS="$ROOT/shared/prompt-injection-patterns.json"
  SCHEMA="$ROOT/shared/prompt-injection-patterns.schema.json"
}

@test "pattern library file exists" {
  [ -f "$PATTERNS" ]
}

@test "pattern schema file exists" {
  [ -f "$SCHEMA" ]
}

@test "pattern library is valid JSON" {
  # Path passed via argv so MSYS auto-converts /d/a/... to native Windows form on Git Bash.
  python3 -c "import json, sys; json.load(open(sys.argv[1]))" "$PATTERNS"
}

@test "pattern library validates against schema" {
  python3 - "$PATTERNS" "$SCHEMA" <<'PY'
import json, re, sys
data = json.load(open(sys.argv[1]))
schema = json.load(open(sys.argv[2]))
assert data.get("version") == schema["properties"]["version"]["const"], "version mismatch"
assert isinstance(data["patterns"], list)
assert len(data["patterns"]) >= 40, f"expected >= 40 patterns, got {len(data['patterns'])}"
allowed_cats = set(schema["properties"]["patterns"]["items"]["properties"]["category"]["enum"])
allowed_sev = set(schema["properties"]["patterns"]["items"]["properties"]["severity"]["enum"])
id_pat = re.compile(schema["properties"]["patterns"]["items"]["properties"]["id"]["pattern"])
seen_ids = set()
for p in data["patterns"]:
    assert p["category"] in allowed_cats, f"bad category: {p['category']}"
    assert p["severity"] in allowed_sev, f"bad severity: {p['severity']}"
    assert id_pat.match(p["id"]), f"bad id: {p['id']}"
    assert p["id"] not in seen_ids, f"duplicate id: {p['id']}"
    seen_ids.add(p["id"])
    re.compile(p["pattern"])  # every regex compiles
PY
}

@test "every pattern category has at least one entry" {
  python3 - "$PATTERNS" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
cats = {p["category"] for p in data["patterns"]}
required = {"OVERRIDE","ROLE_HIJACK","SYSTEM_SPOOF","TOOL_COERCION","EXFIL","CREDENTIAL_SHAPED","PROMPT_LEAK"}
missing = required - cats
assert not missing, f"missing categories: {missing}"
PY
}
