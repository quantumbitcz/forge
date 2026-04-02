# Agent Effectiveness Tracking

Operational guide for tracking review agent performance across pipeline runs. Updated by `fg-700-retrospective`. Data format defined in `agent-effectiveness-schema.json`.

## Metrics Per Agent

For each review agent dispatched during REVIEW stage:

| Metric | Description | Source |
|---|---|---|
| runs | Total times dispatched | stage notes |
| avg_time_seconds | Average wall time per dispatch | stage timestamps |
| avg_findings | Average findings returned per dispatch | quality gate report |
| false_positive_rate | Findings marked incorrect by implementer / total findings | fix cycle deltas |
| coverage_pct | Files reviewed / files changed | agent output vs changed files list |

## False Positive Detection

A finding is "false positive" when:
1. The implementer marks it as ACCEPTED (intentional trade-off) AND
2. The quality gate re-scores and the finding disappears (not because it was fixed, but because re-review no longer flags it)

NOT a false positive:
- Implementer fixes it (it was real)
- Implementer documents it as unfixable (it's real but out of scope)

## Auto-Tuning Triggers

| Condition | Threshold | Action |
|---|---|---|
| High false positive rate | >30% over 5+ runs | Suggest tightening agent's rules or reviewing conventions |
| Zero findings sustained | 0 findings over 5+ runs | Suggest agent may be redundant for this project |
| Slow execution | >120s average over 5+ runs | Suggest limiting file scope or splitting agent |

Note: The JSON schema at `agent-effectiveness-schema.json` uses 15% as a data recording threshold. The 30% trigger here is for retrospective action — a higher bar to avoid premature optimization of the agent lineup.
