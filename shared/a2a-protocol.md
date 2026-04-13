# A2A Protocol (Local Adaptation)

Local adaptation of Google's Agent-to-Agent (A2A) protocol for cross-repo coordination. Defines how forge pipelines running in separate repositories discover each other's capabilities and exchange task state via the filesystem instead of HTTP.

---

## Overview

Google's A2A protocol uses JSON-RPC 2.0 over HTTP for inter-agent communication. Forge adapts this for local, filesystem-based coordination:

- **Transport:** filesystem reads via worktree access (not HTTP)
- **Discovery:** `.forge/agent-card.json` (not `/.well-known/agent.json`)
- **Task exchange:** state.json polling with A2A-compatible lifecycle mapping
- **Authentication:** none (local filesystem, same user)

The protocol is designed to be a superset of file-based polling — when agent cards are absent, the system falls back to current behavior seamlessly.

### JSON-RPC 2.0 Compatibility

A2A uses JSON-RPC 2.0 as its wire format. Forge preserves the message schema for future HTTP bridging but does not run an RPC server. Method names from the A2A spec map to local file operations:

| A2A Method | Forge Local Equivalent |
|---|---|
| `tasks/send` | Write to `.forge/state.json` (orchestrator-managed) |
| `tasks/get` | Read `.forge/state.json` from target repo worktree |
| `tasks/cancel` | Write `story_state: "ABORTED"` to state.json |
| `agent/authenticatedExtendedCard` | Read `.forge/agent-card.json` from target repo |

---

## Task Lifecycle Mapping

A2A defines a set of task states. The following table maps forge pipeline states to A2A task lifecycle states:

| A2A Task State | Forge Pipeline States | Trigger |
|---|---|---|
| `pending` | PREFLIGHT, EXPLORING, PLANNING, VALIDATING | Pipeline initialized but not yet producing output |
| `in-progress` | IMPLEMENTING, VERIFYING, REVIEWING, DOCUMENTING | Active work in progress |
| `input-required` | ESCALATED, CONCERNS (score 60-79) | Pipeline blocked on user decision |
| `completed` | SHIPPING (after evidence SHIP), LEARNING | Pipeline has shipped successfully |
| `failed` | ABORTED, unrecoverable error | Pipeline terminated without shipping |

### State Mapping Rules

1. The A2A state is derived from `story_state` in `state.json` — it is NOT stored separately
2. Cross-repo coordinators (fg-103) compute the A2A state on read using the mapping table above
3. When a consuming repo polls a producer's state, it uses the A2A state to decide readiness (e.g., `completed` means the producer's contract is available)
4. `input-required` signals that the producing repo is stalled — consumers should not wait indefinitely

---

## Agent Card Schema

Each forge-enabled project exposes its capabilities via `.forge/agent-card.json`. This file follows the A2A AgentCard schema adapted for local use.

### Schema

```json
{
  "name": "forge",
  "description": "Forge autonomous pipeline for {project_name}",
  "url": "local://forge",
  "version": "1.19.0",
  "protocol_version": "a2a/0.2.1",
  "project_id": "git@github.com:org/repo.git",
  "capabilities": {
    "streaming": false,
    "stateTransitionHistory": true,
    "pushNotifications": false
  },
  "skills": [
    {
      "id": "forge-run",
      "name": "Pipeline Execution",
      "description": "10-stage autonomous pipeline: Preflight through Learn"
    },
    {
      "id": "forge-review",
      "name": "Code Review",
      "description": "Review changed files with up to 9 specialized agents"
    },
    {
      "id": "forge-fix",
      "name": "Bug Fix",
      "description": "Root cause investigation and targeted fix"
    }
  ],
  "defaultInputModes": ["application/json"],
  "defaultOutputModes": ["application/json"]
}
```

