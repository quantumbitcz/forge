#!/usr/bin/env bash
# dependency-check.sh — Checks a specific external dependency's availability.
# Usage: dependency-check.sh <dependency_name>
# Output: "OK" or "UNAVAILABLE: reason"
# Exit: always 0

set -euo pipefail

DEP="${1:-}"

if [[ -z "$DEP" ]]; then
  echo "UNAVAILABLE: no dependency name provided (usage: dependency-check.sh <name>)"
  exit 0
fi

# Normalize to lowercase
DEP="$(echo "$DEP" | tr '[:upper:]' '[:lower:]')"

case "$DEP" in
  docker)
    if ! command -v docker &>/dev/null; then
      echo "UNAVAILABLE: docker command not found"
      exit 0
    fi
    # Check if Docker daemon is running
    if docker info &>/dev/null; then
      echo "OK"
    else
      echo "UNAVAILABLE: Docker daemon is not running (try: open -a Docker or sudo systemctl start docker)"
    fi
    ;;

  database|db)
    # Attempt TCP connection to common database ports
    # Check for docker-compose to find configured port
    DB_PORT=""
    if [[ -f "docker-compose.yml" || -f "docker-compose.yaml" || -f "compose.yml" || -f "compose.yaml" ]]; then
      # Try to extract port from compose file (common patterns)
      for compose_file in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
        if [[ -f "$compose_file" ]]; then
          # Look for common DB port mappings
          DB_PORT=$(grep -oE '[0-9]+:5432' "$compose_file" 2>/dev/null | head -1 | cut -d: -f1) # PostgreSQL
          if [[ -z "$DB_PORT" ]]; then
            DB_PORT=$(grep -oE '[0-9]+:3306' "$compose_file" 2>/dev/null | head -1 | cut -d: -f1) # MySQL
          fi
          if [[ -z "$DB_PORT" ]]; then
            DB_PORT=$(grep -oE '[0-9]+:27017' "$compose_file" 2>/dev/null | head -1 | cut -d: -f1) # MongoDB
          fi
          [[ -n "$DB_PORT" ]] && break
        fi
      done
    fi

    # Default to PostgreSQL port if nothing found
    if [[ -z "$DB_PORT" ]]; then
      DB_PORT="5432"
    fi

    # Try TCP connection
    if command -v nc &>/dev/null; then
      if nc -z -w 3 localhost "$DB_PORT" 2>/dev/null; then
        echo "OK"
      else
        echo "UNAVAILABLE: cannot connect to localhost:$DB_PORT (database may not be running)"
      fi
    elif command -v bash &>/dev/null; then
      if (echo >/dev/tcp/localhost/"$DB_PORT") 2>/dev/null; then
        echo "OK"
      else
        echo "UNAVAILABLE: cannot connect to localhost:$DB_PORT (database may not be running)"
      fi
    else
      echo "UNAVAILABLE: no tool available to check TCP connection (nc or bash /dev/tcp)"
    fi
    ;;

  network|net)
    if curl -s --max-time 5 https://api.github.com >/dev/null 2>&1; then
      echo "OK"
    elif curl -s --max-time 5 https://1.1.1.1 >/dev/null 2>&1; then
      echo "UNAVAILABLE: DNS resolution may be failing (raw IP works but github.com does not)"
    elif ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
      echo "UNAVAILABLE: ICMP works but HTTP does not (possible proxy or firewall issue)"
    else
      echo "UNAVAILABLE: no network connectivity detected"
    fi
    ;;

  gh|github)
    if ! command -v gh &>/dev/null; then
      echo "UNAVAILABLE: gh command not found (install: brew install gh)"
      exit 0
    fi
    if gh auth status &>/dev/null; then
      echo "OK"
    else
      echo "UNAVAILABLE: gh is not authenticated (run: gh auth login)"
    fi
    ;;

  node|npm)
    if command -v node &>/dev/null; then
      echo "OK"
    else
      echo "UNAVAILABLE: node not found (install: brew install node or use nvm)"
    fi
    ;;

  gradle|gradlew)
    if [[ -f "./gradlew" ]]; then
      if [[ -x "./gradlew" ]]; then
        echo "OK"
      else
        echo "UNAVAILABLE: gradlew exists but is not executable (fix: chmod +x gradlew)"
      fi
    elif command -v gradle &>/dev/null; then
      echo "OK"
    else
      echo "UNAVAILABLE: neither gradlew nor gradle found"
    fi
    ;;

  playwright)
    if command -v npx &>/dev/null; then
      if npx playwright --version &>/dev/null 2>&1; then
        echo "OK"
      else
        echo "UNAVAILABLE: playwright not installed (run: npx playwright install)"
      fi
    else
      echo "UNAVAILABLE: npx not found — cannot check playwright"
    fi
    ;;

  context7)
    # Quick probe — attempt to check if context7 MCP is responsive
    # This is a passive check; we can't call MCP from bash.
    # Instead, check if the tool list mentions context7 (passed via env)
    if [[ -n "${CONTEXT7_AVAILABLE:-}" ]]; then
      echo "INFO: Context7 MCP reported as available" >&2
    else
      echo "INFO: Context7 MCP not detected — using conventions file for documentation" >&2
    fi
    echo "OK"
    ;;

  git-remote|remote)
    project_root="${2:-$(pwd)}"
    remote_url="$(git -C "$project_root" remote get-url origin 2>/dev/null || true)"
    if [[ -z "$remote_url" ]]; then
      echo "WARN: No git remote 'origin' configured — PR creation will fail" >&2
      echo "OK"
      exit 0
    fi
    if timeout 5 git -C "$project_root" ls-remote --exit-code origin HEAD &>/dev/null; then
      echo "INFO: Git remote reachable: $remote_url" >&2
      echo "OK"
    else
      echo "WARN: Git remote unreachable: $remote_url — PR creation may fail" >&2
      echo "OK"
    fi
    ;;

  *)
    echo "UNAVAILABLE: unknown dependency '$DEP' (supported: docker, database, network, gh, node, gradle, playwright, context7, git-remote)"
    ;;
esac

exit 0
