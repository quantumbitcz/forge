---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
---
# Data Pipelines — Learnings

Cross-cutting learnings for data pipeline orchestration (Airflow, Dagster, dbt).

## Patterns

- DAG/pipeline definitions should be version-controlled alongside transformation code
- Idempotent tasks prevent data duplication on retries
- Schema validation at pipeline boundaries catches drift early

## Common Issues

- Stale DAG definitions cause silent pipeline failures
- Missing retry policies on external API calls cause cascading failures
- Hardcoded connection strings leak credentials in logs

## Evolution

Items below evolve via retrospective agent feedback loops.
