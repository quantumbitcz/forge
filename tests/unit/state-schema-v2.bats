#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCHEMA="$PROJECT_ROOT/shared/checks/state-schema-v2.0.json"
}

@test "state-schema-v2.0.json exists" {
  [ -f "$SCHEMA" ]
}

@test "schema declares version 2.0.0 as const" {
  run python3 -c "import json,sys; s=json.load(open(sys.argv[1])); p=s['properties']['version']; sys.exit(0 if p.get('const')=='2.0.0' else 1)" "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "schema defines plan_judge_loops as integer" {
  run python3 -c "import json,sys; s=json.load(open(sys.argv[1])); p=s['properties']['plan_judge_loops']; sys.exit(0 if p['type']=='integer' else 1)" "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "schema defines impl_judge_loops as object of integers keyed by string" {
  run python3 -c "import json,sys; s=json.load(open(sys.argv[1])); p=s['properties']['impl_judge_loops']; sys.exit(0 if (p['type']=='object' and p['additionalProperties']['type']=='integer') else 1)" "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "schema defines judge_verdicts as array of objects" {
  run python3 -c "import json,sys; s=json.load(open(sys.argv[1])); p=s['properties']['judge_verdicts']; sys.exit(0 if (p['type']=='array' and p['items']['type']=='object') else 1)" "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "schema forbids critic_revisions" {
  run grep -l critic_revisions "$SCHEMA"
  [ "$status" -ne 0 ]
}

@test "schema forbids implementer_reflection_cycles" {
  run grep -l implementer_reflection_cycles "$SCHEMA"
  [ "$status" -ne 0 ]
}

@test "findings-schema.json exists and validates canonical reviewer finding" {
  SCHEMA="$PROJECT_ROOT/shared/checks/findings-schema.json"
  [ -f "$SCHEMA" ]

  # Canonical reviewer finding (Phase 5 shape)
  FIXTURE=$(cat <<'EOF'
{
  "finding_id": "f-fg-411-security-reviewer-01J2BQK",
  "dedup_key": "src/api/UserController.kt:42:SEC-AUTH-003",
  "reviewer": "fg-411-security-reviewer",
  "severity": "CRITICAL",
  "category": "SEC-AUTH-003",
  "file": "src/api/UserController.kt",
  "line": 42,
  "message": "Missing ownership check on PATCH /users/{id}",
  "confidence": "HIGH",
  "created_at": "2026-04-22T14:03:11Z",
  "seen_by": []
}
EOF
)
  run python3 -c "import json,sys; import jsonschema; s=json.load(open(sys.argv[1])); f=json.loads(sys.argv[2]); jsonschema.validate(f,s); print('OK')" "$SCHEMA" "$FIXTURE"
  [ "$status" -eq 0 ]
}

@test "findings-schema.json tolerates Phase 7 INTENT finding (nullable file/line, ac_id required)" {
  SCHEMA="$PROJECT_ROOT/shared/checks/findings-schema.json"
  FIXTURE=$(cat <<'EOF'
{
  "finding_id": "f-fg-540-intent-verifier-01J2BQL",
  "dedup_key": "-:-:INTENT-AC-007",
  "reviewer": "fg-540-intent-verifier",
  "severity": "WARNING",
  "category": "INTENT-AC-007",
  "file": null,
  "line": null,
  "ac_id": "AC-007",
  "message": "AC-007 has no assertion coverage in the diff.",
  "confidence": "HIGH",
  "created_at": "2026-04-22T14:10:00Z",
  "seen_by": []
}
EOF
)
  run python3 -c "import json,sys; import jsonschema; s=json.load(open(sys.argv[1])); f=json.loads(sys.argv[2]); jsonschema.validate(f,s); print('OK')" "$SCHEMA" "$FIXTURE"
  [ "$status" -eq 0 ]
}

@test "findings-schema.json rejects INTENT finding without ac_id" {
  SCHEMA="$PROJECT_ROOT/shared/checks/findings-schema.json"
  FIXTURE=$(cat <<'EOF'
{
  "finding_id": "f-x-1",
  "dedup_key": "-:-:INTENT-AC-007",
  "reviewer": "fg-540-intent-verifier",
  "severity": "WARNING",
  "category": "INTENT-AC-007",
  "file": null,
  "line": null,
  "message": "no ac_id",
  "confidence": "HIGH",
  "created_at": "2026-04-22T14:10:00Z",
  "seen_by": []
}
EOF
)
  run python3 -c "import json,sys; import jsonschema; s=json.load(open(sys.argv[1])); f=json.loads(sys.argv[2]); jsonschema.validate(f,s)" "$SCHEMA" "$FIXTURE"
  [ "$status" -ne 0 ]
}
