#!/usr/bin/env bash
# Budget ceiling alerting for the forge pipeline.
#
# Commands:
#   init [--forge-dir PATH]                  -- Initialize budget tracking for run
#   check [--forge-dir PATH]                 -- Check budget status, return alert level
#   stage-report <stage> [--forge-dir PATH]  -- Emit per-stage cost summary line
#   summary [--forge-dir PATH]               -- Full budget summary for forge-status
#   apply-downgrade [--forge-dir PATH]       -- Write model tier override to state.json
#
# Exit codes:
#   0 = OK (below first threshold)
#   1 = INFO (crossed first threshold, e.g., 50%)
#   2 = WARNING (crossed second threshold, e.g., 75%)
#   3 = CRITICAL (crossed third threshold, e.g., 90%)
#   4 = EXCEEDED (above 100% of ceiling)
#   10 = disabled (cost_alerting.enabled is false)
#   11 = input error
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_WRITER="${SCRIPT_DIR}/forge-state-write.sh"

FORGE_DIR=".forge"
CMD=""
STAGE=""
ITERATION=""

# ── Argument parsing ──────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    init)
      CMD="init"; shift ;;
    check)
      CMD="check"; shift ;;
    stage-report)
      CMD="stage-report"; shift
      STAGE="${1:?stage-report requires <stage>}"; shift
      # Optional: --iteration N for convergence loop cost lines
      if [[ $# -gt 0 && "$1" == "--iteration" ]]; then
        shift; ITERATION="${1:?--iteration requires a number}"; shift
      fi
      ;;
    summary)
      CMD="summary"; shift ;;
    apply-downgrade)
      CMD="apply-downgrade"; shift ;;
    --forge-dir)
      shift; FORGE_DIR="${1:?--forge-dir requires a path}"; shift ;;
    *)
      echo "ERROR: unknown argument: $1" >&2; exit 11 ;;
  esac
done

[[ -z "$CMD" ]] && { echo "Usage: cost-alerting.sh {init|check|stage-report|summary|apply-downgrade} ..." >&2; exit 11; }

# ── Helpers ───────────────────────────────────────────────────────────────

_read_state() {
  bash "$STATE_WRITER" read --forge-dir "$FORGE_DIR"
}

