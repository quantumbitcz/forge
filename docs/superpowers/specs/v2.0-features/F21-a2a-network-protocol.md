# F21: A2A Protocol Over Network Transport

## Status
DRAFT — 2026-04-13 (Forward-Looking)

## Problem Statement

Forge's A2A protocol (`shared/a2a-protocol.md`) is filesystem-based: agent cards live at `.forge/agent-card.json`, task state is read by polling `.forge/state.json`, and cross-repo coordination (fg-103) requires shared filesystem access between repositories. This works for monorepos and colocated multi-repos on a single machine, but fails in real-world multi-team scenarios:

1. **Different machines:** Backend team on machine A, frontend team on machine B. No shared filesystem path exists between them. fg-103 cannot read the producer's `.forge/state.json`.
2. **CI environments:** CI runners for separate repos have no filesystem overlap. Cross-repo contract validation and dependency coordination are impossible.
3. **Remote development:** Developers using cloud-based dev environments (Codespaces, Gitpod, DevPod) cannot share filesystem paths with local machines.
4. **Team scaling:** As teams grow beyond 2-3 developers, the "everyone symlinks to the same directory" pattern breaks down.

Google's A2A protocol (adopted by 100+ enterprises as of early 2026) solves this with HTTP-based agent cards at `/.well-known/agent.json` and JSON-RPC 2.0 task management over HTTP. Forge already preserves JSON-RPC 2.0 message schemas for "future HTTP bridging" (per `a2a-protocol.md`), but no HTTP transport exists.

The gap: filesystem transport cannot scale beyond a single machine. The protocol adaptation is ready (lifecycle mapping, agent card schema), but the transport layer is missing.

## Proposed Solution

Add an HTTP transport layer alongside the existing filesystem transport. Agent cards are served at a local HTTP endpoint following the Google A2A spec. Task submission, status polling, and cancellation use HTTP verbs against a lightweight local server. WebSocket support enables real-time task state notifications, eliminating polling overhead. The filesystem transport remains the default; HTTP is opt-in via `a2a.transport: http` in `forge-config.md`.

## Detailed Design

### Architecture

```
                    Machine A (Backend)                         Machine B (Frontend)
              +---------------------------+              +---------------------------+
              | forge pipeline (producer) |              | forge pipeline (consumer) |
              +---------------------------+              +---------------------------+
                     |           |                              |           |
            +--------+           +--------+            +--------+           +--------+
            v                             v            v                             v
    .forge/state.json           A2A HTTP Server     A2A HTTP Client          .forge/state.json
    (local, unchanged)         (port 9473)          (in fg-103)             (local, unchanged)
                                    |                      |
                                    +--- HTTP/WS -----------+
                                    |                      |
                        GET /.well-known/agent-card.json
                        POST /tasks/send
                        GET  /tasks/{id}
                        POST /tasks/{id}/cancel
                        WS   /tasks/{id}/subscribe
```

**Components:**

1. **A2A HTTP server** (`shared/a2a/a2a-server.sh`) — lightweight HTTP server wrapping the local `.forge/state.json` and `.forge/agent-card.json` as HTTP endpoints. Implemented as a Python `http.server` subprocess managed by the orchestrator. Starts at PREFLIGHT, stops at LEARNING/ABORT.

2. **A2A HTTP client** (`shared/a2a/a2a-client.sh`) — shell functions that fg-103 and other coordination agents use to discover remote agent cards and poll task state over HTTP instead of filesystem reads.

3. **A2A discovery registry** (`shared/a2a/discovery.sh`) — optional local discovery service that agents can register with. Provides a single endpoint listing all known forge instances on the local network. Falls back to explicit URL configuration when discovery is unavailable.

4. **Transport abstraction** (`shared/a2a/transport.sh`) — unified interface that routes read/write operations to either filesystem or HTTP transport based on configuration. All existing callers (fg-103, sprint orchestrator) use this abstraction rather than direct filesystem reads.

5. **Authentication module** (`shared/a2a/auth.sh`) — token generation, validation, and mTLS certificate management for securing HTTP transport.

### Schema / Data Model

#### Agent Card (HTTP Transport Extension)

The existing agent card schema (`shared/a2a-protocol.md`) is extended with HTTP-specific fields:

