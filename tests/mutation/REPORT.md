# Scenario-Sensitivity Probe Report — shared/state-transitions.md

Regenerated on every CI run from `tests/mutation/state_transitions.py`. Commit this file; CI fails on drift.

> **Note.** These rows are exercised via env-var assertion-flipping, NOT via source-file mutation. A `killed` outcome proves the scenario reached the row and the assertion would have caught a misconfigured row id; it does NOT prove a real bug in `state-transitions.md` or the state machine would be caught. See `state_transitions.py` docstring for the full semantics.

**Strategy:** `MUTATE_ROW` env-var — participating scenarios read the env var and flip their expected `next_state` assertion when the row matches. Each row is probed twice: first WITHOUT `MUTATE_ROW` (negative-control baseline) and then with `MUTATE_ROW=<id>`.

**Outcomes:**
- `killed` — baseline passed, mutation failed (scenario is sensitive to this row).
- `**survived (gap)**` — baseline passed, mutation also passed (scenario does NOT actually exercise this row; under-covered).
- `**baseline broken**` — baseline failed without mutation (scenario is broken; outcome for this row is undefined until the scenario is fixed).

| row_id | description | scenario | mutation_applied | baseline | outcome |
| --- | --- | --- | --- | --- | --- |
| 37 | REVIEWING + score_regressing -> ESCALATED | oscillation.bats | next_state: ESCALATED -> IMPLEMENTING | fail | **baseline broken** |
| 28 | VERIFYING + safety_gate_fail<2 -> IMPLEMENTING | safety-gate.bats | next_state: IMPLEMENTING -> DOCUMENTING | pass | killed |
| E-3 | ANY + circuit_breaker_open -> ESCALATED | circuit-breaker.bats | next_state: ESCALATED -> <prior> | pass | killed |
| 47 | SHIPPING + pr_rejected design -> PLANNING | feedback-loop.bats | next_state: PLANNING -> IMPLEMENTING | pass | killed |
| 48 | SHIPPING + feedback_loop_count>=2 -> ESCALATED | feedback-loop.bats | guard: >= 2 -> >= 3 | pass | killed |
