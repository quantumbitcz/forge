# Security Posture

This document defines the OWASP Agentic AI Security compliance posture for the forge pipeline. It covers input sanitization, tool call budgets, anomaly detection, convention file signatures, and per-agent permission tiers.

## OWASP Top 10 for Agentic AI

The following table maps each OWASP Agentic Security Initiative (ASI) risk to the forge pipeline's current mitigation and planned enhancements for v1.19.

| ID | Risk Name | Current Mitigation | v1.19 Enhancement |
|---|---|---|---|
| ASI01 | Excessive Agency / Goal Hijacking | Pipeline stages are deterministic (state-transitions.md); orchestrator never writes code | Input sanitization strips injection patterns from requirement text before pipeline entry |
| ASI02 | Tool Misuse | Tools declared per-agent in frontmatter; orchestrator dispatches only listed tools | Tool call audit log with per-agent budget enforcement and anomaly detection |
| ASI03 | Privilege Escalation / Identity | Agent tiers (1-4) with distinct UI capabilities; Tier 4 agents have no user interaction | Document explicit permission model per tier; enforce read-only for Tier 4 |
| ASI04 | Supply Chain Compromise | Convention files loaded from plugin directory only; no remote fetch at runtime. MCP governance allowlist (`shared/mcp-governance.md`) blocks unapproved MCP servers at PREFLIGHT. | SHA256 signature verification of convention files at PREFLIGHT. MCP server allowlist with modes: allowlist (default), audit, disabled. Supply chain verification for new dependencies (typosquatting, provenance, popularity). |
| ASI05 | Unsafe Code Execution | Code runs in worktree isolation; user tree never modified | Document sandbox options (gVisor, Firecracker) for high-security environments |
| ASI06 | Memory Poisoning / Data Leakage | State files in `.forge/` (gitignored); no secrets in state.json. Cache integrity verification (`shared/cache-integrity.md`) detects tampered explore-cache, plan-cache, knowledge, and code-graph files via SHA256 checksums. | Data classification contract (shared/data-classification.md) for pipeline artifacts. SHA256 checksums on all cached artifacts with tamper detection and automatic invalidation. |
| ASI07 | Insecure Inter-Agent Communication | All inter-agent communication via orchestrator stage notes; no direct agent-to-agent calls | A2A protocol contract (shared/a2a-protocol.md) with message signing and schema validation |
| ASI08 | Cascading Hallucination Failures | Recovery engine with circuit breakers (7 strategies, budget ceiling 5.5); 3 consecutive transients in 60s = non-recoverable | Fan-out caps per dispatch; anomaly detection on call frequency and cost |
| ASI09 | Trust Boundary Exploitation | Explicit trust boundaries: plugin code vs. project code vs. runtime state | Confidence scores on inter-agent findings (v1.18 scoring.md); trust attestation chain |
| ASI10 | Rogue Agent Behavior | Agent tools restricted via frontmatter; orchestrator is sole dispatcher | Per-agent tool call budget with hard ceiling; alert on budget breach |

## Input Sanitization

All requirement text entering the pipeline (via `/forge run`, `/forge fix`, `/forge run`, or sprint input) is sanitized before processing. Sanitization runs at the earliest pipeline entry point, before intent classification.

### Rules

1. **Strip HTML tags:** Remove all `<tag>` and `</tag>` patterns. Requirement text is plain text or markdown only.
2. **Strip script tags:** Remove `<script>...</script>` blocks and `javascript:` URI schemes.
3. **Strip markdown injection:** Remove patterns that could alter agent system prompts:
   - Triple-backtick blocks containing `system:` or `role:` directives
   - Lines starting with `## System` or `## Instructions` (prompt injection attempts)
   - Embedded base64-encoded content exceeding 500 characters
4. **Preserve legitimate content:** Markdown formatting (headers, lists, code blocks for examples) is preserved. Only patterns matching injection signatures are removed.
5. **Log sanitization:** When content is stripped, log an INFO entry: `"Input sanitized: {N} patterns removed"`. The original text is NOT stored.

### Configuration

```yaml
security:
  input_sanitization: true
```

When `input_sanitization` is `false`, sanitization is skipped entirely. Default: `true`. Disabling is NOT recommended and produces a WARNING at PREFLIGHT.

## Tool Call Budget

Each agent has a maximum number of tool calls per pipeline run. The orchestrator enforces the budget before dispatching each tool call. When an agent exceeds its budget, the orchestrator terminates the agent and logs a WARNING.

### Defaults

| Parameter | Value |
|---|---|
| Default budget (all agents) | 50 |
| `fg-300-implementer` | 200 |
| `fg-500-test-gate` | 150 |

### Enforcement

