#!/usr/bin/env bash
set -euo pipefail

# Check if Docker is available
if ! docker info > /dev/null 2>&1; then
  echo '{"available": false, "reason": "docker not available"}'
  exit 1
fi

# Check if the pipeline-neo4j container is running (with timeout to prevent hangs)
CONTAINER_STATUS=""
if command -v timeout &>/dev/null; then
  CONTAINER_STATUS=$(timeout 5 docker inspect pipeline-neo4j --format '{{.State.Status}}' 2>/dev/null || true)
elif command -v gtimeout &>/dev/null; then
  CONTAINER_STATUS=$(gtimeout 5 docker inspect pipeline-neo4j --format '{{.State.Status}}' 2>/dev/null || true)
else
  CONTAINER_STATUS=$(docker inspect pipeline-neo4j --format '{{.State.Status}}' 2>/dev/null || true)
fi

if [ "$CONTAINER_STATUS" != "running" ]; then
  echo '{"available": false, "reason": "container not running"}'
  exit 1
fi

# Check health status
HEALTH_STATUS=""
if command -v timeout &>/dev/null; then
  HEALTH_STATUS=$(timeout 5 docker inspect pipeline-neo4j --format '{{.State.Health.Status}}' 2>/dev/null || true)
elif command -v gtimeout &>/dev/null; then
  HEALTH_STATUS=$(gtimeout 5 docker inspect pipeline-neo4j --format '{{.State.Health.Status}}' 2>/dev/null || true)
else
  HEALTH_STATUS=$(docker inspect pipeline-neo4j --format '{{.State.Health.Status}}' 2>/dev/null || true)
fi

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
