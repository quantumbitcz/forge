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
2. If RECOVERABLE is true: attempt the SUGGESTED_STRATEGY (up to recovery budget of 5 total applications)
3. If RECOVERABLE is false: report to orchestrator immediately using the error format
4. The orchestrator decides: retry with different approach, skip, or escalate to user

## Usage by Recovery Engine

The recovery engine reads the ERROR_TYPE field to select the appropriate strategy without heuristic classification. This replaces the free-text error parsing that was previously required.

When an error arrives with a pre-classified ERROR_TYPE and SUGGESTED_STRATEGY:
- Use the suggested strategy directly (skip heuristic classification)
- Still respect the recovery budget (max 5 applications per run)

When an error arrives WITHOUT classification (legacy agents or unexpected errors):
- Fall back to the existing heuristic classification in the recovery engine
- Log WARNING: "Unclassified error — using heuristic classification"

## Error Aggregation

If multiple errors occur in the same stage:
- Report all of them (don't stop at the first)
- Group by ERROR_TYPE
- The most severe (non-recoverable) determines the stage outcome
- If a mix of recoverable and non-recoverable errors: attempt recovery for the recoverable ones, escalate for the non-recoverable ones
