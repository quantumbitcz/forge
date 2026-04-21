#!/usr/bin/env bash
# Thin shim → shared/convergence_engine_sim.py.
# Original used `bc` for floats which isn't available on Windows.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
exec env PYTHONPATH="${PLUGIN_ROOT}${PYTHONPATH:+:${PYTHONPATH}}" \
  python3 -m shared.convergence_engine_sim "$@"