_write_state() {
  local _max_retries=3 _attempt=0 _updated="$1"
  while [[ $_attempt -lt $_max_retries ]]; do
    bash "$STATE_WRITER" write "$_updated" --forge-dir "$FORGE_DIR" > /dev/null
    local _rc=$?
    if [[ $_rc -eq 0 ]]; then
      return 0
    elif [[ $_rc -eq 3 ]]; then
      # CAS conflict -- re-read state, re-apply the update, and retry
      _attempt=$((_attempt + 1))
      local _delay
      _delay=$(python3 -c "import random; print(0.05 * (2 ** ($_attempt - 1)) + random.random() * 0.02)")
      sleep "$_delay" 2>/dev/null || sleep 0.1
      # Re-read current state and merge our changes on top
      local _fresh_state
      _fresh_state=$(_read_state) || return 2
      # Merge: take the fresh _seq but apply our cost_alerting/context changes
      _updated=$(python3 -c "
import json, sys
fresh = json.loads(sys.argv[1])
ours = json.loads(sys.argv[2])
# Preserve fresh _seq and any concurrent changes, overlay our specific sections
for key in ['cost_alerting', 'context', 'cost']:
    if key in ours:
        fresh[key] = ours[key]
json.dump(fresh, sys.stdout)
" "$_fresh_state" "$_updated") || return 2
      continue
    else
      echo "ERROR: state write failed (rc=$_rc)" >&2
      return "$_rc"
    fi
  done
  echo "ERROR: state write failed after $_max_retries CAS retries" >&2
  return 3
}

# ── Init ──────────────────────────────────────────────────────────────────

do_init() {
  local state_file="${FORGE_DIR}/state.json"
  [[ ! -f "$state_file" ]] && { echo "ERROR: state.json not found in $FORGE_DIR" >&2; exit 11; }

  local current_state
  current_state=$(_read_state) || { echo "ERROR: failed to read state.json" >&2; exit 11; }

  local updated_state
  updated_state=$(echo "$current_state" | python3 -c '
import json, sys, os

state = json.load(sys.stdin)
forge_dir = sys.argv[1]

# Read config for cost_alerting settings
budget_ceiling = 2000000
thresholds = [0.50, 0.75, 0.90]
per_stage_limits = "auto"

config_path = os.path.join(os.environ.get("FORGE_CONFIG_DIR", "."), "forge-config.md")
try:
    if os.path.exists(config_path):
        with open(config_path) as cf:
            cfg_text = cf.read()
        parts = cfg_text.split("---")
        if len(parts) >= 3:
            import yaml
            cfg = yaml.safe_load(parts[1]) or {}
            ca = cfg.get("cost_alerting", {})
            if ca:
                if "budget_ceiling_tokens" in ca:
                    budget_ceiling = int(ca["budget_ceiling_tokens"])
                if "alert_thresholds" in ca:
                    t = ca["alert_thresholds"]
                    if isinstance(t, list) and len(t) == 3:
                        thresholds = [float(x) for x in t]
                if "per_stage_limits" in ca:
                    per_stage_limits = ca["per_stage_limits"]
except Exception:
    pass

# Resolve auto per-stage limits
if per_stage_limits == "auto":
    proportions = {
        "preflight":     0.03,
        "exploring":     0.07,
        "planning":      0.10,
        "validating":    0.05,
        "implementing":  0.30,
        "verifying":     0.15,
        "reviewing":     0.15,
        "documenting":   0.05,
        "shipping":      0.05,
        "learning":      0.05,
    }
    per_stage_limits = {s: int(budget_ceiling * p) for s, p in proportions.items()}

# Set ceiling in tokens section
if "tokens" not in state:
    state["tokens"] = {"estimated_total": 0, "budget_ceiling": 0, "by_stage": {}, "by_agent": {}}
state["tokens"]["budget_ceiling"] = budget_ceiling

# Initialize cost_alerting runtime state
state["cost_alerting"] = {
    "enabled": True,
    "thresholds": thresholds,
    "per_stage_limits": per_stage_limits,
    "alerts_issued": [],
    "last_alert_level": "OK",
    "routing_override": None,
}

json.dump(state, sys.stdout, indent=2)
' "$FORGE_DIR")
  [[ $? -ne 0 ]] && { echo "ERROR: failed to compute init state" >&2; exit 11; }

  _write_state "$updated_state"
}

# ── Check ─────────────────────────────────────────────────────────────────

do_check() {
  local state_file="${FORGE_DIR}/state.json"
  [[ ! -f "$state_file" ]] && { echo "OK: no state.json, nothing to check"; exit 0; }

  local current_state
  current_state=$(_read_state) || { echo "OK: could not read state.json"; exit 0; }

  # Python computes alert level, updates state, outputs message + exit code
  local result
  result=$(echo "$current_state" | python3 -c '
import json, sys

state = json.load(sys.stdin)
forge_dir = sys.argv[1]

ca = state.get("cost_alerting", {})
if not ca.get("enabled", True):
    print("DISABLED")
    sys.exit(0)

tokens = state.get("tokens", {})
total = tokens.get("estimated_total", 0)
ceiling = tokens.get("budget_ceiling", 0)

if ceiling <= 0:
    print("EXIT:0")
    print("OK: no budget ceiling set")
    sys.exit(0)

ratio = total / ceiling
thresholds = ca.get("thresholds", [0.50, 0.75, 0.90])
alerts_issued = ca.get("alerts_issued", [])

# Determine current alert level
if ratio >= 1.0:
    level = "EXCEEDED"
    exit_code = 4
elif len(thresholds) >= 3 and ratio >= thresholds[2]:
    level = "CRITICAL"
    exit_code = 3
elif len(thresholds) >= 2 and ratio >= thresholds[1]:
    level = "WARNING"
    exit_code = 2
elif len(thresholds) >= 1 and ratio >= thresholds[0]:
    level = "INFO"
    exit_code = 1
else:
    level = "OK"
    exit_code = 0

# Only emit NEW_ALERT for newly crossed thresholds
new_alert = level not in alerts_issued and level != "OK"
if new_alert:
    alerts_issued.append(level)
    ca["alerts_issued"] = alerts_issued
    ca["last_alert_level"] = level
    state["cost_alerting"] = ca

pct = int(ratio * 100)
msg = f"{level}: {pct}% of token budget used ({total:,} / {ceiling:,})"

# Output: EXIT:{code}\n{message}\n[NEW_ALERT:{level}]
print(f"EXIT:{exit_code}")
print(msg)
if new_alert:
    print(f"NEW_ALERT:{level}")

# Output updated state if we modified it
if new_alert:
    print("STATE:" + json.dumps(state))
' "$FORGE_DIR")

  local exit_code=0
  local output_lines=()
  local updated_state=""

  while IFS= read -r line; do
    if [[ "$line" == "DISABLED" ]]; then
      exit 10
    elif [[ "$line" == EXIT:* ]]; then
      exit_code="${line#EXIT:}"
    elif [[ "$line" == STATE:* ]]; then
      updated_state="${line#STATE:}"
    else
      output_lines+=("$line")
    fi
  done <<< "$result"

  # Print output
  for line in "${output_lines[@]}"; do
    echo "$line"
  done

  # Write updated state if alerts changed
  if [[ -n "$updated_state" ]]; then
    _write_state "$updated_state"
  fi

  exit "$exit_code"
}

# ── Stage Report ──────────────────────────────────────────────────────────

do_stage_report() {
  local state_file="${FORGE_DIR}/state.json"
  [[ ! -f "$state_file" ]] && { echo "[COST] $STAGE: no state data"; return 0; }

  local current_state
  current_state=$(_read_state) || { echo "[COST] $STAGE: state read error"; return 0; }

  echo "$current_state" | python3 -c "
import json, sys

state = json.load(sys.stdin)
stage = sys.argv[1].lower()
iteration = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else ''

tokens = state.get('tokens', {})
by_stage = tokens.get('by_stage', {})
stage_data = by_stage.get(stage, {'input': 0, 'output': 0})
stage_tokens = stage_data.get('input', 0) + stage_data.get('output', 0)
total_tokens = tokens.get('estimated_total', 0)
ceiling = tokens.get('budget_ceiling', 0)

cost = state.get('cost', {})
cost_usd = cost.get('estimated_cost_usd', 0.0)

# Per-stage budget check
ca = state.get('cost_alerting', {})
per_stage_limits = ca.get('per_stage_limits', {})
stage_limit = per_stage_limits.get(stage, 0)

budget_note = ''
if stage_limit > 0:
    stage_ratio = stage_tokens / stage_limit
    if stage_ratio >= 1.5:
        budget_note = ' [STAGE_OVER_BUDGET: 150%+ of expected]'
    elif stage_ratio >= 1.0:
        budget_note = ' [STAGE_AT_LIMIT]'

# Format
if ceiling > 0:
    pct = int(total_tokens / ceiling * 100)
    budget_str = f'{pct}% of budget'
else:
    budget_str = 'no budget set'

# Abbreviation map
abbrev = {
    'preflight': 'PRE', 'exploring': 'EXPL', 'planning': 'PLAN',
    'validating': 'VALID', 'implementing': 'IMPL', 'verifying': 'VERIFY',
    'reviewing': 'REVIEW', 'documenting': 'DOCS', 'shipping': 'SHIP',
    'learning': 'LEARN',
}
label = abbrev.get(stage, stage.upper())

if iteration:
    print(f'[COST] {label} iteration {iteration}: {stage_tokens:,} tokens (\${cost_usd:.2f}) | {budget_str} | Run total: {total_tokens:,} tokens{budget_note}')
else:
    print(f'[COST] {label}: {stage_tokens:,} tokens (\${cost_usd:.2f}) | {budget_str} | Run total: {total_tokens:,} tokens{budget_note}')
" "$STAGE" "$ITERATION"
}

# ── Summary ──────────────────────────────────────────────────────────────

do_summary() {
  local forge_dir="${FORGE_DIR}"
  local state_file="${forge_dir}/state.json"
  [[ -f "$state_file" ]] || { echo "No state file"; return 1; }

  local current_state
  current_state=$(_read_state) || { echo "No state file"; return 1; }

  echo "$current_state" | python3 -c "
import json, sys
state = json.load(sys.stdin)
cost = state.get('cost', {})
tokens = state.get('tokens', {})
ca = state.get('cost_alerting', {})
ceiling = tokens.get('budget_ceiling', 2000000)
total = tokens.get('estimated_total', 0)
pct = round(total / ceiling * 100, 1) if ceiling > 0 else 0
cost_usd = cost.get('estimated_cost_usd', 0.0)
alerts = ca.get('alerts_issued', [])

print(f'Budget: {total:,} / {ceiling:,} tokens ({pct}%) — Est. \${cost_usd:.2f}')
if alerts:
    print(f'Alerts triggered: {', '.join(alerts)}')

by_stage = tokens.get('by_stage', {})
if by_stage:
    print('Per-stage:')
    for stage, data in sorted(by_stage.items()):
        stokens = data.get('input', 0) + data.get('output', 0)
        per_stage_costs = cost.get('per_stage', {})
        stage_cost = per_stage_costs.get(stage, {}).get('cost_usd', 0.0) if isinstance(per_stage_costs.get(stage), dict) else 0.0
        print(f'  {stage}: {stokens:,} tokens (\${stage_cost:.2f})')
"
}

# ── Apply Downgrade ──────────────────────────────────────────────────────

do_apply_downgrade() {
  local state_file="${FORGE_DIR}/state.json"
  [[ ! -f "$state_file" ]] && { echo "ERROR: state.json not found" >&2; exit 11; }

  local current_state
  current_state=$(_read_state) || exit 11

  local updated_state
  updated_state=$(echo "$current_state" | python3 -c '
import json, sys

state = json.load(sys.stdin)

# Cost downgrade routing: premium -> standard, standard -> fast
cost_downgrade_routing = {
    "fg-200-planner": "sonnet",
    "fg-300-implementer": "sonnet",
    "fg-320-frontend-polisher": "sonnet",
    "fg-412-architecture-reviewer": "sonnet",
    "fg-350-docs-generator": "haiku",
    "fg-600-pr-builder": "haiku",
    "fg-700-retrospective": "haiku",
    "fg-710-post-run": "haiku",
}

ca = state.get("cost_alerting", {})
ca["routing_override"] = cost_downgrade_routing
state["cost_alerting"] = ca

json.dump(state, sys.stdout, indent=2)
')
  [[ $? -ne 0 ]] && { echo "ERROR: failed to compute downgrade" >&2; exit 11; }

  _write_state "$updated_state"
  echo "Applied cost downgrade routing override for remaining stages"
}

# ── Dispatch ──────────────────────────────────────────────────────────────

case "$CMD" in
  init)            do_init ;;
  check)           do_check ;;
  stage-report)    do_stage_report ;;
  summary)         do_summary ;;
  apply-downgrade) do_apply_downgrade ;;
esac
