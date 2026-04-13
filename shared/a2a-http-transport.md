# A2A HTTP Transport Specification

Detailed specification for the HTTP transport layer added in v2.0. This document covers endpoints, request/response formats, authentication, error handling, and configuration. For protocol overview and lifecycle mapping, see `shared/a2a-protocol.md`.

---

## Endpoints

### GET /.well-known/agent-card.json

Agent card discovery endpoint. Follows the Google A2A spec convention.

**Authentication:** None (public endpoint).

**Response:**

```
HTTP/1.1 200 OK
Content-Type: application/json

{
  "name": "forge",
  "description": "Forge autonomous pipeline for backend-service",
  "url": "http://192.168.1.10:9473",
  "version": "2.0.0",
  "protocol_version": "a2a/0.2.1",
  "project_id": "git@github.com:org/backend-service.git",
  "transport": "http",
  "capabilities": {
    "streaming": true,
    "stateTransitionHistory": true,
    "pushNotifications": true
  },
  "authentication": {
    "schemes": ["bearer"],
    "credentials_ref": ".forge/a2a-credentials.json"
  },
  "skills": [
    {
      "id": "forge-run",
      "name": "Pipeline Execution",
      "description": "10-stage autonomous pipeline: Preflight through Learn"
    }
  ],
  "defaultInputModes": ["application/json"],
  "defaultOutputModes": ["application/json"]
}
```

---

### POST /tasks/send

Submit a task or message to this forge instance. Follows JSON-RPC 2.0 format.

**Authentication:** Required (Bearer token or mTLS).

**Request:**

```
POST /tasks/send HTTP/1.1
Content-Type: application/json
Authorization: Bearer forge-a2a-{token}

{
  "jsonrpc": "2.0",
  "method": "tasks/send",
  "id": "req-001",
  "params": {
    "id": "task-backend-api-v2",
    "message": {
      "role": "user",
      "parts": [
        {
          "type": "text",
          "text": "Contract validation result: PASS. Backend API v2 endpoints ready."
        }
      ]
    },
    "metadata": {
      "source_project": "git@github.com:org/backend-service.git",
      "pipeline_stage": "SHIPPING",
      "story_id": "FG-42"
    }
  }
}
```

**Response (success):**

```
HTTP/1.1 200 OK
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "id": "req-001",
  "result": {
    "id": "task-backend-api-v2",
    "state": "accepted",
    "timestamp": "2026-04-13T10:05:00Z"
  }
}
```

**Response (error):**

```
HTTP/1.1 200 OK
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "id": "req-001",
  "error": {
    "code": -32600,
    "message": "Invalid task ID format"
  }
}
```

---

### GET /tasks/{id}

Get current task state. Maps from `state.json` using the A2A lifecycle mapping defined in `a2a-protocol.md`.

**Authentication:** Required.

**Response:**

```
HTTP/1.1 200 OK
Content-Type: application/json

{
  "id": "task-backend-api-v2",
  "state": "in-progress",
  "story_state": "REVIEWING",
  "score": 85,
  "stage_progress": {
    "current": "REVIEWING",
    "completed": ["PREFLIGHT", "EXPLORING", "PLANNING", "VALIDATING", "IMPLEMENTING", "VERIFYING"]
  },
  "timestamp": "2026-04-13T10:15:00Z"
}
```

**State values:** `pending`, `in-progress`, `input-required`, `completed`, `failed` (per A2A lifecycle mapping in `a2a-protocol.md`).

**404 — Task not found:**

```
HTTP/1.1 404 Not Found
Content-Type: application/json

{
  "error": "task_not_found",
  "message": "No task with ID 'task-unknown' exists in this forge instance"
}
```

---

### POST /tasks/{id}/cancel

Request cancellation of a running task.

**Authentication:** Required.

**Request:**

```
POST /tasks/task-backend-api-v2/cancel HTTP/1.1
Authorization: Bearer forge-a2a-{token}
```

