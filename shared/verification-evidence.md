# Verification Evidence Schema

This document defines the evidence artifact that `fg-590-pre-ship-verifier` produces and `fg-600-pr-builder` validates before creating a PR. The evidence file is the single source of truth for shipping readiness.

## File Location

`.forge/evidence.json` — created fresh by `fg-590-pre-ship-verifier` on every invocation. Never cached, never carried over between runs.

## Schema

```json
{
  "evidence": {
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

Evidence older than `shipping.evidence_max_age_minutes` (default: 30, range: 5-60) is treated as missing. The PR builder checks `timestamp` against the current time and refuses to create a PR with stale evidence.

## Lifecycle

1. Created by `fg-590-pre-ship-verifier` after DOCS (Stage 7)
2. Read by orchestrator (`fg-100`) to decide SHIP vs loop-back
3. Read by PR builder (`fg-600`) as a hard gate before PR creation
4. Overwritten on each fg-590 invocation (no append, no history — history is in `state.json.evidence.block_history`)
