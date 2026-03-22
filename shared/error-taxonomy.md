# Error Taxonomy

Standard error classification for all pipeline agents. Every error reported to the orchestrator or recovery engine should use this format.

## Error Format

When reporting errors, agents should structure them as:

- **ERROR_TYPE:** one of the types from the table below
- **ERROR_DETAIL:** specific message (command output, file path, etc.)
- **RECOVERABLE:** true or false
- **SUGGESTED_STRATEGY:** recovery strategy name from recovery-engine.md, or "none"
- **CONTEXT:** file:line or command that failed

## Error Types

| Type | Meaning | Recoverable? | Default Strategy |
|---|---|---|---|
| TOOL_FAILURE | Shell command failed or tool crashed (build, test, lint) | Yes | tool-diagnosis |
| BUILD_FAILURE | Compilation error | Yes | tool-diagnosis |
| TEST_FAILURE | Test assertion failed | Yes | tool-diagnosis |
| LINT_FAILURE | Linter reported errors | Yes | tool-diagnosis |
| AGENT_TIMEOUT | Dispatched agent didn't return in time | Yes | agent-reset |
| AGENT_ERROR | Dispatched agent returned an error | Maybe | agent-reset |
| STATE_CORRUPTION | state.json or checkpoint unreadable | Yes | state-reconstruction |
| DEPENDENCY_MISSING | Required tool/binary not found | No | dependency-health |
| CONFIG_INVALID | dev-pipeline.local.md malformed or missing required fields | No | none (user must fix) |
| GIT_CONFLICT | Merge conflict or dirty working tree | No | resource-cleanup |
| DISK_FULL | Insufficient disk space | No | resource-cleanup |
| NETWORK_UNAVAILABLE | External service unreachable (GitHub, context7, Linear) | Maybe | transient-retry |
| PERMISSION_DENIED | File or directory not writable | No | none (user must fix) |
| MCP_UNAVAILABLE | Optional MCP server not responding | Yes | graceful degradation (not a recovery strategy — agent handles inline) |
| PATTERN_MISSING | Referenced pattern file doesn't exist | No | none (planner must fix) |

## Usage by Agents

When an agent encounters an error:

1. Classify it using the table above
2. If RECOVERABLE is true: attempt the SUGGESTED_STRATEGY (within the weighted recovery budget — see `shared/recovery/recovery-engine.md`)
3. If RECOVERABLE is false: report to orchestrator immediately using the error format
4. The orchestrator decides: retry with different approach, skip, or escalate to user

## Usage by Recovery Engine

The recovery engine reads the ERROR_TYPE field to select the appropriate strategy without heuristic classification. This replaces the free-text error parsing that was previously required.

When an error arrives with a pre-classified ERROR_TYPE and SUGGESTED_STRATEGY:
- Use the suggested strategy directly (skip heuristic classification)
- Still respect the weighted recovery budget (max 5.0 total weight per run — see `shared/recovery/recovery-engine.md` for strategy weights)

When an error arrives WITHOUT classification (legacy agents or unexpected errors):
- Fall back to the existing heuristic classification in the recovery engine
- Log WARNING: "Unclassified error — using heuristic classification"

## Error Aggregation

If multiple errors occur in the same stage:
- Report all of them (don't stop at the first)
- Group by ERROR_TYPE
- The most severe (non-recoverable) determines the stage outcome
- If a mix of recoverable and non-recoverable errors: attempt recovery for the recoverable ones, escalate for the non-recoverable ones

## Error Severity Ordering

When multiple errors co-occur in a stage, determine outcome by this severity order (highest first):

1. `CONFIG_INVALID` — pipeline cannot proceed
2. `PERMISSION_DENIED` — system-level block
3. `DISK_FULL` — resource hard limit
4. `STATE_CORRUPTION` — pipeline integrity
5. `DEPENDENCY_MISSING` — required tool absent
6. `GIT_CONFLICT` — version control integrity
7. `AGENT_TIMEOUT` / `AGENT_ERROR` — agent-level
8. `TOOL_FAILURE` — tool-level
9. `BUILD_FAILURE` / `TEST_FAILURE` / `LINT_FAILURE` — code-level (retry loops)
10. `NETWORK_UNAVAILABLE` — possibly transient
11. `MCP_UNAVAILABLE` — optional, graceful degradation
12. `PATTERN_MISSING` — planner error, non-blocking

The highest-severity non-recoverable error determines stage outcome. Recoverable errors are attempted via recovery engine in order.

## MCP_UNAVAILABLE Handling

MCP failures are NOT recovery engine domain. When an agent encounters MCP_UNAVAILABLE, handle gracefully inline: skip the MCP-dependent operation, log INFO in stage notes ("MCP {name} unavailable, skipping {operation}"), continue with degraded capability. Do NOT call the recovery engine for MCP_UNAVAILABLE.

## Network Permanence Detection

After 3 consecutive transient-retry failures for the same endpoint within 60 seconds, reclassify `NETWORK_UNAVAILABLE` as non-recoverable for that endpoint. Log: "Network to {endpoint} appears permanently unavailable after 3 retries." Continue pipeline with degraded mode for that service. Do not consume further recovery budget for this endpoint.
