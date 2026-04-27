# Mutation Testing Report — shared/state-transitions.md

Regenerated on every CI run from `tests/mutation/state_transitions.py`. Commit this file; CI fails on drift.

**Strategy:** `MUTATE_ROW` env-var — participating scenarios read the env var and flip their expected `next_state` assertion when the row matches.

| row_id | description | scenario | mutation_applied | survived |
| --- | --- | --- | --- | --- |
| 37 | REVIEWING + score_regressing → ESCALATED | oscillation.bats | next_state: ESCALATED → IMPLEMENTING | NO |
| 28 | VERIFYING + safety_gate_fail<2 → IMPLEMENTING | safety-gate.bats | next_state: IMPLEMENTING → DOCUMENTING | NO |
| E-3 | ANY + circuit_breaker_open → ESCALATED | circuit-breaker.bats | next_state: ESCALATED → <prior> | NO |
| 47 | SHIPPING + pr_rejected design → PLANNING | feedback-loop.bats | next_state: PLANNING → IMPLEMENTING | NO |
| 48 | SHIPPING + feedback_loop_count>=2 → ESCALATED | feedback-loop.bats | guard: >= 2 → >= 3 | NO |