```json
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

| Field | Type | Required | Description |
|---|---|---|---|
| `url` | string | Yes | `"local://forge"` for filesystem, `"http://{host}:{port}"` for HTTP |
| `transport` | string | No | `"filesystem"` (default) or `"http"`. Derived from `url` scheme if omitted. |
| `capabilities.streaming` | boolean | Yes | `true` when HTTP transport with WebSocket is active |
| `capabilities.pushNotifications` | boolean | Yes | `true` when WebSocket is active |
| `authentication.schemes` | string[] | No | `["bearer"]` or `["mtls"]`. Absent for filesystem transport. |
| `authentication.credentials_ref` | string | No | Path to credentials file (never embedded in card). |

#### Task Message Schema (JSON-RPC 2.0)

Task submission follows the Google A2A JSON-RPC format:

```json
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

#### Credentials File (`.forge/a2a-credentials.json`)

```json
{
  "token": "forge-a2a-{random-32-hex}",
  "generated_at": "2026-04-13T10:00:00Z",
  "expires_at": "2026-04-14T10:00:00Z",
  "allowed_projects": [
    "git@github.com:org/frontend-app.git",
    "git@github.com:org/mobile-app.git"
  ]
}
```

This file is gitignored (inside `.forge/`). Tokens are rotated every 24 hours by default. `allowed_projects` restricts which remote forge instances can authenticate.

### Configuration

In `forge-config.md`:

```yaml
a2a:
  transport: filesystem           # filesystem | http
  http_port: 9473                 # Port for A2A HTTP server
  http_bind: "0.0.0.0"           # Bind address. "127.0.0.1" for local-only.
  auth_mode: token                # token | mtls | none
  token_ttl_hours: 24             # Token rotation interval
  discovery_enabled: false        # Enable local network discovery broadcast
  discovery_port: 9474            # UDP broadcast port for discovery
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

| Parameter | Type | Default | Range | Description |
|---|---|---|---|---|
| `a2a.transport` | string | `filesystem` | `filesystem`, `http` | Transport layer selection |
| `a2a.http_port` | integer | `9473` | 1024-65535 | HTTP server port |
| `a2a.http_bind` | string | `"0.0.0.0"` | Valid IP or `"0.0.0.0"` | Network interface to bind to |
| `a2a.auth_mode` | string | `token` | `token`, `mtls`, `none` | Authentication scheme. `none` only allowed with `http_bind: 127.0.0.1`. |
| `a2a.token_ttl_hours` | integer | `24` | 1-168 | Token expiry window |
| `a2a.discovery_enabled` | boolean | `false` | -- | Enable UDP-based local discovery |
| `a2a.discovery_port` | integer | `9474` | 1024-65535 | Discovery broadcast port |
| `a2a.websocket_enabled` | boolean | `true` | -- | Enable WebSocket push notifications |
| `a2a.remote_agents` | array | `[]` | -- | Explicit remote agent URLs |
| `a2a.tls.*` | string | -- | Valid file paths | mTLS certificate paths |

### Data Flow

#### Server Startup (PREFLIGHT)

1. Orchestrator reads `a2a.transport` from config
2. If `filesystem`: no server started (existing behavior). Set `state.json.integrations.a2a.transport = "filesystem"`.
3. If `http`:
   a. Check Python 3 availability (required for HTTP server)
   b. Generate or rotate token if `auth_mode: token` and token expired/missing
   c. Start `a2a-server.sh` as background process, record PID in `.forge/.a2a-server.pid`
   d. Server reads `.forge/agent-card.json` and updates `url` to reflect HTTP endpoint
   e. Server begins serving endpoints on configured port
   f. Set `state.json.integrations.a2a.transport = "http"`, `state.json.integrations.a2a.url = "http://{host}:{port}"`
   g. If `discovery_enabled`: broadcast agent card via UDP to discovery port

#### Agent Card Discovery (fg-103)

1. fg-103 reads `a2a.remote_agents` from config for explicit URLs
2. If `discovery_enabled`: also listen for UDP broadcasts to discover additional agents
3. For each remote agent URL:
   a. `GET {url}/.well-known/agent-card.json` with auth header
   b. Parse capabilities, verify `protocol_version` compatibility
   c. If request fails: log WARNING, mark agent as `unreachable`, retry with backoff (3 attempts, 5s/15s/30s)
   d. If all retries fail: fall back to filesystem transport if path is configured in `related_projects`
4. Store discovered agents in `state.json.a2a.discovered_agents[]`

#### Task State Polling (fg-103)

With filesystem transport (existing):
```
fg-103 reads: /path/to/producer/.forge/state.json
```

With HTTP transport (new):
```
fg-103 calls: GET {producer_url}/tasks/{story_id}
Response: { "state": "in-progress", "story_state": "REVIEWING", "score": 85 }
```

With WebSocket (new, optional):
```
fg-103 connects: WS {producer_url}/tasks/{story_id}/subscribe
Server pushes: { "event": "state_change", "from": "REVIEWING", "to": "SHIPPING" }
fg-103 reacts immediately (no polling delay)
```

#### Server Shutdown (LEARNING/ABORT)

1. Orchestrator reads `.forge/.a2a-server.pid`
2. Sends SIGTERM to server process
3. Server drains active WebSocket connections (5s grace period)
4. Server writes final state response to any pending requests
5. PID file removed

### Integration Points

| Agent / System | Integration | Change Required |
|---|---|---|
| `fg-103-cross-repo-coordinator` | Replace direct filesystem reads with transport abstraction calls. HTTP client for remote agents, filesystem for local. | Refactor `setup-worktrees` and `coordinate-implementation` to use `transport.sh`. |
| `fg-090-sprint-orchestrator` | Sprint orchestration across machines via HTTP task polling. | Add HTTP-aware polling in `sprint-state.json` management. |
| `fg-100-orchestrator` | Start/stop HTTP server at PREFLIGHT/LEARNING. | Add server lifecycle management to PREFLIGHT and post-LEARNING cleanup. |
| `fg-250-contract-validator` | Cross-repo contract fetch via HTTP when producer is remote. | Add HTTP GET for contract files from remote agent's file-serving endpoint. |
| `/forge-init` | Generate agent card with correct `url` field based on transport config. | Update card generation to include `transport` and `authentication` fields when HTTP is configured. |
| `shared/a2a-protocol.md` | Document HTTP transport as an alternative to filesystem. | Add HTTP transport section with endpoint reference and auth documentation. |
| `shared/mcp-detection.md` | No change — A2A is not MCP-based. | None. |
| `state-schema.md` | Add `a2a.transport`, `a2a.url`, `a2a.discovered_agents[]` to state schema. | Extend integrations section. |

#### HTTP Endpoints Reference

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/.well-known/agent-card.json` | None (public) | Agent card discovery (per Google A2A spec) |
| POST | `/tasks/send` | Required | Submit a task or message to this agent |
| GET | `/tasks/{id}` | Required | Get task state (maps from `state.json`) |
| POST | `/tasks/{id}/cancel` | Required | Request task cancellation |
| WS | `/tasks/{id}/subscribe` | Required | WebSocket subscription for real-time state updates |
| GET | `/health` | None | Server health check |
| GET | `/files/{path}` | Required | Serve project files for cross-repo contract validation (read-only, restricted to `.forge/` and configured contract paths) |

