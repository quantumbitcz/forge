#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # PYTHONPATH covers shared/python so `import findings_store` works on Windows
  # (Git Bash), where MSYS-style sys.path entries cannot be resolved by native
  # Python; MSYS auto-converts known path-style env vars across the boundary.
  export PYTHONPATH="$PROJECT_ROOT/shared/python${PYTHONPATH:+:$PYTHONPATH}"
  export TMPDIR="$(mktemp -d)"
  export RUNS="$TMPDIR/.forge/runs/R/findings"
  mkdir -p "$RUNS"
}

teardown() { rm -rf "$TMPDIR"; }

@test "truncated JSON line → WARNING with reviewer id and line number; remaining lines survive" {
  # Line 1 valid, line 2 truncated, line 3 valid
  cat > "$RUNS/fg-410-code-reviewer.jsonl" <<EOF
{"finding_id":"f-fg-410-code-reviewer-01J2BQK0001","dedup_key":"a.kt:1:QUAL-NAME","reviewer":"fg-410-code-reviewer","severity":"INFO","category":"QUAL-NAME","file":"a.kt","line":1,"message":"name","confidence":"LOW","created_at":"2026-04-22T10:00:00Z","seen_by":[]}
{"finding_id":"f-fg-410
{"finding_id":"f-fg-410-code-reviewer-01J2BQK0003","dedup_key":"b.kt:2:QUAL-NAME","reviewer":"fg-410-code-reviewer","severity":"INFO","category":"QUAL-NAME","file":"b.kt","line":2,"message":"name","confidence":"LOW","created_at":"2026-04-22T10:00:01Z","seen_by":[]}
EOF

  run python3 - "$RUNS" <<'PY'
import contextlib
import io
import sys
from pathlib import Path

# PYTHONPATH (set in setup) covers shared/python.
from findings_store import reduce_findings

root = Path(sys.argv[1])
buf = io.StringIO()
with contextlib.redirect_stderr(buf):
    out = reduce_findings(root, writer_glob='fg-4*.jsonl')
assert len(out) == 2, out  # two survivors
err = buf.getvalue()
assert 'fg-410-code-reviewer' in err
assert 'line 2' in err
assert 'WARNING' in err.upper()
print('OK')
PY
  [ "$status" -eq 0 ]
}

@test "binary garbage line → skipped, continues" {
  printf '\x00\xff\x7f' > "$RUNS/fg-411-security-reviewer.jsonl"
  printf '\n{"finding_id":"f-fg-411-security-reviewer-ABCDEFGHJK","dedup_key":"x.kt:1:SEC","reviewer":"fg-411-security-reviewer","severity":"CRITICAL","category":"SEC","file":"x.kt","line":1,"message":"m","confidence":"HIGH","created_at":"2026-04-22T10:00:00Z","seen_by":[]}\n' >> "$RUNS/fg-411-security-reviewer.jsonl"
  run python3 - "$RUNS" <<'PY'
import sys
from pathlib import Path

# PYTHONPATH (set in setup) covers shared/python.
from findings_store import reduce_findings

out = reduce_findings(Path(sys.argv[1]), writer_glob='fg-4*.jsonl')
assert len(out) == 1 and out[0]['finding_id'] == 'f-fg-411-security-reviewer-ABCDEFGHJK'
print('OK')
PY
  [ "$status" -eq 0 ]
}
