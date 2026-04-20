# Resilience Learnings

Per-project cumulative learnings for `fg-555-resilience-tester`.

## Discovered patterns

(auto-populated by `fg-700-retrospective`)

## Calibration

| Rule | Static/Dynamic | Default cap | Notes |
|---|---|---|---|
| `RESILIENCE-TIMEOUT-UNBOUNDED` | Static | CRITICAL | Cheap grep; always on when agent dispatched |
| `RESILIENCE-RETRY-UNBOUNDED` | Static | WARNING | Can be INFO for CLI scripts |
| `RESILIENCE-CIRCUIT-MISSING` | Static | WARNING | Suppress when `state.downstreams` is empty |
| `RESILIENCE-CHAOS-*` | Dynamic | WARNING | Flake-prone; capped per spec §10 R3 |
