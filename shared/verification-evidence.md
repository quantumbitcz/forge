# Verification Evidence Schema

This document defines the evidence artifact that `fg-590-pre-ship-verifier` produces and `fg-600-pr-builder` validates before creating a PR. The evidence file is the single source of truth for shipping readiness.

## File Location

`.forge/evidence.json` — created fresh by `fg-590-pre-ship-verifier` on every invocation. Never cached, never carried over between runs.

## Schema

```json
{
  "evidence": {
    "generation_started_at": "2026-04-05T14:28:00Z",
    "timestamp": "2026-04-05T14:32:00Z",
    "build": {
      "command": "npm run build",
      "exit_code": 0,
      "duration_ms": 4200,
      "output_tail": "Build completed successfully."
    },
    "tests": {
      "command": "npm test",
      "exit_code": 0,
      "total": 142,
      "passed": 142,
      "failed": 0,
      "skipped": 0,
      "duration_ms": 18500
    },
    "lint": {
      "command": "npm run lint",
      "exit_code": 0
    },
    "review": {
      "dispatched": true,
      "critical_issues": 0,
      "important_issues": 0,
      "minor_issues": 2
    },
    "score": {
      "current": 100,
      "target": 100
    },
    "verdict": "SHIP",
    "block_reasons": []
  }
}
```

## Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `timestamp` | string (ISO 8601) | Yes | When verification ran. Used for staleness check. |
| `generation_started_at` | string (ISO 8601) | Yes | When fg-590 started. Used with `timestamp` to compute generation duration for staleness window adjustment. |
| `build.command` | string | Yes | Actual build command executed (from `forge.local.md` `commands.build`) |
| `build.exit_code` | integer | Yes | Must be 0 for SHIP verdict |
| `build.duration_ms` | integer | Yes | Wall-clock build time |
| `build.output_tail` | string | No | Last 5 lines of build output (for diagnostics on failure) |
| `tests.command` | string | Yes | Actual test command executed |
| `tests.exit_code` | integer | Yes | Must be 0 for SHIP verdict |
| `tests.total` | integer | Yes | Total test count |
| `tests.passed` | integer | Yes | Passing test count |
| `tests.failed` | integer | Yes | Must be 0 for SHIP verdict |
| `tests.skipped` | integer | Yes | Skipped test count (informational) |
| `tests.duration_ms` | integer | Yes | Wall-clock test time |
| `lint.command` | string | Yes | Actual lint command executed |
| `lint.exit_code` | integer | Yes | Must be 0 for SHIP verdict |
| `review.dispatched` | boolean | Yes | Whether final code review ran |
| `review.critical_issues` | integer | Yes | Must be 0 for SHIP verdict |
| `review.important_issues` | integer | Yes | Must be 0 for SHIP verdict |
| `review.minor_issues` | integer | Yes | Informational only — does not affect verdict |
| `score.current` | integer | Yes | Must be >= `shipping.min_score` |
| `score.target` | integer | Yes | The configured `shipping.min_score` value |
| `verdict` | string | Yes | `"SHIP"` or `"BLOCK"` |
| `block_reasons` | string[] | Yes | Empty when SHIP. Lists all failing checks when BLOCK. |

## Verdict Rules

`verdict: "SHIP"` requires ALL of:
- `build.exit_code == 0`
- `tests.exit_code == 0` AND `tests.failed == 0`
- `lint.exit_code == 0`
- `review.critical_issues == 0` AND `review.important_issues == 0`
- `score.current >= shipping.min_score`

Any violation → `verdict: "BLOCK"` with `block_reasons` listing each failing condition.

## Staleness

Evidence older than the **effective staleness window** is treated as missing. The PR builder checks `timestamp` against the current time and refuses to create a PR with stale evidence.

### Effective Staleness Window

```
generation_duration = timestamp - generation_started_at (minutes)
effective_window = max(evidence_max_age_minutes, generation_duration + 5)
```

Evidence is stale when: `now - timestamp > effective_window`

This ensures that slow builds (where `generation_duration` exceeds `evidence_max_age_minutes`) do not immediately invalidate their own evidence. The 5-minute buffer accounts for PR builder startup time.

The configured `evidence_max_age_minutes` (default: 30, range: 5-60) remains the minimum window. The effective window only extends beyond it when the generation itself took longer.

### Evidence Refresh Loop Cap

If evidence is stale on re-check, the orchestrator re-dispatches fg-590. The field `evidence_refresh_count` (in `state.json`) tracks how many times this has occurred. After 3 stale-evidence refreshes, the pipeline escalates to the user instead of looping. See row 52 in `shared/state-transitions.md`.

## Lifecycle

1. Created by `fg-590-pre-ship-verifier` after DOCS (Stage 7)
2. Read by orchestrator (`fg-100`) to decide SHIP vs loop-back
3. Read by PR builder (`fg-600`) as a hard gate before PR creation
4. Overwritten on each fg-590 invocation (no append, no history — history is in `state.json.evidence.block_history`)

## Partial Failure Handling

Evidence collection runs four checks sequentially: build, tests, lint, review. If any check partially fails (timeout, crash, indeterminate result), the following rules apply.

### Check-Level Failure Modes

| Check | Failure Mode | Evidence Field | Verdict Effect |
|-------|-------------|---------------|----------------|
| Build | Command times out (`build_timeout` exceeded) | `build.exit_code: -1`, `build.output_tail: "TIMEOUT after {N}s"` | BLOCK with `block_reasons: ["build_timeout"]` |
| Build | Command crashes (signal) | `build.exit_code: {signal + 128}` | BLOCK with `block_reasons: ["build_crash"]` |
| Tests | Command times out (`test_timeout` exceeded) | `tests.exit_code: -1`, `tests.total: 0` | BLOCK with `block_reasons: ["test_timeout"]` |
| Tests | Partial completion (some suites pass, runner crashes) | `tests.exit_code: {code}`, `tests.passed: {partial}`, `tests.failed: -1` | BLOCK with `block_reasons: ["test_partial_failure"]` |
| Lint | Command times out (`lint_timeout` exceeded) | `lint.exit_code: -1` | BLOCK with `block_reasons: ["lint_timeout"]` |
| Review | Agent timeout (>10min) | `review.dispatched: true`, `review.critical_issues: -1` | BLOCK with `block_reasons: ["review_timeout"]` |
| Review | Agent crash | `review.dispatched: false` | BLOCK with `block_reasons: ["review_not_dispatched"]` |

### Sentinel Values

- `exit_code: -1` indicates timeout (the command did not produce an exit code)
- `tests.failed: -1` indicates the test runner crashed before reporting results
- `review.critical_issues: -1` indicates the review agent did not return a structured result

### Sequential Short-Circuit

Evidence collection is sequential: build -> tests -> lint -> review. If build fails (non-zero exit code), subsequent checks are **not skipped** -- all four run regardless. Rationale: even with a build failure, lint and review may surface additional issues that inform the fix cycle.

**Exception:** If `build.exit_code` is -1 (timeout), tests are skipped (they cannot run without a successful build). Lint and review still run against the source code (they do not require a build artifact). Skipped checks are recorded with their sentinel values, not omitted from `evidence.json`.

### Block History

Each BLOCK verdict appends to `state.json.evidence.block_history[]`:

```json
{
  "attempt": 2,
  "reasons": ["test_timeout"],
  "scores": { "build": 0, "tests": -1, "lint": 0, "review": 0 },
  "timestamp": "2026-04-13T10:00:00Z"
}
```

The orchestrator uses `block_history` to detect patterns (e.g., tests consistently timing out across attempts) and may adjust timeouts or escalate to the user.