1. The orchestrator maintains a `tool_calls` counter per agent per run.
2. Before each tool call dispatch, check `tool_calls[agent] < budget[agent]`.
3. If the budget is exceeded: terminate the agent, log `WARNING: Agent {name} exceeded tool call budget ({budget}). Terminating.`, and proceed with available results.
4. Budget counts reset at the start of each pipeline run.

### Configuration

```yaml
security:
  tool_call_budget:
    default: 50
    overrides:
      fg-300-implementer: 200
      fg-500-test-gate: 150
```

Override values must be >= 1 and <= 1000. Values outside this range are clamped with a WARNING.

## Anomaly Detection

The pipeline monitors tool call frequency and session cost to detect runaway agents or unexpected behavior patterns.

### Thresholds

| Metric | Threshold | Action |
|---|---|---|
| Tool calls per minute (any agent) | 30 | WARNING log + alert. If sustained for 2 minutes, terminate agent. |
| Session cost (USD, cumulative) | $10 | WARNING log + alert. Pipeline pauses for user confirmation before continuing. |

### Detection Rules

1. **Call frequency:** A sliding 60-second window tracks tool calls per agent. Exceeding `max_calls_per_minute` triggers a WARNING. If the rate remains above threshold for a second consecutive window, the agent is terminated.
2. **Cost tracking:** Cumulative session cost is estimated from tool call counts and model token usage. Exceeding `max_session_cost_usd` pauses the pipeline with an escalation to the user.
3. **Pattern anomalies:** Repeated identical tool calls (same tool, same arguments, 5+ times in 60 seconds) trigger an INFO alert. This may indicate a stuck agent.

### Configuration

```yaml
security:
  anomaly_detection:
    max_calls_per_minute: 30
    max_session_cost_usd: 10
```

Constraints enforced at PREFLIGHT:
- `max_calls_per_minute` must be >= 5 and <= 200 (default: 30)
- `max_session_cost_usd` must be >= 1 and <= 100 (default: 10)

## Convention File Signatures

Convention files (`.md`, `rules-override.json`, `known-deprecations.json`) loaded during PREFLIGHT are verified against SHA256 signatures to detect tampering or unexpected modification.

### Process

1. At PREFLIGHT, compute SHA256 hashes of all loaded convention files.
2. Compare against stored hashes from the previous run (in `state.json` field `conventions_hash` and `conventions_section_hashes`).
3. **First run:** No comparison — store baseline hashes.
4. **Subsequent runs:** If a hash mismatches, log `WARNING: Convention file {path} has changed since last run (SHA256 mismatch). Reviewing changes.` The pipeline continues but agents are notified of the drift via stage notes.
5. **Signature storage:** Hashes are stored in `state.json` per the existing `conventions_hash` and `conventions_section_hashes` fields.

### Configuration

```yaml
security:
  convention_signatures: true
```

When `convention_signatures` is `false`, signature verification is skipped. Default: `true`.

## Per-Agent Permission Model

Agent permissions are tiered according to the existing UI tier classification (see `shared/agent-ui.md`). Each tier defines what the agent is allowed to do.

| Tier | Agents | Permissions |
|---|---|---|
| Tier 1 | Shaper, scope decomposer, planner, migration planner, bootstrapper, sprint orchestrator | Tasks + AskUser + EnterPlanMode. Can prompt user for clarification. Can create/modify plans. Cannot write code directly. |
| Tier 2 | Orchestrator, bug investigator, quality gate, test gate, PR builder, cross-repo coordinator, post-run | Tasks + AskUser. Can prompt user for decisions. Can dispatch sub-agents. Cannot write code directly. |
| Tier 3 | Implementer, frontend polisher, retrospective, docs discoverer, deprecation refresh, preview validator, pre-ship verifier, infra verifier, scaffolder, docs generator, contract validator, test bootstrapper, build-verifier | Tasks only. Can write code (within worktree). Can run build/test/lint commands. No user interaction. |
| Tier 4 | All reviewers (fg-410 through fg-419), validator, worktree manager, conflict resolver | No UI. Read-only analysis. Can emit findings. Cannot write code, dispatch agents, or interact with user. |

### Enforcement

- Tool declarations in agent frontmatter are the source of truth. An agent cannot invoke a tool not listed in its `tools:` field.
- Tier 4 agents must not include `Write`, `Edit`, `Agent`, or `AskUserQuestion` in their tool list. Validated by `ui-frontmatter-consistency.bats`.
- Tier 3 agents must not include `AskUserQuestion` or `EnterPlanMode`.
- Violations detected at PREFLIGHT produce a CRITICAL finding and block pipeline start.

## Sandbox Documentation

For high-security environments where code execution must be fully isolated, the following sandbox technologies are supported:

### gVisor

gVisor provides an application kernel that intercepts system calls, adding a layer of isolation between the application and the host kernel. Configure by running the forge pipeline inside a gVisor-sandboxed container (`runsc` runtime).

