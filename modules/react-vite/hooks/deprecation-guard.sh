#!/usr/bin/env bash
# DEPRECATED: Use shared/checks/engine.sh instead.
# Will be removed in the next release.

# Avoid duplicate checks if engine.sh was already invoked by plugin hook
if [ -n "${_ENGINE_RUNNING:-}" ]; then exit 0; fi

echo "WARNING: $(basename "$0") is deprecated. Use engine.sh --hook instead." >&2
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" _ENGINE_RUNNING=1 exec "$PLUGIN_ROOT/shared/checks/engine.sh" --hook
