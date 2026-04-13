#!/usr/bin/env bash
set -euo pipefail

# Convergence Engine Simulator — Executable Specification
# Usage: convergence-engine-sim.sh [options]
#
# Simulates the convergence engine with given parameters and score history.
# This script IS the canonical algorithm. convergence-engine.md is the prose
# explanation. If they disagree, this script is authoritative.
#
# Options:
#   --scores "43,78,75,76"        Score history (comma-separated, required)
#   --pass-threshold 80           Minimum passing score (default: 80)
#   --plateau-threshold 2         Smoothed delta <= this = plateau (default: 2)
#   --plateau-patience 2          Consecutive plateaus before confirmed (default: 2)
#   --oscillation-tolerance 5     Raw delta within tolerance = not regressing (default: 5)
#   --max-iterations 10           Maximum total iterations (default: 10)
#   --target-score 90             Target for perfection phase (default: 90)
#   --help                        Show this help
#
# Limitations:
#   - SAFETY_GATE phase requires test pass/fail input not modeled by this
#     simulator. See convergence-engine.md §Safety Gate for the full algorithm.
#   - Input validation is minimal — non-numeric scores produce undefined behavior.
#
# Output (one line per cycle):
#   cycle=N score=S delta=D smoothed=SM phase=PHASE plateau_count=PC decision=DECISION

# --- Defaults ---
SCORES=""
PASS_THRESHOLD=80
PLATEAU_THRESHOLD=2
PLATEAU_PATIENCE=2
OSCILLATION_TOLERANCE=5
MAX_ITERATIONS=10
TARGET_SCORE=90

show_help() {
  sed -n '3,23p' "$0" | sed 's/^# \?//'
  exit 0
}

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scores)         SCORES="$2";               shift 2 ;;
    --pass-threshold) PASS_THRESHOLD="$2";       shift 2 ;;
    --plateau-threshold) PLATEAU_THRESHOLD="$2"; shift 2 ;;
    --plateau-patience) PLATEAU_PATIENCE="$2";   shift 2 ;;
    --oscillation-tolerance) OSCILLATION_TOLERANCE="$2"; shift 2 ;;
    --max-iterations) MAX_ITERATIONS="$2";       shift 2 ;;
    --target-score)   TARGET_SCORE="$2";         shift 2 ;;
    --help)           show_help ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$SCORES" ]]; then
  echo "Error: --scores is required" >&2
  exit 1
fi

# --- Parse scores into array ---
IFS=',' read -ra SCORE_ARR <<< "$SCORES"
NUM_SCORES=${#SCORE_ARR[@]}

if [[ $NUM_SCORES -eq 0 ]]; then
  echo "Error: --scores must contain at least one value" >&2
  exit 1
fi

# --- Smoothed delta function ---
# Implements the 4-case smoothed_delta from convergence-engine.md:
#   <2 scores: 0
#   2 scores:  raw delta
#   3 scores:  2-point weighted (0.6/0.4)
#   4+ scores: 3-point weighted (0.5/0.3/0.2)
#
# Arguments: space-separated score history up to current cycle
compute_smoothed_delta() {
  local -a hist=("$@")
  local len=${#hist[@]}

  if [[ $len -lt 2 ]]; then
    echo "0"
    return
  fi

  if [[ $len -eq 2 ]]; then
    echo "${hist[1]} - ${hist[0]}" | bc
    return
  fi

  if [[ $len -eq 3 ]]; then
    local d1 d2
    d1=$(echo "${hist[2]} - ${hist[1]}" | bc)
    d2=$(echo "${hist[1]} - ${hist[0]}" | bc)
    echo "$d1 * 0.6 + $d2 * 0.4" | bc
    return
  fi

  # 4+ scores: use last 4 entries
  local d1 d2 d3
  d1=$(echo "${hist[$((len-1))]} - ${hist[$((len-2))]}" | bc)
  d2=$(echo "${hist[$((len-2))]} - ${hist[$((len-3))]}" | bc)
  d3=$(echo "${hist[$((len-3))]} - ${hist[$((len-4))]}" | bc)
  echo "$d1 * 0.5 + $d2 * 0.3 + $d3 * 0.2" | bc
}

# --- Absolute value for bc output (may have leading minus, may have decimals) ---
abs_val() {
  local v="$1"
  echo "$v" | sed 's/^-//'
}

# --- Simulation loop ---
plateau_count=0
total_iterations=0
history=()

for (( i=0; i<NUM_SCORES; i++ )); do
  cycle=$((i + 1))
  score=${SCORE_ARR[$i]}
  history+=("$score")

  # Raw delta from previous score (0 if first)
  if [[ $i -eq 0 ]]; then
    delta=0
  else
    delta=$(echo "$score - ${SCORE_ARR[$((i-1))]}" | bc)
  fi

  # Smoothed delta from history
  smoothed=$(compute_smoothed_delta "${history[@]}")

  # Increment total iterations (each cycle = one iteration)
  total_iterations=$cycle

  # --- Decision logic ---
  phase=""
  decision=""

  # 1. Global cap: budget exhausted
  if [[ $total_iterations -ge $MAX_ITERATIONS ]]; then
    phase="BUDGET_EXHAUSTED"
    decision="ESCALATE"

  # 2. Regressing: raw delta < 0 AND |delta| > oscillation_tolerance
  elif [[ $i -gt 0 ]] && [[ $(echo "$delta < 0" | bc) -eq 1 ]] && \
       [[ $(echo "$(abs_val "$delta") > $OSCILLATION_TOLERANCE" | bc) -eq 1 ]]; then
    phase="REGRESSING"
    decision="ESCALATE"

  # 3. Pass: score >= pass_threshold AND no confirmed plateau
  elif [[ $(echo "$score >= $PASS_THRESHOLD" | bc) -eq 1 ]] && [[ $plateau_count -lt $PLATEAU_PATIENCE ]]; then
    # Check if we are in a plateau situation first (cycle >= 3)
    if [[ $cycle -ge 3 ]] && [[ $(echo "$(abs_val "$smoothed") <= $PLATEAU_THRESHOLD" | bc) -eq 1 ]]; then
      plateau_count=$((plateau_count + 1))
      if [[ $plateau_count -ge $PLATEAU_PATIENCE ]]; then
        phase="PLATEAUED"
        decision="PASS_PLATEAUED"
      else
        phase="PASS"
        decision="PASS"
      fi
    else
      phase="PASS"
      decision="PASS"
    fi

  # 4. Plateau detection: cycle >= 3 AND |smoothed_delta| <= plateau_threshold
  elif [[ $cycle -ge 3 ]] && [[ $(echo "$(abs_val "$smoothed") <= $PLATEAU_THRESHOLD" | bc) -eq 1 ]]; then
    plateau_count=$((plateau_count + 1))
    if [[ $plateau_count -ge $PLATEAU_PATIENCE ]]; then
      if [[ $(echo "$score >= $PASS_THRESHOLD" | bc) -eq 1 ]]; then
        phase="PLATEAUED"
        decision="PASS_PLATEAUED"
      else
        phase="PLATEAUED"
        decision="ESCALATE"
      fi
    else
      phase="IMPROVING"
      decision="CONTINUE"
    fi

  # 5. Default: improving
  else
    plateau_count=0
    phase="IMPROVING"
    decision="CONTINUE"
  fi

  echo "cycle=$cycle score=$score delta=$delta smoothed=$smoothed phase=$phase plateau_count=$plateau_count decision=$decision"
done
