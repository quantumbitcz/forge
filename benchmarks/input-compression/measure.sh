#!/usr/bin/env bash
# Measure input compression effectiveness across the forge repo.
# Applies compression rules from shared/input-compression.md via Python regex.
#
# Usage:
#   ./measure.sh                    # Run with defaults (aggressive, level 2)
#   ./measure.sh --level 1          # Conservative
#   ./measure.sh --level 3          # Ultra
#   ./measure.sh --file path.md     # Single file
#
# Output: writes results to benchmarks/input-compression/results.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MEASURE_PY="$SCRIPT_DIR/measure.py"
OUTPUT="$SCRIPT_DIR/results.md"

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 required" >&2
    exit 1
fi

# Pass all arguments through, add defaults
ARGS=("--repo-root" "$REPO_ROOT" "--output" "$OUTPUT")

# Check if user passed --file (skip repo-root/output if so)
for arg in "$@"; do
    if [[ "$arg" == "--file" ]]; then
        ARGS=()
        break
    fi
done

echo "Running input compression benchmark..."
python3 "$MEASURE_PY" "${ARGS[@]}" "$@"

if [[ -f "$OUTPUT" ]] && [[ ${#ARGS[@]} -gt 0 ]]; then
    echo ""
    echo "Results written to: $OUTPUT"
    echo ""
    # Print summary line from results
    tail -n +7 "$OUTPUT" | head -20
fi