### Field Reference

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | string | Yes | Always `"forge"` |
| `description` | string | Yes | Human-readable project description |
| `url` | string | Yes | Always `"local://forge"` — signals filesystem transport |
| `version` | string | Yes | Forge plugin version that generated the card |
| `protocol_version` | string | Yes | A2A protocol version this card conforms to |
| `project_id` | string | Yes | Git remote URL — matches `state.json.project_id` |
| `capabilities.streaming` | boolean | Yes | Always `false` (no streaming in local mode) |
| `capabilities.stateTransitionHistory` | boolean | Yes | Always `true` (state.json tracks `previous_state`) |
| `capabilities.pushNotifications` | boolean | Yes | Always `false` (polling-based) |
| `skills` | array | Yes | Forge skills available in this project |
| `defaultInputModes` | string[] | Yes | MIME types accepted |
| `defaultOutputModes` | string[] | Yes | MIME types produced |

---

## Agent Card Generation

The agent card is created by `/forge-init` and updated on subsequent init runs.

### Generation Flow

1. `/forge-init` detects the project's git remote to populate `project_id`
2. Skills are populated from the project's `forge.local.md` configuration (only skills relevant to the project's stack)
3. The card is written to `.forge/agent-card.json`
4. The file is gitignored (lives inside `.forge/`)

### Update Rules

- Re-running `/forge-init` regenerates the card with the current forge version
- The card is NOT updated during pipeline runs (it represents static capabilities, not runtime state)
- Deleting `.forge/` removes the card — next `/forge-init` recreates it

---

## Local Adaptation

### Filesystem-Based Transport

Instead of HTTP endpoints, forge uses direct filesystem access:

```
Producer repo:  /path/to/backend/.forge/agent-card.json    (capabilities)
                /path/to/backend/.forge/state.json          (task state)

Consumer repo reads via:
  1. Worktree path from sprint-state.json  →  repos[].path
  2. Direct filesystem read of .forge/ in the target project
```

### Discovery Protocol

Cross-repo discovery follows this order:

1. Read `sprint-state.json` for known project paths
2. For each project path, check for `.forge/agent-card.json`
3. If agent card exists: parse capabilities, map task states via A2A lifecycle
4. If agent card is missing: fall back to file-based polling (pre-A2A behavior)

### Differences from A2A Spec

| A2A Spec | Forge Local |
|---|---|
| HTTP/HTTPS transport | Filesystem read |
| `/.well-known/agent.json` | `.forge/agent-card.json` |
| JSON-RPC server | No server — direct file read |
| Bearer token auth | None (local filesystem) |
| Server-Sent Events streaming | Not supported |
| Push notifications via webhook | Not supported — polling only |

---

## Fallback Behavior

When `.forge/agent-card.json` does not exist in a target repository, the system falls back to current file-based polling behavior. This ensures backward compatibility with projects that have not run `/forge-init` with A2A-capable forge versions.

### Fallback Decision Tree

```
Read .forge/agent-card.json from target repo
  ├─ EXISTS → Use A2A protocol (parse capabilities, map task states)
  └─ MISSING → Fall back to file-based polling
       ├─ Read .forge/state.json directly (if exists)
       ├─ Map story_state to producer readiness without A2A lifecycle
       └─ Log INFO: "A2A agent card not found for {project_id} — using file-based polling"
```

### Behavioral Differences

| Aspect | With Agent Card | Without Agent Card (Fallback) |
|---|---|---|
| Capability discovery | Read `skills[]` from card | Assume full forge pipeline |
| State mapping | A2A lifecycle states | Direct `story_state` comparison |
| Version compatibility | Check `protocol_version` | No version check |
| Logging | Standard | INFO noting fallback |

---

## Cross-Repo Coordination

`fg-103-cross-repo-coordinator` is the primary consumer of agent cards. It reads cards from related repositories to understand their capabilities and track their task states.

### Coordination Flow