**Response (success):**

```
HTTP/1.1 200 OK
Content-Type: application/json

{
  "id": "task-backend-api-v2",
  "state": "failed",
  "reason": "cancelled_by_remote",
  "timestamp": "2026-04-13T10:20:00Z"
}
```

**Response (task already completed):**

```
HTTP/1.1 409 Conflict
Content-Type: application/json

{
  "error": "task_already_completed",
  "message": "Task 'task-backend-api-v2' is in state 'completed' and cannot be cancelled"
}
```

---

### DELETE /tasks/{id}

Remove a completed or failed task from the local registry. Does not affect `state.json`.

**Authentication:** Required.

**Response:**

```
HTTP/1.1 204 No Content
```

**409 — Task still active:**

```
HTTP/1.1 409 Conflict
Content-Type: application/json

{
  "error": "task_active",
  "message": "Task 'task-backend-api-v2' is still in-progress and cannot be deleted"
}
```

---

### WS /tasks/{id}/subscribe

WebSocket endpoint for real-time state change notifications. Optional enhancement — requires the `websockets` Python library. When unavailable, the server returns 501 and clients fall back to HTTP polling.

**Authentication:** Required (token passed as query parameter: `?token={token}`).

**Connection:**

```
WS /tasks/task-backend-api-v2/subscribe?token=forge-a2a-{token}
```

**Server push messages:**

```json
{ "event": "state_change", "from": "IMPLEMENTING", "to": "VERIFYING", "timestamp": "2026-04-13T10:10:00Z" }
{ "event": "score_update", "score": 85, "delta": 5, "timestamp": "2026-04-13T10:12:00Z" }
{ "event": "completed", "final_state": "SHIPPING", "score": 92, "timestamp": "2026-04-13T10:25:00Z" }
```

**Reconnection:** Clients reconnect with exponential backoff (1s, 2s, 4s, max 30s). After 3 consecutive failures, fall back to HTTP polling via `GET /tasks/{id}`.

**501 — WebSocket not available:**

```
HTTP/1.1 501 Not Implemented
Content-Type: application/json

{
  "error": "websocket_unavailable",
  "message": "WebSocket support requires the 'websockets' Python library. Use GET /tasks/{id} for polling."
}
```

---

### GET /health

Server health check. Returns 200 when the server is running and can read `state.json`.

**Authentication:** None.

**Response:**

```
HTTP/1.1 200 OK
Content-Type: application/json

{
  "status": "healthy",
  "transport": "http",
  "uptime_seconds": 3600,
  "websocket_available": true,
  "active_connections": 2
}
```

---

### GET /files/{path}

Serve project files for cross-repo contract validation. Read-only. Restricted to `.forge/` directory and paths explicitly listed in `a2a.allowed_file_paths` (default: none beyond `.forge/`).

**Authentication:** Required.

**Response:**

```
HTTP/1.1 200 OK
Content-Type: application/json

{ ... file contents ... }
```

**403 — Path not allowed:**

```
HTTP/1.1 403 Forbidden
Content-Type: application/json

{
  "error": "path_restricted",
  "message": "Access to 'src/main/...' is not permitted. Only .forge/ and explicitly allowed paths are served."
}
```

---

## Authentication Flow

### Token Authentication (Default)

1. At PREFLIGHT, the server generates a token if missing or expired:
   ```json
   {
     "token": "forge-a2a-{random-32-hex}",
     "generated_at": "2026-04-13T10:00:00Z",
     "expires_at": "2026-04-14T10:00:00Z",
     "allowed_projects": ["git@github.com:org/frontend-app.git"]
   }
   ```
2. Credentials are stored in `.forge/a2a-credentials.json` (gitignored).
3. Remote agents exchange tokens out-of-band (manually or via `a2a.remote_agents` config).
4. Clients send: `Authorization: Bearer forge-a2a-{token}`.
5. On 401 response, clients re-read `.forge/a2a-credentials.json` and retry once (handles mid-run token rotation).
6. Tokens rotate every `a2a.token_ttl_hours` (default 24, range 1-168).

