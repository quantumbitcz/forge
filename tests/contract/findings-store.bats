#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # Convert MSYS path to mixed form on native Windows so native Python can resolve it.
  if command -v cygpath >/dev/null 2>&1; then
    PROJECT_ROOT="$(cygpath -m "$PROJECT_ROOT")"
  fi
}

@test "shared/findings-store.md exists" {
  [ -f "$PROJECT_ROOT/shared/findings-store.md" ]
}

@test "findings-store.md declares path convention .forge/runs/<run_id>/findings/" {
  run grep -F ".forge/runs/<run_id>/findings/" "$PROJECT_ROOT/shared/findings-store.md"
  [ "$status" -eq 0 ]
}

@test "findings-store.md declares append-only semantics" {
  # Match both case forms (the section header is "Append-only" but body
  # references "append-only") without -i, which is broken in some MSYS
  # grep builds against UTF-8 docs.
  run grep -F -e "Append-only" -e "append-only" "$PROJECT_ROOT/shared/findings-store.md"
  [ "$status" -eq 0 ]
}

@test "findings-store.md documents annotation inheritance rule verbatim phrase" {
  run grep -F "inherits \`severity\`, \`category\`, \`file\`, \`line\`, \`confidence\`, and \`message\` **verbatim**" "$PROJECT_ROOT/shared/findings-store.md"
  [ "$status" -eq 0 ]
}

@test "findings-store.md documents duplicate emission tiebreaker" {
  # Strings are lowercase in the source; -i is broken on some MSYS grep builds.
  run grep -F "tiebreaker" "$PROJECT_ROOT/shared/findings-store.md"
  [ "$status" -eq 0 ]
}

@test "stage-contract.md describes Agent Teams pattern for Stage 6" {
  F="$PROJECT_ROOT/shared/stage-contract.md"
  run grep -F 'Agent Teams' "$F"
  [ "$status" -eq 0 ]
}

@test "stage-contract.md describes judge veto in Stage 2 and Stage 4" {
  F="$PROJECT_ROOT/shared/stage-contract.md"
  run grep -F 'binding veto' "$F"
  [ "$status" -eq 0 ]
}

@test "agent-communication.md does not contain stale 'dedup hints' phrasing" {
  # Note: 'previous batch findings' is now expected (per dedup-no-cap.bats):
  # the §Findings Store Protocol section requires "Include all previous batch
  # findings with domain affinity for the next reviewer." We only forbid the
  # legacy 'dedup hints' phrasing that was the explicit replacement target.
  F="$PROJECT_ROOT/shared/agent-communication.md"
  run grep -iF 'dedup hints' "$F"
  [ "$status" -ne 0 ]
}

@test "agent-communication.md references Findings Store Protocol" {
  F="$PROJECT_ROOT/shared/agent-communication.md"
  run grep -F 'Findings Store Protocol' "$F"
  [ "$status" -eq 0 ]
}

@test "fg-400-quality-gate.md does not contain forbidden strings" {
  F="$PROJECT_ROOT/agents/fg-400-quality-gate.md"
  for s in 'previous batch findings' 'dedup hints' 'top 20'; do
    run grep -iF "$s" "$F"
    [ "$status" -ne 0 ] || { echo "forbidden string found: $s"; return 1; }
  done
}

@test "fg-400-quality-gate §20 is <= 3 lines and references shared/agents.md#review-tier" {
  F="$PROJECT_ROOT/agents/fg-400-quality-gate.md"
  SECTION=$(awk '/^## 20\./,/^## 21\./{print}' "$F" | grep -v '^## 21' | tail -n +2)
  LINES=$(echo "$SECTION" | grep -cv '^[[:space:]]*$' || true)
  [ "$LINES" -le 3 ]
  echo "$SECTION" | grep -F 'shared/agents.md#review-tier'
}

@test "fg-400-quality-gate declares parallel fanout with max_parallel_reviewers" {
  F="$PROJECT_ROOT/agents/fg-400-quality-gate.md"
  run grep -F 'max_parallel_reviewers' "$F"
  [ "$status" -eq 0 ]
}

@test "every fg-41* reviewer contains 'Findings Store Protocol' in first 60 lines" {
  for F in "$PROJECT_ROOT"/agents/fg-41*.md; do
    HEAD=$(head -60 "$F")
    echo "$HEAD" | grep -qF 'Findings Store Protocol' || {
      echo "missing preamble in $F"
      return 1
    }
  done
}

@test "orchestrator dispatches fg-400 with reviewer_registry_slice parameter" {
  F="$PROJECT_ROOT/agents/fg-100-orchestrator.md"
  run grep -F 'reviewer_registry_slice' "$F"
  [ "$status" -eq 0 ]
}

@test "reviewer_registry helper exists and extracts REVIEW-tier from shared/agents.md" {
  run python3 - "$PROJECT_ROOT/shared/python" "$PROJECT_ROOT/shared/agents.md" <<'PYEOF'
import sys
sys.path.insert(0, sys.argv[1])
from reviewer_registry import extract_review_tier_slice
import pathlib
slice = extract_review_tier_slice(pathlib.Path(sys.argv[2]))
assert isinstance(slice, (list, tuple)) and len(slice) == 9, f'expected 9, got {len(slice)}'
names = [r['name'] for r in slice]
assert names == sorted(set(names)), f'duplicates or unsorted: {names}'
assert any('fg-411-security-reviewer' == r['name'] for r in slice)
assert all(not r['domain'].startswith('6 (') for r in slice), 'leaked Tier-matrix row'
print('OK')
PYEOF
  [ "$status" -eq 0 ]
}
