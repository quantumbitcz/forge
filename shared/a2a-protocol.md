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

## Configuration

A2A is implicit — no explicit configuration is required. The protocol activates when:

1. `.forge/agent-card.json` exists in a target repository
2. `fg-103` detects the card during cross-repo setup

There is no `a2a.enabled` flag. Presence of the agent card is the signal.

### Opting Out

To prevent A2A discovery for a specific project, do not run `/forge-init` in that project (or delete `.forge/agent-card.json`). The fallback to file-based polling is automatic and silent.

---

## Lifecycle Summary

```
/forge-init
  → Detects git remote, generates .forge/agent-card.json

/forge-run (producer repo)
  → state.json updated at each stage transition
  → No agent-card.json changes during run

fg-103 (consumer repo)
  → Reads producer's agent-card.json for capabilities
  → Polls producer's state.json, maps to A2A task states
  → Dispatches consumer when producer reaches "completed"

Fallback (no agent card)
  → fg-103 polls state.json directly
  → Uses story_state without A2A mapping
  → Logs INFO about missing agent card
```
