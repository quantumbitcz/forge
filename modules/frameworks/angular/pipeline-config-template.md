# Pipeline Configuration

Tunable parameters read by the orchestrator at the start of each run.
Updated by the retrospective agent based on run metrics. Manual edits welcome.

## Orchestration

| Parameter | Value | Description |
|-----------|-------|-------------|
| max_fix_loops | 3 | Max VERIFY fix attempts before escalating to user |
| max_review_loops | 2 | Max REVIEW iterations before escalating to user |
| auto_proceed_risk | MEDIUM | Highest risk level at which pipeline proceeds without asking (LOW, MEDIUM, HIGH, ALL) |
| parallel_impl_threshold | 3 | Dispatch parallel sub-agents when >= N independent implementation steps |
| total_retries_max | 10 | Global retry budget across all loops (5-30) |
| oscillation_tolerance | 5 | Score regression tolerance for quality cycles (0-20) |

## Review Agents

| Agent | Enabled | Weight | Notes |
|-------|---------|--------|-------|
| quality-gate | true | primary | GO/NO-GO verdict — orchestrator uses this for ship decision |
| frontend-reviewer | true | secondary | Conventions + security — findings merged into quality-gate |
| frontend-performance-reviewer | true | secondary | OnPush, change detection, bundle size |

## Domain Hotspots

Domains that frequently cause issues. Pipeline applies extra verification to these.
Updated automatically by the retrospective agent.

| Domain | Issue Count | Last Issue | Common Failure |
|--------|-------------|------------|----------------|
| — | 0 | — | — |

## Metrics

Cross-run metrics computed by the retrospective agent. Used for trend analysis and self-tuning.

| Metric | Value | Trend |
|--------|-------|-------|
| total_runs | 0 | — |
| successful_runs | 0 | — |
| avg_fix_loops | 0.0 | — |
| avg_review_loops | 0.0 | — |
| success_rate | — | — |
| preempt_effectiveness | — | — |

## Auto-Tuning Rules

Applied by the retrospective agent when updating this config:

1. If `avg_fix_loops` > `max_fix_loops - 0.5` for 3+ consecutive runs -> increment `max_fix_loops` by 1
2. If `avg_fix_loops` < 1.0 for 5+ consecutive runs -> decrement `max_fix_loops` by 1 (min: 2)
3. If a domain appears in hotspots 3+ times -> add a domain-specific PREEMPT to pipeline-log.md
4. If `success_rate` drops below 60% over last 5 runs -> set `auto_proceed_risk` to LOW (more cautious)
5. If `success_rate` is 100% over last 5 runs -> set `auto_proceed_risk` to HIGH (more autonomous)

# Scoring customization (uncomment to override defaults)
# scoring:
#   critical_weight: 20
#   warning_weight: 5
#   info_weight: 2
#   pass_threshold: 80
#   concerns_threshold: 60
#   oscillation_tolerance: 5  # Score regression tolerance for quality cycles (0-20)
