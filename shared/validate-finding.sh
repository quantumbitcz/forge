#!/usr/bin/env bash
# Thin shim → shared/validate_finding.py.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
exec env PYTHONPATH="${PLUGIN_ROOT}${PYTHONPATH:+:${PYTHONPATH}}" \
  python3 -m shared.validate_finding "$@"
