#!/usr/bin/env bash
# State integrity validator for .forge/ directory.
# Checks cross-reference consistency of state files: required fields,
# counter bounds, orphaned checkpoints, stale locks, evidence freshness.
#
# Usage: state-integrity.sh <forge-dir>
# Exit 0 if valid, exit 1 if errors found.
# Output: "ERROR: ..." for hard failures, "WARNING: ..." for soft issues,
#         "OK: state integrity validated" if clean.

set -euo pipefail

FORGE_DIR="${1:?Usage: state-integrity.sh <forge-dir>}"

# Track exit status
errors=0
warnings=0

error() {
  echo "ERROR: $1"
  errors=$(( errors + 1 ))
}

warn() {
  echo "WARNING: $1"
  warnings=$(( warnings + 1 ))
}

# ── 1. state.json existence ─────────────────────────────────────────────────

STATE_FILE="${FORGE_DIR}/state.json"
if [[ ! -f "$STATE_FILE" ]]; then
  error "state.json not found in ${FORGE_DIR}"
  exit 1
fi

# ── 2. state.json is valid JSON ─────────────────────────────────────────────

PYTHON=""
if command -v python3 &>/dev/null; then
  PYTHON="python3"
elif command -v python &>/dev/null; then
  PYTHON="python"
else
  error "neither python3 nor python available for JSON validation"
  exit 1
fi

if ! "$PYTHON" -c "import json, sys; json.load(open(sys.argv[1]))" "$STATE_FILE" 2>/dev/null; then
  error "state.json is invalid JSON"
  exit 1
fi

# ── 3. Required fields ──────────────────────────────────────────────────────

REQUIRED_FIELDS="version complete story_id story_state domain_area total_retries total_retries_max"

missing_fields=$("$PYTHON" - "$STATE_FILE" "$REQUIRED_FIELDS" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
fields = sys.argv[2].split()
missing = [f for f in fields if f not in state]
if missing:
    print(" ".join(missing))
PYEOF
)

if [[ -n "$missing_fields" ]]; then
  error "required fields missing: ${missing_fields}"
fi

# ── 4. Counter consistency ───────────────────────────────────────────────────

counter_check=$("$PYTHON" - "$STATE_FILE" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
retries = state.get("total_retries", 0)
retries_max = state.get("total_retries_max", 10)
if isinstance(retries, (int, float)) and isinstance(retries_max, (int, float)):
    if retries > retries_max:
        print(f"total_retries ({retries}) exceeds total_retries_max ({retries_max})")
PYEOF
)

if [[ -n "$counter_check" ]]; then
  error "$counter_check"
fi

# ── 5. story_state is a valid pipeline state ─────────────────────────────────

VALID_STATES="PREFLIGHT EXPLORING PLANNING VALIDATING IMPLEMENTING VERIFYING REVIEWING DOCUMENTING SHIPPING LEARNING MIGRATING MIGRATION_PAUSED MIGRATION_CLEANUP MIGRATION_VERIFY"

state_check=$("$PYTHON" - "$STATE_FILE" "$VALID_STATES" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
valid = set(sys.argv[2].split())
current = state.get("story_state", "")
if current and current not in valid:
    print(f"invalid story_state: {current}")
PYEOF
)

if [[ -n "$state_check" ]]; then
  error "$state_check"
fi

# ── 6. domain_area is lowercase single word ──────────────────────────────────

domain_check=$("$PYTHON" - "$STATE_FILE" <<'PYEOF'
import json, sys, re
with open(sys.argv[1]) as f:
    state = json.load(f)
domain = state.get("domain_area", "")
if domain and not re.match(r'^[a-z][a-z0-9_-]*$', domain):
    print(f"domain_area '{domain}' is not lowercase single word")
PYEOF
)

if [[ -n "$domain_check" ]]; then
  warn "$domain_check"
fi

# ── 7. Orphaned checkpoint files ─────────────────────────────────────────────

story_id=$("$PYTHON" -c "import json,sys; print(json.load(open(sys.argv[1])).get('story_id',''))" "$STATE_FILE" 2>/dev/null || true)

if [[ -n "$story_id" ]]; then
  for ckpt in "${FORGE_DIR}"/checkpoint-*.json; do
    [[ -e "$ckpt" ]] || continue
    basename_ckpt="$(basename "$ckpt")"
    # Expected: checkpoint-{story_id}.json
    expected="checkpoint-${story_id}.json"
    if [[ "$basename_ckpt" != "$expected" ]]; then
      warn "orphaned checkpoint file: ${basename_ckpt} (current story_id: ${story_id})"
    fi
  done
fi

# ── 8. Lock file staleness ──────────────────────────────────────────────────

LOCK_FILE="${FORGE_DIR}/.lock"
if [[ -f "$LOCK_FILE" ]]; then
  # Get file modification time (epoch seconds), cross-platform
  lock_mtime=""
  if stat -f %m "$LOCK_FILE" &>/dev/null; then
    # macOS (BSD stat)
    lock_mtime=$(stat -f %m "$LOCK_FILE")
  elif stat -c %Y "$LOCK_FILE" &>/dev/null; then
    # Linux (GNU stat)
    lock_mtime=$(stat -c %Y "$LOCK_FILE")
  fi

  if [[ -n "$lock_mtime" ]]; then
    now=$(date +%s)
    age_hours=$(( (now - lock_mtime) / 3600 ))
    if [[ $age_hours -ge 24 ]]; then
      warn "lock file is stale (${age_hours}h old, threshold: 24h)"
    fi
  fi
fi

# ── 9. Evidence freshness ───────────────────────────────────────────────────

if [[ "$story_id" != "" ]]; then
  current_state=$("$PYTHON" -c "import json,sys; print(json.load(open(sys.argv[1])).get('story_state',''))" "$STATE_FILE" 2>/dev/null || true)
  if [[ "$current_state" == "SHIPPING" ]]; then
    EVIDENCE_FILE="${FORGE_DIR}/evidence.json"
    if [[ -f "$EVIDENCE_FILE" ]]; then
      evidence_verdict=$("$PYTHON" -c "import json,sys; print(json.load(open(sys.argv[1])).get('verdict',''))" "$EVIDENCE_FILE" 2>/dev/null || true)
      if [[ "$evidence_verdict" != "SHIP" ]]; then
        error "shipping but evidence verdict is '${evidence_verdict}', expected 'SHIP'"
      fi
    else
      error "shipping but evidence.json not found"
    fi
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────

if [[ $errors -gt 0 ]]; then
  exit 1
elif [[ $warnings -gt 0 ]]; then
  echo "OK: state integrity validated (${warnings} warning(s))"
  exit 0
else
  echo "OK: state integrity validated"
  exit 0
fi