### Error Handling

| Failure Mode | Behavior | Degradation |
|---|---|---|
| Python 3 not available | Log WARNING: "Python 3 required for A2A HTTP server. Falling back to filesystem transport." Set `a2a.transport = "filesystem"` in state. | Full fallback to filesystem. |
| Port already in use | Try `http_port + 1` through `http_port + 10`. If all fail, log WARNING and fall back to filesystem. | Fallback to filesystem. |
| Remote agent unreachable | 3 retries with exponential backoff (5s, 15s, 30s). After exhaustion, mark agent as `unreachable`. If filesystem path available, fall back. | Partial — unreachable agents excluded from coordination. |
| Authentication failure (401) | Log WARNING with remote agent URL. Do not retry with different credentials. Require manual config fix. | Agent excluded from coordination for this run. |
| Token expired mid-run | Server rotates token automatically. Clients refresh token from `.forge/a2a-credentials.json` on 401 response. | Transparent — one retry with refreshed token. |
| WebSocket disconnected | Client reconnects with exponential backoff (1s, 2s, 4s, max 30s). Falls back to HTTP polling after 3 failed reconnects. | Increased polling latency. |
| Server crashes | Orchestrator detects missing PID, restarts server. If restart fails twice, fall back to filesystem. | Brief interruption, then recovery or fallback. |
| mTLS certificate invalid | Log CRITICAL. Do not start server. Fall back to filesystem. | Full fallback to filesystem. |
| Network partition (mid-coordination) | Polling timeouts trigger `dependency_timeout_minutes` escalation (same as filesystem). | Same timeout behavior as filesystem transport. |

## Performance Characteristics

### Latency Comparison

| Operation | Filesystem Transport | HTTP Transport | WebSocket Transport |
|---|---|---|---|
| Agent card discovery | <1ms (file read) | 5-50ms (HTTP GET, LAN) | N/A |
| Task state poll | <1ms (file read) | 5-50ms (HTTP GET, LAN) | <1ms (push notification) |
| Task state poll (WAN) | N/A (not supported) | 50-200ms (HTTP GET) | <5ms (push after initial connect) |
| Cross-repo file read | <1ms (file read) | 10-100ms (HTTP GET + transfer) | N/A |