1. During `setup-worktrees`, fg-103 reads agent cards from all target repos
2. Agent card `skills[]` informs whether the target repo supports the required operation (e.g., does it have `forge-run`?)
3. During `coordinate-implementation`, fg-103 polls target repos' `state.json` and maps `story_state` to A2A task states using the lifecycle mapping table
4. `completed` state on a producer triggers consumer dispatch (replacing direct `story_state >= "verifying"` checks when A2A is available)
5. `input-required` state on a producer triggers timeout escalation earlier than the default polling timeout

### Task State Reading

```
fg-103 reads: /path/to/producer/.forge/state.json
  → story_state: "REVIEWING"
  → A2A mapping: "in-progress"
  → Decision: producer not ready, continue polling

fg-103 reads: /path/to/producer/.forge/state.json
  → story_state: "SHIPPING"
  → A2A mapping: "completed"
  → Decision: dispatch consumer
```

---

## HTTP Transport (v2.0+)

Starting with v2.0, forge supports HTTP as an alternative transport alongside the existing filesystem transport. HTTP enables cross-machine coordination between forge pipelines running on different hosts, CI runners, or cloud dev environments (Codespaces, Gitpod, DevPod). The filesystem transport remains the default. HTTP is opt-in via `a2a.transport: http` in `forge-config.md`.

Full HTTP transport specification: `shared/a2a-http-transport.md`.

### Transport Abstraction

All coordination agents (fg-103, fg-090, fg-250) use a unified transport interface (`shared/a2a/transport.sh`) that routes operations to the configured transport. Callers do not need to know whether a remote agent is reachable via filesystem or HTTP — the transport layer handles routing transparently.

```
fg-103 calls transport.read_agent_card(target)
  ├─ target.transport == "filesystem" → read .forge/agent-card.json from path
  └─ target.transport == "http"       → GET {url}/.well-known/agent-card.json
```

### Agent Card (HTTP Extension)

When HTTP transport is active, the agent card includes additional fields:

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
  "skills": [ ... ],
  "defaultInputModes": ["application/json"],
  "defaultOutputModes": ["application/json"]
}
```

| Field | Filesystem | HTTP |
|---|---|---|
| `url` | `"local://forge"` | `"http://{host}:{port}"` |
| `transport` | absent or `"filesystem"` | `"http"` |
| `capabilities.streaming` | `false` | `true` (when WebSocket active) |
| `capabilities.pushNotifications` | `false` | `true` (when WebSocket active) |
| `authentication` | absent | `{ "schemes": ["bearer"], "credentials_ref": "..." }` |

### HTTP Endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/.well-known/agent-card.json` | None (public) | Agent card discovery (per Google A2A spec) |
| POST | `/tasks/send` | Required | Submit a task or message |
| GET | `/tasks/{id}` | Required | Get task state (mapped from `state.json`) |
| POST | `/tasks/{id}/cancel` | Required | Request task cancellation |
| WS | `/tasks/{id}/subscribe` | Required | WebSocket for real-time state updates (optional, requires `websockets` library) |
| GET | `/health` | None | Server health check |
| GET | `/files/{path}` | Required | Serve `.forge/` files for cross-repo contract validation (read-only) |

### Discovery

Remote agents are discovered via two mechanisms:

1. **Explicit configuration:** `a2a.remote_agents` in `forge-config.md` lists known agent URLs and project IDs.
2. **Local registry:** When `a2a.discovery_enabled: true`, agents broadcast their presence via UDP on `a2a.discovery_port` (default 9474). Other forge instances on the same network segment discover them automatically.

Explicit configuration takes precedence. Discovery results are stored in `state.json.a2a.discovered_agents[]`.

### Security

| Mode | Description | When to use |
|---|---|---|
| `token` (default) | Auto-generated bearer token, rotated every `token_ttl_hours` (default 24). Stored in `.forge/a2a-credentials.json` (gitignored). Clients refresh on 401. | LAN, trusted networks |
| `mtls` | Mutual TLS with client certificates. Requires `a2a.tls.cert_path`, `a2a.tls.key_path`, `a2a.tls.ca_path`. | Enterprise, zero-trust environments |
| `none` | No authentication. Only allowed when `a2a.http_bind: 127.0.0.1` (localhost-only). PREFLIGHT rejects `auth_mode: none` with non-localhost bind. | Local development only |

