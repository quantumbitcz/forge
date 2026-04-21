# Graduation Gate — Repo-map PageRank

Governs the rollout-stage-3 → stage-4 transition (flipping
`code_graph.prompt_compaction.enabled` default from `false` to `true` in
`plugin.json`).

## Gate criteria (all must hold across 20 consecutive passing `master` eval runs)

| # | Metric | Threshold | Source |
|---|---|---|---|
| G1 | Mean composite score delta (ON − OFF) | ≥ −2.0 points | `state.json.final_score`, scenario `10-repo-map-ab` |
| G2 | Mean orchestrator+planner prompt-token reduction | ≥ 30 % | `state.json.prompt_compaction.stages.*.pack_tokens` vs `baseline_tokens_estimate` |
| G3 | Mean elapsed delta | ≤ +5 % | `state.json.elapsed_ms` |
| G4 | `repomap.bypass.failure` aggregate count (sum over 20 runs) | = 0 | `state.json.prompt_compaction.bypass_events` (excludes `sparse_graph`) |
| G5 | Median `overall_ratio` | ≥ 0.25 | `state.json.prompt_compaction.overall_ratio` |

## Revert rule

A **single** master eval run with composite delta < −2.0 resets the consecutive counter to 0 and files a P1 issue before the next flip attempt. The code stays shipped; only the default flag reverts.

## Reviewer action at 20 runs

1. Run `python3 tests/evals/pipeline/summarize_runs.py --scenario 10-repo-map-ab --last 20` and confirm G1–G5.
2. Flip `code_graph.prompt_compaction.enabled` to `true` in the framework `forge-config-template.md` files (not `plugin.json` — the per-framework template is the resolved default).
3. Bump CLAUDE.md row to mark repo-map PageRank as "on by default."
4. Open a PR titled `chore(repomap): graduate prompt_compaction to default ON`.
