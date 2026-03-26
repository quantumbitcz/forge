#!/usr/bin/env bash
set -euo pipefail

# Check if Docker is available
if ! docker info > /dev/null 2>&1; then
  echo '{"available": false, "reason": "docker not available"}'
  exit 1
fi

# Check if the pipeline-neo4j container is running
CONTAINER_STATUS=$(docker inspect pipeline-neo4j --format '{{.State.Status}}' 2>/dev/null || true)

if [ "$CONTAINER_STATUS" != "running" ]; then
  echo '{"available": false, "reason": "container not running"}'
  exit 1
fi

# Check health status
HEALTH_STATUS=$(docker inspect pipeline-neo4j --format '{{.State.Health.Status}}' 2>/dev/null || true)

if [ "$HEALTH_STATUS" != "healthy" ]; then
  echo '{"available": false, "reason": "container not running"}'
  exit 1
fi

echo '{"available": true, "container": "running", "bolt_port": 7687}'
exit 0