### Fallback to Filesystem

If HTTP transport fails at any point, the system falls back to filesystem transport transparently:

- **Python 3 not available:** WARNING logged, filesystem transport used for the entire run.
- **Port conflict:** Tries `http_port` through `http_port + 10`. All fail: WARNING, filesystem fallback.
- **Remote agent unreachable:** 3 retries (5s, 15s, 30s backoff). After exhaustion: agent marked `unreachable`. If a filesystem path exists in `related_projects`, it is used instead.
- **Server crash mid-run:** Orchestrator detects missing PID, restarts. Two restart failures: filesystem fallback.
- **mTLS certificate invalid:** CRITICAL logged. Server not started. Filesystem fallback.

The transport layer logs all fallbacks as WARNING so they are visible in pipeline output without blocking the run.

### WebSocket (Optional Enhancement)

When `a2a.websocket_enabled: true` (default) and HTTP transport is active, the server provides a WebSocket endpoint at `/tasks/{id}/subscribe`. Consumers receive real-time state change notifications instead of polling:

```
Server pushes: { "event": "state_change", "from": "REVIEWING", "to": "SHIPPING" }
```

WebSocket requires the `websockets` Python library. If unavailable, the server starts without WebSocket support and clients fall back to HTTP polling. Disconnected WebSocket clients reconnect with backoff (1s, 2s, 4s, max 30s) and fall back to polling after 3 failed reconnects.

### Server Lifecycle

1. **Start (PREFLIGHT):** Orchestrator reads `a2a.transport` from config. If `http`: start `a2a-server.sh` as background Python process, record PID in `.forge/.a2a-server.pid`, update agent card with HTTP URL.
2. **Run:** Server reads `.forge/state.json` on each request (cached, refreshed every 2s). Memory: 10-30MB. CPU: <1% idle.
3. **Stop (LEARNING/ABORT):** SIGTERM to server PID. 5s grace period for WebSocket drain. PID file removed.

---

## Configuration

### Filesystem Transport (Implicit)

A2A filesystem transport requires no explicit configuration. The protocol activates when:

1. `.forge/agent-card.json` exists in a target repository
2. `fg-103` detects the card during cross-repo setup

There is no `a2a.enabled` flag. Presence of the agent card is the signal.

### HTTP Transport (Explicit)

HTTP transport is configured via the `a2a:` section in `forge-config.md`:

```yaml
a2a:
  transport: filesystem           # filesystem (default) | http
  http_port: 9473                 # Port for A2A HTTP server
  auth_mode: token                # token | mtls | none
```

See `shared/a2a-http-transport.md` for the full configuration reference.

### Opting Out

To prevent A2A discovery for a specific project, do not run `/forge-init` in that project (or delete `.forge/agent-card.json`). The fallback to file-based polling is automatic and silent.

---

## Lifecycle Summary

```
/forge-init
  → Detects git remote, generates .forge/agent-card.json
  → If a2a.transport == "http": includes transport and authentication fields in card

/forge-run (producer repo)
  → PREFLIGHT: if a2a.transport == "http", start A2A HTTP server on configured port
  → state.json updated at each stage transition
  → No agent-card.json changes during run
  → LEARNING/ABORT: stop A2A HTTP server if running

fg-103 (consumer repo)
  → Reads producer's agent-card.json for capabilities (filesystem or HTTP GET)
  → Polls producer's state.json, maps to A2A task states (filesystem read or HTTP GET)
  → If WebSocket available: subscribes for real-time state push notifications
  → Dispatches consumer when producer reaches "completed"

Fallback (no agent card)
  → fg-103 polls state.json directly
  → Uses story_state without A2A mapping
  → Logs INFO about missing agent card

Transport fallback (HTTP failure)
  → Falls back to filesystem if path available
  → Logs WARNING about HTTP failure
  → Run continues without interruption
```
