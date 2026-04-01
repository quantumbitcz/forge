#!/usr/bin/env bash
set -euo pipefail

# Cross-platform timeout wrapper (self-contained to avoid sourcing platform.sh,
# which runs detect_os at load time and needs uname/grep on PATH).
_neo4j_timeout() {
  local seconds="$1"; shift
  if command -v timeout &>/dev/null; then
    timeout "$seconds" "$@"
  elif command -v gtimeout &>/dev/null; then
    gtimeout "$seconds" "$@"
  else
    "$@"
  fi
}

# Check if Docker is available
if ! docker info > /dev/null 2>&1; then
  echo '{"available": false, "reason": "docker not available"}'
  exit 1
fi

# Check if the pipeline-neo4j container is running (with timeout to prevent hangs)
CONTAINER_STATUS=""
CONTAINER_STATUS=$(_neo4j_timeout 5 docker inspect pipeline-neo4j --format '{{.State.Status}}' 2>/dev/null || true)

if [ "$CONTAINER_STATUS" != "running" ]; then
  echo '{"available": false, "reason": "container not running"}'
  exit 1
fi

# Check health status
HEALTH_STATUS=""
HEALTH_STATUS=$(_neo4j_timeout 5 docker inspect pipeline-neo4j --format '{{.State.Health.Status}}' 2>/dev/null || true)

if [ -z "$HEALTH_STATUS" ]; then
  # Container has no health check configured — treat as unknown, not failed
  echo '{"available": false, "reason": "container health status unknown (no health check configured)"}'
  exit 1
elif [ "$HEALTH_STATUS" != "healthy" ]; then
  echo "{\"available\": false, \"reason\": \"container unhealthy (status: ${HEALTH_STATUS})\"}"
  exit 1
fi

echo '{"available": true, "container": "running", "bolt_port": 7687}'
exit 0