### mTLS Authentication (Optional)

1. Requires pre-provisioned certificates:
   - `a2a.tls.cert_path` — server certificate
   - `a2a.tls.key_path` — server private key
   - `a2a.tls.ca_path` — CA certificate for client verification
2. Server starts with TLS enabled. Clients must present a valid client certificate signed by the same CA.
3. Invalid certificates: CRITICAL logged, server does not start, filesystem fallback.

### No Authentication

Only permitted when `a2a.http_bind: 127.0.0.1`. PREFLIGHT validation rejects `auth_mode: none` with any other bind address.

---

## Error Handling

### HTTP Status Codes

| Code | Meaning | Client Action |
|---|---|---|
| 200 | Success | Process response |
| 204 | Success (no content) | Task deleted |
| 401 | Unauthorized | Refresh token from credentials file, retry once |
| 403 | Forbidden | Path not allowed / project not in `allowed_projects` |
| 404 | Not Found | Task does not exist |
| 409 | Conflict | Task state prevents operation (already completed/still active) |
| 500 | Internal Server Error | Log WARNING, retry with backoff |
| 501 | Not Implemented | WebSocket unavailable, use HTTP polling |
| 503 | Service Unavailable | Server starting up, retry after 1s |

### JSON-RPC 2.0 Error Codes

| Code | Meaning |
|---|---|
| -32600 | Invalid request (malformed JSON-RPC) |
| -32601 | Method not found |
| -32602 | Invalid params |
| -32603 | Internal error |

### Retry Policy

- **Remote agent unreachable:** 3 attempts with exponential backoff (5s, 15s, 30s).
- **401 Unauthorized:** 1 retry with refreshed token. No further retries on second 401.
- **500 Internal Server Error:** 2 retries with 5s delay.
- **WebSocket disconnect:** Reconnect with backoff (1s, 2s, 4s, max 30s). Fall back to polling after 3 failures.
- **All retries exhausted:** Mark agent as `unreachable`. Fall back to filesystem if path available. Log WARNING.

### Fallback Decision Tree

```
Attempt HTTP request to remote agent
  ├─ Success → process response
  ├─ 401 → refresh token → retry once
  │    ├─ Success → process response
  │    └─ 401 again → mark unreachable
  ├─ Network error / timeout → retry with backoff (3 attempts)
  │    ├─ Success → process response
  │    └─ Exhausted → check filesystem path
  │         ├─ Path exists → use filesystem transport (log WARNING)
  │         └─ No path → mark unreachable, exclude from coordination
  └─ 5xx → retry twice with 5s delay
       ├─ Success → process response
       └─ Exhausted → same as network error path
```

---

## Configuration Reference

Full `a2a:` section in `forge-config.md`:

```yaml
a2a:
  transport: filesystem           # filesystem (default) | http
  http_port: 9473                 # Port for A2A HTTP server (1024-65535)
  http_bind: "0.0.0.0"           # Bind address. "127.0.0.1" for local-only.
  auth_mode: token                # token | mtls | none
  token_ttl_hours: 24             # Token rotation interval (1-168)
  discovery_enabled: false        # Enable local network discovery broadcast
  discovery_port: 9474            # UDP broadcast port for discovery (1024-65535)
  websocket_enabled: true         # Enable WebSocket for real-time updates
  remote_agents:                  # Explicit remote agent URLs (when discovery is off)
    - url: "http://192.168.1.10:9473"
      project_id: "git@github.com:org/backend-service.git"
    - url: "http://192.168.1.11:9473"
      project_id: "git@github.com:org/frontend-app.git"
  tls:                            # mTLS configuration (when auth_mode: mtls)
    cert_path: ".forge/a2a-cert.pem"
    key_path: ".forge/a2a-key.pem"
    ca_path: ".forge/a2a-ca.pem"
```

