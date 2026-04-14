#!/usr/bin/env bash
# Unified compression evaluation harness.
# Wraps output-compression benchmark and evals into a single CLI.
#
# Usage:
#   ./compression-eval.sh                          # Run output compression eval (3-arm, 10 tasks)
#   ./compression-eval.sh --suite output            # Same as above
#   ./compression-eval.sh --suite full              # Run 5-arm output benchmark
#   ./compression-eval.sh --suite input             # Run input compression measurement
#   ./compression-eval.sh --suite all               # Run all suites
#   ./compression-eval.sh --model claude-sonnet-4   # Specify model
#   ./compression-eval.sh --dry-run                 # Estimate cost, no API calls
#   ./compression-eval.sh --compare FILE1 FILE2     # Compare two result files
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SUITE="eval"
MODEL=""
DRY_RUN=""
COMPARE_FILES=()

usage() {
  cat <<'USAGE'
Usage: compression-eval.sh [OPTIONS]

Options:
  --suite <eval|output|full|input|all>  Suite to run (default: eval)
  --model <model-id>                    Anthropic model to use
  --dry-run                             Estimate cost, no API calls
  --compare <file1> <file2>             Compare two JSON result files
  -h, --help                            Show this help
USAGE
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite) shift; SUITE="$1"; shift ;;
    --model) shift; MODEL="--model $1"; shift ;;
    --dry-run) DRY_RUN="--dry-run"; shift ;;
    --compare)
      [[ $# -ge 3 ]] || { echo "Error: --compare requires two result files"; exit 1; }
      COMPARE_FILES=("$2" "$3")
      shift 3
      ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Handle --compare mode
if [[ ${#COMPARE_FILES[@]} -gt 0 ]]; then
  if [[ ! -f "${COMPARE_FILES[0]}" || ! -f "${COMPARE_FILES[1]}" ]]; then
    echo "ERROR: Both files must exist for comparison" >&2
    exit 1
  fi
  python3 -c "
import json, sys
a = json.load(open(sys.argv[1]))
b = json.load(open(sys.argv[2]))
print('Comparison of:', sys.argv[1], 'vs', sys.argv[2])
print('---')
for task in set(list(a.get('tasks',{}).keys()) + list(b.get('tasks',{}).keys())):
    print(f'Task: {task}')
    for arm in ['verbose','terse','caveman-full']:
        a_acc = a.get('tasks',{}).get(task,{}).get('arms',{}).get(arm,{}).get('accuracy','N/A')
        b_acc = b.get('tasks',{}).get(task,{}).get('arms',{}).get(arm,{}).get('accuracy','N/A')
        print(f'  {arm}: {a_acc} -> {b_acc}')
" "${COMPARE_FILES[0]}" "${COMPARE_FILES[1]}"
  exit 0
fi

case "$SUITE" in
  eval|output)
    echo "=== Output Compression Eval (3-arm) ==="
    python3 "$REPO_ROOT/evals/compression/run-evals.py" $MODEL $DRY_RUN
    ;;
  full)
    echo "=== Output Compression Benchmark (5-arm) ==="
    python3 "$SCRIPT_DIR/output-compression/run-benchmark.py" $MODEL $DRY_RUN
    ;;
  input)
    echo "=== Input Compression Measurement ==="
    python3 "$SCRIPT_DIR/input-compression/measure.py" --repo-root "$REPO_ROOT"
    ;;
  all)
    "$0" --suite eval $MODEL $DRY_RUN
    "$0" --suite full $MODEL $DRY_RUN
    "$0" --suite input
    ;;
  *)
    echo "Unknown suite: $SUITE" >&2; exit 1
    ;;
esac
