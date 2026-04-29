# Security Audit Trail

Documents the format and semantics of `.forge/security-audit.jsonl`, the append-only log of security-relevant events during pipeline execution.

## File Location

`.forge/security-audit.jsonl` -- one JSON object per line (JSON Lines format). Created on first security event. Survives `/forge-admin recover reset`. Rotated when file size exceeds `security.audit_trail.max_file_size_mb` (default 10 MB).

## Event Types

### MCP_CONNECTION

Logged at PREFLIGHT when MCP governance evaluates a detected MCP server.

```json
{
  "timestamp": "2026-04-13T10:00:00Z",
  "event": "MCP_CONNECTION",
  "mcp_name": "linear",
  "prefix": "mcp__claude_ai_Linear__",
  "result": "allowed",
  "risk_level": "MEDIUM",
  "governance_mode": "allowlist"
}
```

| Field | Type | Description |
|---|---|---|
| `mcp_name` | string | Human-readable MCP server name |
| `prefix` | string | Tool name prefix used for detection |
| `result` | string | `allowed`, `blocked`, or `audit_only` |
| `risk_level` | string | `LOW`, `MEDIUM`, or `HIGH` |
| `governance_mode` | string | Active governance mode at time of check |

When a server is blocked, additional fields are included:

```json
{
  "timestamp": "2026-04-13T10:00:01Z",
  "event": "MCP_CONNECTION",
  "mcp_name": "unknown-server",
  "prefix": "mcp__custom_unknown__",
  "result": "blocked",
  "reason": "not in mcp_governance.allowlist",
  "governance_mode": "allowlist"
}
```

### MCP_TOOL_INVOCATION

Logged when `audit_all_calls: true` or the MCP server has risk level MEDIUM or HIGH. Records every tool call to an external MCP server.

```json
{
  "timestamp": "2026-04-13T10:15:00Z",
  "event": "MCP_TOOL_INVOCATION",
  "mcp_name": "linear",
  "tool_name": "mcp__claude_ai_Linear__save_issue",
  "agent": "fg-200-planner",
  "stage": "PLANNING",
  "risk_level": "MEDIUM"
}
```

| Field | Type | Description |
|---|---|---|
| `tool_name` | string | Fully qualified tool name invoked |
| `agent` | string | Agent that initiated the call |
| `stage` | string | Pipeline stage at time of invocation |

### SECRET_DETECTED

Logged when the L1 check engine or enhanced secret detection finds a credential or high-entropy string.

```json
{
  "timestamp": "2026-04-13T10:15:00Z",
  "event": "SECRET_DETECTED",
  "category": "SEC-SECRET-AWS",
  "file": "src/config/aws.ts",
  "line": 15,
  "context": "production",
  "severity": "CRITICAL",
  "detection_method": "l1_regex"
}
```

| Field | Type | Description |
|---|---|---|
| `category` | string | Finding category code (e.g., `SEC-SECRET-AWS`, `SEC-ENTROPY`) |
| `file` | string | Relative file path where the secret was detected |
| `line` | integer | Line number of the detection |
| `context` | string | Code context: `production`, `test`, `fixture`, `config`, `docs`, `generated` |
| `severity` | string | Context-adjusted severity: `CRITICAL`, `WARNING`, or `INFO` |
| `detection_method` | string | `l1_regex`, `entropy`, or `ast_context` |

### CACHE_INTEGRITY_FAIL

Logged when SHA256 verification of a cached artifact fails.

```json
{
  "timestamp": "2026-04-13T10:00:03Z",
  "event": "CACHE_INTEGRITY_FAIL",
  "file": "plan-cache/index.json",
  "expected_sha256": "f6e5d4c3b2a1...",
  "actual_sha256": "a1b2c3d4e5f6...",
  "action": "invalidated",
  "tamper_response": "Rebuild index from plan files"
}
```

| Field | Type | Description |
|---|---|---|
| `file` | string | Path relative to `.forge/` of the tampered file |
| `expected_sha256` | string | Checksum stored in `integrity.json` |
| `actual_sha256` | string | Checksum computed from current file on disk |
| `action` | string | `invalidated` or `rebuilt` |
| `tamper_response` | string | Human-readable description of the recovery action taken |

### DEPENDENCY_NEW

Logged when supply chain verification detects a new dependency added during IMPLEMENT.

```json
{
  "timestamp": "2026-04-13T10:20:00Z",
  "event": "DEPENDENCY_NEW",
  "package": "lodash-utils",
  "manifest": "package.json",
  "line": 15,
  "checks": {
    "typosquat": { "flagged": false },
    "provenance": { "verified": true, "registry": "npm" },
    "popularity": { "weekly_downloads": 5200, "flagged": false }
  }
}
```

When typosquatting is detected:

```json
{
  "timestamp": "2026-04-13T10:20:01Z",
  "event": "DEPENDENCY_NEW",
  "package": "lodassh",
  "manifest": "package.json",
  "line": 15,
  "checks": {
    "typosquat": { "flagged": true, "similar_to": "lodash", "edit_distance": 1 },
    "provenance": { "verified": false, "reason": "not found in registry" },
    "popularity": { "weekly_downloads": 0, "flagged": true }
  }
}
```

| Field | Type | Description |
|---|---|---|
| `package` | string | Package/dependency name |
| `manifest` | string | Dependency manifest file where the package was added |
| `line` | integer | Line number in the manifest |
| `checks.typosquat.flagged` | boolean | Whether typosquatting was detected |
| `checks.typosquat.similar_to` | string | Popular package name that this resembles (if flagged) |
| `checks.provenance.verified` | boolean | Whether the package was found in its registry |
| `checks.popularity.weekly_downloads` | integer | Download count from the registry |

## File Rotation

When `.forge/security-audit.jsonl` exceeds `security.audit_trail.max_file_size_mb`:
1. Rename current file to `.forge/security-audit.{ISO-timestamp}.jsonl`
2. Start a new `.forge/security-audit.jsonl`
3. Retain up to `security.audit_trail.retention_runs` rotated files (oldest deleted first)

## Configuration

```yaml
security:
  audit_trail:
    enabled: true
    max_file_size_mb: 10
    retention_runs: 50
```

| Parameter | Type | Default | Range | Description |
|---|---|---|---|---|
| `enabled` | boolean | `true` | -- | Enable security audit logging |
| `max_file_size_mb` | integer | `10` | 1-100 | Max audit log file size before rotation |
| `retention_runs` | integer | `50` | 10-200 | Number of rotated files to retain |
