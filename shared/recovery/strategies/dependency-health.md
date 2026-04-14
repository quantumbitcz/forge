---
name: dependency-health
description: Checks and recovers external dependencies (Docker, database, network, CLI tools). Determines degraded mode when full recovery is not possible.
---

# Dependency Health Strategy

Handles failures caused by unavailable external dependencies. Attempts automatic recovery where safe, determines degraded operation mode when recovery is not possible.

---

## 1. Pre-stage Health Check Matrix

Run health checks before each stage begins. Required dependencies vary by stage:

| Stage | Required | Optional |
|-------|----------|----------|
| PREFLIGHT | git, python3 | — |
| EXPLORE | git | — |
| PLAN | git | context7 (MCP) |
| VALIDATE | git | — |
| IMPLEMENT | git, build tool | docker, database, context7 |
| VERIFY | git, build tool, test runner | docker, database |
| REVIEW | git | — |
| DOCS | git | — |
| SHIP | git | gh |
| PREVIEW | network | playwright |
| LEARN | git | — |

**Build tool** and **test runner** are detected from `forge.local.md` `commands` config (e.g., `./gradlew`, `npm`, `pnpm`).

Use `shared/recovery/health-checks/pre-stage-health.sh <stage>` for the check. If it reports missing dependencies, proceed to diagnosis below.

---

## 2. Dependency Diagnosis and Recovery

### 2.1 Docker

**Detection:** `docker info` fails or returns error.

**Common errors and remediation:**

| Error | Cause | Recovery |
|-------|-------|----------|
| `Cannot connect to the Docker daemon` | Docker not running | Attempt: `open -a Docker` (MacOS) or `sudo systemctl start docker` (Linux). Wait up to 30s for startup. |
| `permission denied` | User not in docker group | Return `ESCALATE` — requires `sudo usermod -aG docker $USER` and re-login. |
| `docker: command not found` | Not installed | Return `ESCALATE` with install suggestion. |

**After recovery attempt:** Re-run `docker info`. If success, return `RECOVERED`.

### 2.2 Database

**Detection:** TCP connection to configured database port fails.

**Common scenarios:**

| Scenario | Recovery |
|----------|----------|
| Docker Compose DB container stopped | Run `docker compose up -d <db-service>`. Wait up to 30s. Check port again. |
| Port conflict | Report which process holds the port (`lsof -i :<port>`). Return `ESCALATE`. |
| DB container exists but unhealthy | `docker compose restart <db-service>`. Wait 30s. |
| No docker-compose.yml | Return `ESCALATE` — cannot auto-configure database. |

**After recovery:** Retry TCP connection. If success, return `RECOVERED`.

### 2.3 Network Connectivity

**Detection:** `curl -s --max-time 5 https://api.github.com` fails.

**Diagnosis:**

1. **DNS resolution:** `nslookup github.com`. If fails → DNS issue (likely system-level).
2. **General connectivity:** `curl -s --max-time 5 https://1.1.1.1` or `ping -c 1 -W 5 8.8.8.8`. If fails → no internet.
3. **Proxy:** Check `$HTTP_PROXY` / `$HTTPS_PROXY` environment variables.

**Recovery:** Network issues are generally not recoverable by the pipeline. Determine degraded mode:

| Stage | Without Network | Degraded? |
|-------|----------------|-----------|
| IMPLEMENT | Can build/test locally | No (unless deps need downloading) |
| VERIFY | Local tests work | No |
| SHIP | Cannot push/create PR | Yes — commit locally, skip PR |
| PREVIEW | Cannot validate | Yes — skip preview |
| Other stages | No network needed | No |

### 2.4 GitHub CLI (`gh`)

**Detection:** `gh auth status` fails.

| Error | Recovery |
|-------|----------|
| `not logged in` | Return `ESCALATE` — user must run `gh auth login`. |
| `gh: command not found` | Return `ESCALATE` with install suggestion. |
| Network error | Route to network diagnosis (2.3). |

**`gh` is optional for all stages except SHIP.** If unavailable during non-SHIP stages, return `DEGRADED` with note.

### 2.5 Build Tool

**Detection:** Configured build command not found or not executable.

| Tool | Check | Recovery |
|------|-------|----------|
| `./gradlew` | File exists and is executable | `chmod +x ./gradlew` |
| `gradle` | `which gradle` | Return `ESCALATE` with install suggestion |
| `npm` / `pnpm` | `which npm` / `which pnpm` | Return `ESCALATE` with install suggestion |
| `node_modules/.bin/*` | Directory exists | Run `npm install` or `pnpm install` |

### 2.6 MCP Servers

**Detection:** MCP tool call times out or returns connection error.

**Recovery:** MCP servers are managed externally. The pipeline cannot restart them.

- If the MCP tool is optional (context7 for docs): return `DEGRADED`.
- If the MCP tool is required (no alternative): return `ESCALATE`.

---

## 3. Degraded Mode Determination

When a dependency cannot be recovered, determine what pipeline capabilities are lost:

| Lost Dependency | Degraded Capability | Impact |
|-----------------|---------------------|--------|
| Docker | `"test"` | Skip integration tests, run unit tests only |
| Database | `"test"` | Skip DB-related tasks, note in review |
| Network | `"build"` | Proceed with local resources only |
| gh CLI | `"git"` | Commit locally, manual PR needed |
| context7 | `"context7"` | Use conventions file + codebase grep |
| Playwright | `"playwright"` | Skip preview stage |

Add each degraded capability to `state.json` `recovery.degraded_capabilities` array.

> **Naming convention:** Capability names must match the short, lowercase convention defined in `shared/recovery/recovery-engine.md` section on Degraded Capability Handling. MCP capabilities use `state.json.integrations` keys (`"context7"`, `"linear"`, `"playwright"`, `"slack"`, `"figma"`). Infrastructure capabilities use tool-type names (`"build"`, `"test"`, `"git"`).

---

## 4. Output

Return to recovery engine:

```json
{
  "result": "RECOVERED | DEGRADED | ESCALATE",
  "details": "Diagnosis and recovery attempt description",
  "dependency": "docker",
  "recovery_action": "Started Docker daemon, waited 20s",
  "degraded_capabilities": ["test"],
  "install_suggestion": null
}
```