### Firecracker

Firecracker micro-VMs provide lightweight virtualization with minimal overhead. Each pipeline run can execute inside a dedicated Firecracker VM, ensuring full kernel-level isolation.

### Usage

Sandbox configuration is environment-specific and not enforced by the plugin. The plugin documents sandbox options for security-conscious deployments. When a sandbox is detected (via environment variable `FORGE_SANDBOX=gvisor|firecracker`), the pipeline logs an INFO entry at PREFLIGHT: `"Running in sandboxed environment: {sandbox_type}"`.

## Full Configuration Reference

```yaml
security:
  input_sanitization: true
  tool_call_budget:
    default: 50
    overrides:
      fg-300-implementer: 200
      fg-500-test-gate: 150
  anomaly_detection:
    max_calls_per_minute: 30
    max_session_cost_usd: 10
  convention_signatures: true
```

All security settings are optional. When omitted, plugin defaults (documented above) apply. Settings are read from `forge-config.md` or `forge.local.md` with the standard resolution order (`forge-config.md` > `forge.local.md` > plugin defaults).

## MCP Governance (ASI04)

Allowlist-based authorization for MCP servers detected at PREFLIGHT. Prevents untrusted external tools from being used by pipeline agents. Full specification in `shared/mcp-governance.md`.

### Summary

- **Default allowlist:** context7, playwright, neo4j, slack, linear, figma, excalidraw (the 7 servers from `shared/mcp-detection.md`)
- **Modes:** `allowlist` (block unapproved, default), `audit` (allow all, log everything), `disabled` (no checks)
- **On unapproved server:** CRITICAL finding `SEC-MCP-UNAUTHORIZED`, server blocked for the run
- **Audit trail:** All governance decisions logged to `.forge/security-audit.jsonl` (see `shared/security-audit-trail.md`)
- **Configuration:** `security.mcp_governance` in `forge-config.md`

## Cache Integrity Verification (ASI06)

SHA256 checksum verification for cached pipeline artifacts. Detects tampered or corrupted cache entries before the pipeline consumes them. Full specification in `shared/cache-integrity.md`.

### Summary

- **Protected files:** `explore-cache.json`, `plan-cache/**`, `knowledge/**`, `code-graph.db`
- **Checksums computed at write time**, verified at read time
- **Tampered entries:** WARNING finding `SEC-CACHE-TAMPER`, cache invalidated, automatic re-exploration or re-planning
- **Integrity store:** `.forge/integrity.json`
- **Configuration:** `security.cache_integrity` in `forge-config.md`

## Enhanced Secret Detection

Extended L1 secret detection with entropy analysis and cloud credential patterns. Supplements existing SEC-SECRET and SEC-PII regex patterns from `shared/data-classification.md`.

### High-Entropy String Detection

Shannon entropy calculation via `shared/checks/l1-security/entropy-check.py`. Post-filter on L1 regex matches:
- **Threshold:** entropy > 4.5 AND length >= 16 AND not in test/fixture context
- **Exclusions:** UUIDs, SHA hashes, hex color codes, known test patterns
- **Finding category:** `SEC-ENTROPY` (WARNING)

### Cloud Credential Patterns

18 provider-specific patterns in `shared/checks/l1-security/cloud-credentials.json`:
- AWS (access keys, secret keys)
- GCP (service account keys, API keys)
- Azure (connection strings, SAS tokens)
- GitHub (PATs, fine-grained tokens)
- Slack (bot tokens, webhooks)
- Stripe (live keys, test keys)
- JWT tokens, Bearer tokens
- Private key headers (RSA, EC, Ed25519, OpenSSH, encrypted)

### AST-Context-Aware Severity

When F01's tree-sitter code graph is available, L1 matches are classified by code context. Test code reduces severity from CRITICAL to WARNING; test fixtures reduce to INFO. Production and configuration code retain original severity. See the F10 spec for the full context classification table.

## Security Audit Trail

All security-relevant events are logged to `.forge/security-audit.jsonl` in JSON Lines format. Full format specification in `shared/security-audit-trail.md`.

### Event Types

| Event | Trigger |
|---|---|
| `MCP_CONNECTION` | MCP governance evaluates a detected server at PREFLIGHT |
| `MCP_TOOL_INVOCATION` | MCP tool call (when audit enabled or MEDIUM/HIGH risk server) |
| `SECRET_DETECTED` | L1 check engine or entropy detection finds a credential |
| `CACHE_INTEGRITY_FAIL` | SHA256 verification of a cached artifact fails |
| `DEPENDENCY_NEW` | Supply chain verification detects a new dependency |

### Configuration

```yaml
security:
  audit_trail:
    enabled: true
    max_file_size_mb: 10
    retention_runs: 50
```
