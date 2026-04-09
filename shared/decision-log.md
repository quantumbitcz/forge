# Decision Log

Every branching decision in the forge pipeline is logged to a structured append-only file for post-run analysis, debugging slow convergence, and tuning decision logic.

## File Location

`.forge/decisions.jsonl` — append-only, one JSON object per line (JSON Lines format). Created on first write. Gitignored with the rest of `.forge/`.

## Schema

Each line is a self-contained JSON object:

```json
{
  "ts": "2024-01-15T10:32:04.123Z",
  "agent": "fg-100-orchestrator",
  "decision": "state_transition",
  "input": { "current_state": "IMPLEMENTING", "event": "verify_pass" },
  "choice": "VERIFYING",
  "alternatives": ["IMPLEMENTING (retry)"],
  "reason": "All tests pass, advancing to VERIFY stage"
}
```

## Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `ts` | string (ISO 8601) | yes | Timestamp of the decision |
| `agent` | string | yes | Agent that made the decision (e.g. `fg-100-orchestrator`) |
| `decision` | string (enum) | yes | Decision type — see below |
| `input` | object | yes | Context/inputs that informed the decision |
| `choice` | string | yes | The outcome selected |
| `alternatives` | array of strings | yes | Other options that were considered (may be empty `[]`) |
| `reason` | string | yes | Brief rationale for the choice |
| `confidence` | string (enum) | no | Decision confidence: `HIGH` (>90% certain, default if omitted), `MEDIUM` (70-90%), `LOW` (<70%). Agents should set `LOW` or `MEDIUM` when trade-offs are unclear or multiple alternatives are equally viable. Used by the retrospective to track decision quality. |
| `agreement` | object | no | Reviewer agreement metadata for quality gate conflict resolutions. Structure: `{ "agents": ["fg-410", "fg-411"], "agreed": true/false, "resolved_by": "priority" }`. `agents`: list of agents involved. `agreed`: whether agents reached the same conclusion. `resolved_by`: resolution method (`"priority"`, `"severity"`, `"user"`). Only present on `reviewer_conflict` decision types. |

## Decision Types

| Type | Emitting Agent(s) | Description |
|------|-------------------|-------------|
| `state_transition` | fg-100-orchestrator | Pipeline stage transition (e.g. IMPLEMENTING -> VERIFYING) |
| `convergence_phase_transition` | fg-100-orchestrator, convergence engine | Phase change within convergence (correctness -> perfection -> safety_gate) |
| `convergence_evaluation` | fg-100-orchestrator, convergence engine | IMPROVING / PLATEAUED / REGRESSING assessment after a cycle |
| `recovery_attempt` | fg-100-orchestrator | Recovery strategy selection from recovery engine |
| `circuit_breaker_state_change` | fg-100-orchestrator | Circuit breaker state change (CLOSED -> OPEN, OPEN -> HALF_OPEN, etc.) |
| `escalation` | fg-100-orchestrator | Decision to escalate to user or abort |
| `mode_classification` | fg-100-orchestrator | Pipeline mode selection (standard, bugfix, migration, bootstrap) |
| `domain_detection` | fg-100-orchestrator | Domain/stack detection results and framework routing |
| `reviewer_conflict` | fg-400-quality-gate | Conflicting findings between reviewers and resolution |
| `evidence_verdict` | fg-590-pre-ship-verifier | Ship/no-ship verdict from evidence collection |

## Emission Protocol

1. Construct the JSON object with all required fields.
2. Append as a single line to `.forge/decisions.jsonl`.
3. Continue execution immediately.

**Fire-and-forget** — decision logging MUST NOT block the pipeline. If the file write fails (permissions, disk full), log a WARNING to stage notes and continue. Never retry, never escalate.

## Consumption

- **`fg-700-retrospective`**: Reads the decision log to identify slow convergence patterns, suboptimal routing, and recovery inefficiencies.
- **`/forge-history`**: Surfaces decision log entries for human review of past runs.
- **Debugging**: When a run takes unexpectedly many iterations, the decision log shows every branch point and why.

## Size Management

When `.forge/decisions.jsonl` exceeds 1000 lines, archive the file:

1. Compress to `.forge/decisions-{ISO-date}.jsonl.gz`.
2. Truncate `.forge/decisions.jsonl` to empty.
3. Continue appending to the fresh file.

Archival happens at run start (PREFLIGHT) — never mid-pipeline.
