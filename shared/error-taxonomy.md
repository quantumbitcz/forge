# Error Taxonomy

Standard error classification for all pipeline agents (22 types). Every error reported to the orchestrator or recovery engine should use this format.

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
| TOOL_FAILURE | Shell command failed or tool crashed (exit code != 0 due to tool malfunction, not code errors) | Yes | tool-diagnosis |
| BUILD_FAILURE | Compilation error (code-level — the build tool ran correctly but found code errors). If the build tool itself crashed, classify as TOOL_FAILURE instead. | Yes | orchestrator fix loop (NOT recovery engine) |
| TEST_FAILURE | Test assertion failed (code-level — the test runner ran correctly but assertions failed). If the test runner crashed, classify as TOOL_FAILURE instead. | Yes | orchestrator fix loop (NOT recovery engine) |
| LINT_FAILURE | Linter reported violations (code-level — the linter ran correctly but found issues). If the linter crashed, classify as TOOL_FAILURE instead. | Yes | orchestrator fix loop (NOT recovery engine) |
| AGENT_TIMEOUT | Dispatched agent didn't return in time | Yes | agent-reset |
| AGENT_ERROR | Dispatched agent returned an error. If agent output contains a classifiable sub-error (TOOL_FAILURE, BUILD_FAILURE, etc.), reclassify as that sub-error type. Otherwise, treat as recoverable and route to agent-reset. | Maybe | agent-reset |
| CONTEXT_OVERFLOW | Agent context window approaching or exceeding token limit. Detected when agent output is truncated or agent reports token pressure. | Yes | resource-cleanup (reduce prompt scope, split task, compact history) |
| STATE_CORRUPTION | state.json or checkpoint unreadable | Yes | state-reconstruction |
| DEPENDENCY_MISSING | Required tool/binary not found | No | dependency-health |
| CONFIG_INVALID | forge.local.md malformed or missing required fields | No | none (user must fix) |
| GIT_CONFLICT | Merge conflict or dirty working tree | No | resource-cleanup |
| DISK_FULL | Insufficient disk space | No | resource-cleanup |
| NETWORK_UNAVAILABLE | External service unreachable (GitHub, context7, Linear) | Maybe | transient-retry |
| PERMISSION_DENIED | File or directory not writable, or binary not executable. If a binary/script is not executable (exit code 126): recoverable via tool-diagnosis (`chmod +x`). If a file/directory write permission failure: non-recoverable (user must fix). | Maybe | tool-diagnosis (binary/script) or none (filesystem) |
| MCP_UNAVAILABLE | Optional MCP server not responding | Yes | graceful degradation (not a recovery strategy — agent handles inline) |
| PATTERN_MISSING | Referenced pattern file doesn't exist | No | none (planner must fix) |
| LOCK_FILE_CONFLICT | Lock file (yarn.lock, Cargo.lock) divergence or corruption | Yes | resource-cleanup |
| FLAKY_TEST | Test passes on re-run after initial failure | Yes | transient-retry |
| VERSION_MISMATCH | Required tool/runtime version not met (e.g., Java 8 found, Java 11+ required) | No | none (user must fix) |
| DEPRECATION_WARNING | Use of EOL, deprecated, or unsafe dependency version detected by `fg-140-deprecation-refresh` | N/A | none (inline handling: log WARNING in stage notes, do not block pipeline, do not invoke recovery engine). Retrospective tracks accumulation. |
| WORKTREE_FAILURE | Worktree creation, branch collision, or stale worktree cleanup failed | Yes | resource-cleanup |
| BUDGET_EXHAUSTED | Recovery budget `total_weight >= max_weight` (default: 5.5) — pipeline cannot recover from further failures. Raised by the recovery engine itself, not by pipeline agents. | No | none (recovery engine escalates directly) |
| INJECTION_BLOCKED | A BLOCK-tier prompt-injection pattern matched external input at the filter layer (`hooks/_py/mcp_response_filter.py`). Content is quarantined and never reaches an agent. Stage halts. Not recoverable by retry — requires fixing the source (credential leak, hostile ticket). See `shared/untrusted-envelope.md`. Added in 3.1.0. | No | none (emit `SEC-INJECTION-BLOCKED` CRITICAL, halt stage, surface to user) |

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
- Still respect the weighted recovery budget (max 5.5 total weight per run — see `shared/recovery/recovery-engine.md` for strategy weights)

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
4. `VERSION_MISMATCH` — required tool/runtime version not met
5. `STATE_CORRUPTION` — pipeline integrity
6. `DEPENDENCY_MISSING` — required tool absent
7. `BUDGET_EXHAUSTED` — recovery system limit reached (terminal, no further recovery possible)
8. `GIT_CONFLICT` / `LOCK_FILE_CONFLICT` / `WORKTREE_FAILURE` — version control / lock file / worktree integrity
9. `AGENT_TIMEOUT` / `AGENT_ERROR` / `CONTEXT_OVERFLOW` — agent-level
10. `TOOL_FAILURE` — tool-level
11. `BUILD_FAILURE` / `TEST_FAILURE` / `LINT_FAILURE` — code-level (orchestrator fix loops, not recovery engine)
12. `FLAKY_TEST` — non-deterministic test failure (transient)
13. `NETWORK_UNAVAILABLE` — possibly transient
14. `MCP_UNAVAILABLE` — optional, graceful degradation
15. `DEPRECATION_WARNING` — informational, non-blocking (logged for retrospective)
16. `PATTERN_MISSING` — planner error, non-blocking

The highest-severity non-recoverable error determines stage outcome. Recoverable errors are attempted via recovery engine in order.

## MCP_UNAVAILABLE Handling

MCP failures are NOT recovery engine domain. When an agent encounters MCP_UNAVAILABLE, handle gracefully inline: skip the MCP-dependent operation, log INFO in stage notes ("MCP {name} unavailable, skipping {operation}"), continue with degraded capability. Do NOT call the recovery engine for MCP_UNAVAILABLE.

## Network Permanence Detection

After 3 consecutive transient-retry failures for the same endpoint within 60 seconds, reclassify `NETWORK_UNAVAILABLE` as non-recoverable for that endpoint. Log: "Network to {endpoint} appears permanently unavailable after 3 retries." Continue pipeline with degraded mode for that service. Do not consume further recovery budget for this endpoint.

## Scoring Side-Effects

Some error types produce scoring findings in addition to (or instead of) triggering the recovery engine:

| Error Type | Scoring Effect | Category | Severity | Condition |
|---|---|---|---|---|
| AGENT_TIMEOUT | REVIEW-GAP finding when review agent times out | `REVIEW-GAP` | INFO (WARNING for critical-domain agents) | REVIEW stage only |
| AGENT_ERROR | REVIEW-GAP finding when review agent fails | `REVIEW-GAP` | INFO (WARNING for critical-domain agents) | REVIEW stage only |
| MCP_UNAVAILABLE | No scoring deduction — inline degradation only | — | — | All stages |
| DEPRECATION_WARNING | May produce `DEP-*` findings if severe | `DEP-*` | WARNING | PREFLIGHT |
| BUDGET_EXHAUSTED | No direct scoring — triggers pipeline abort | — | — | — |

Cross-reference: see `shared/scoring.md` section "Partial Failure Handling" for REVIEW-GAP rules.