### Server Resource Usage

| Metric | Expected | Notes |
|---|---|---|
| Memory | 10-30MB | Python http.server with asyncio WebSocket |
| CPU | <1% idle, <5% during state changes | Minimal — reads from disk, serves JSON |
| Open connections | 1-10 concurrent | One per consuming repo |
| Disk I/O | Reads `.forge/state.json` on each request | Cached in memory, refreshed every 2s |

### Polling vs WebSocket

| Aspect | HTTP Polling | WebSocket |
|---|---|---|
| State change detection latency | `sprint.poll_interval_seconds` (10-120s, default 30s) | <1s |
| Network traffic per hour | ~120 requests/hour (at 30s interval) | ~5-20 messages/hour (only on state changes) |
| Suitable for | WAN connections, firewalled environments | LAN, low-latency requirements |

## Testing Approach

### Unit Tests (`tests/unit/a2a-http.bats`)

1. **Server starts and serves agent card:** Start server, GET `/.well-known/agent-card.json`, verify schema
2. **Task state mapping:** PUT known state in `state.json`, GET `/tasks/{id}`, verify A2A lifecycle mapping
3. **Token authentication:** Request without token returns 401. Request with valid token returns 200.
4. **Token rotation:** Expire token, verify server accepts new token after rotation
5. **Port conflict handling:** Bind port, start server, verify it selects next available port
6. **Graceful shutdown:** Start server, send SIGTERM, verify clean exit within 5s

### Integration Tests (`tests/integration/a2a-http.bats`)

1. **Cross-machine simulation:** Start two servers on different ports (simulating two machines). fg-103 discovers both, polls state, receives completion notification.
2. **Filesystem fallback:** Start HTTP transport, kill server, verify fg-103 falls back to filesystem if path is available.
3. **WebSocket notification:** Connect WebSocket client, change `state.json`, verify push notification received within 1s.
4. **Auth modes:** Test `token`, `mtls`, and `none` (localhost-only) auth configurations.

### Scenario Tests

1. **Full pipeline coordination:** Two forge instances (producer + consumer) coordinating via HTTP. Producer reaches SHIPPING, consumer receives notification and proceeds.
2. **Network partition:** Simulate network failure mid-coordination. Verify timeout escalation and recovery on reconnect.
3. **Mixed transport:** One repo on filesystem, one on HTTP. Verify fg-103 handles both transparently.

## Acceptance Criteria

1. A2A HTTP server starts at PREFLIGHT and serves agent card at `/.well-known/agent-card.json`
2. Task state is accessible via `GET /tasks/{id}` with correct A2A lifecycle mapping
3. Token-based authentication blocks unauthorized requests with 401
4. WebSocket connections receive real-time state change notifications
5. fg-103 discovers remote agents via explicit `remote_agents` config
6. Filesystem transport remains default and works identically to v1.20.1
7. When HTTP transport fails, the system falls back to filesystem transport with a WARNING
8. Server shuts down cleanly on SIGTERM within 5 seconds
9. `./tests/validate-plugin.sh` passes with new scripts added
10. No new external dependencies beyond Python 3 (already required by forge)
11. Configuration validation at PREFLIGHT rejects `auth_mode: none` when `http_bind` is not `127.0.0.1`

## Migration Path

1. **v2.0.0:** Ship HTTP transport as opt-in (`a2a.transport: filesystem` remains default). No changes to existing filesystem transport.
2. **v2.0.0:** Update `shared/a2a-protocol.md` to document HTTP transport alongside filesystem.
3. **v2.0.0:** Update `/forge-init` to generate agent cards with `transport` field.
4. **v2.0.0:** Add `a2a:` section to `forge-config-template.md` for all frameworks.
5. **v2.1.0 (future):** Add mTLS support for enterprise environments.
6. **v2.2.0 (future):** Consider making HTTP transport the default once adoption stabilizes.
7. **No breaking changes:** Existing filesystem-only setups experience zero behavioral change.

## Dependencies

**Depends on:**
- Python 3 (already required by forge for `engine.sh`, `run-patterns.sh`)
- Existing A2A protocol implementation (`shared/a2a-protocol.md`) — agent card schema, lifecycle mapping, fallback behavior
- fg-103 cross-repo coordinator (primary consumer of the transport layer)

**Depended on by:**
- F25 (Consumer-Driven Contracts): HTTP transport enables cross-machine Pact broker integration via A2A
- Future multi-team sprint orchestration scenarios