### Parameter Reference

| Parameter | Type | Default | Range | Description |
|---|---|---|---|---|
| `a2a.transport` | string | `filesystem` | `filesystem`, `http` | Transport layer selection |
| `a2a.http_port` | integer | `9473` | 1024-65535 | HTTP server port |
| `a2a.http_bind` | string | `"0.0.0.0"` | Valid IP or `"0.0.0.0"` | Network interface to bind |
| `a2a.auth_mode` | string | `token` | `token`, `mtls`, `none` | Authentication scheme. `none` only with `127.0.0.1`. |
| `a2a.token_ttl_hours` | integer | `24` | 1-168 | Token expiry window in hours |
| `a2a.discovery_enabled` | boolean | `false` | -- | Enable UDP-based local discovery |
| `a2a.discovery_port` | integer | `9474` | 1024-65535 | Discovery broadcast port |
| `a2a.websocket_enabled` | boolean | `true` | -- | Enable WebSocket push notifications |
| `a2a.remote_agents` | array | `[]` | -- | Explicit remote agent URLs |
| `a2a.tls.cert_path` | string | -- | Valid file path | Server certificate for mTLS |
| `a2a.tls.key_path` | string | -- | Valid file path | Server private key for mTLS |
| `a2a.tls.ca_path` | string | -- | Valid file path | CA certificate for mTLS |

### Minimal Configuration (Template Default)

The following is included in every `forge-config-template.md`:

```yaml
# A2A Protocol (v2.0+)
a2a:
  transport: filesystem          # filesystem (default) | http
  http_port: 9473
  auth_mode: token
```

This keeps filesystem as the default. To enable HTTP transport, change `transport: http` and optionally configure `remote_agents` and other parameters.

### PREFLIGHT Validation

The orchestrator validates A2A configuration at PREFLIGHT:

1. `a2a.transport` must be `filesystem` or `http`.
2. If `http`: `a2a.http_port` must be in range 1024-65535.
3. If `auth_mode: none` and `http_bind` is not `127.0.0.1`: reject with CRITICAL.
4. If `auth_mode: mtls`: all three `tls.*` paths must exist and be readable.
5. If `transport: http` and Python 3 is unavailable: WARNING, fall back to filesystem.
6. `a2a.token_ttl_hours` must be in range 1-168 (when `auth_mode: token`).

---

## Server Implementation

The A2A HTTP server is implemented as a Python `http.server` subprocess managed by shell scripts:

- **`shared/a2a/a2a-server.sh`** — starts the Python server, manages PID file, handles port conflicts.
- **`shared/a2a/a2a-client.sh`** — shell functions for HTTP requests (agent card fetch, task polling, task submission).
- **`shared/a2a/transport.sh`** — unified transport interface that routes to filesystem or HTTP based on config.
- **`shared/a2a/discovery.sh`** — optional UDP-based local network discovery.
- **`shared/a2a/auth.sh`** — token generation/validation and mTLS certificate management.

### Resource Usage

| Metric | Expected | Notes |
|---|---|---|
| Memory | 10-30MB | Python http.server with optional asyncio WebSocket |
| CPU | <1% idle, <5% during state changes | Reads from disk, serves JSON |
| Open connections | 1-10 concurrent | One per consuming repo |
| Disk I/O | Reads `.forge/state.json` per request | Cached in memory, refreshed every 2s |

### Latency Comparison

| Operation | Filesystem | HTTP (LAN) | HTTP (WAN) | WebSocket |
|---|---|---|---|---|
| Agent card discovery | <1ms | 5-50ms | 50-200ms | N/A |
| Task state poll | <1ms | 5-50ms | 50-200ms | <1ms (push) |
| Cross-repo file read | <1ms | 10-100ms | 50-500ms | N/A |
