# Apache Airflow — DAG Conventions & Operator Patterns

## Overview

Airflow orchestrates data pipelines as Directed Acyclic Graphs (DAGs). Each DAG defines tasks with dependencies, schedules, and retry behavior. Use Airflow for ETL/ELT workflows, data warehouse loads, ML training pipelines, and cross-system orchestration. DAGs are Python files in the `dags/` directory — Airflow parses them periodically, so module-level code must be lightweight. Operators execute the work; sensors wait for conditions; hooks interface with external systems.

## Architecture Patterns

### DAG Definition

```python
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator

default_args = {
    "owner": "data-team",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "execution_timeout": timedelta(hours=1),
}

with DAG(
    dag_id="etl_daily_users",
    default_args=default_args,
    schedule="@daily",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["etl", "users"],
    max_active_runs=1,
) as dag:
    extract = PythonOperator(task_id="extract", python_callable=extract_users)
    transform = PythonOperator(task_id="transform", python_callable=transform_users)
    load = PythonOperator(task_id="load", python_callable=load_users)
    extract >> transform >> load
```

Every DAG must set `catchup=False` unless historical backfills are intentional. Set `max_active_runs=1` for non-idempotent pipelines to prevent overlap. Define `retries` and `execution_timeout` in `default_args`.

### TaskFlow API (Airflow 2.x+)

```python
from airflow.decorators import dag, task

@dag(schedule="@daily", start_date=datetime(2024, 1, 1), catchup=False)
def etl_daily_users():
    @task
    def extract() -> dict:
        return fetch_from_api()

    @task
    def transform(data: dict) -> dict:
        return clean_and_validate(data)

    @task
    def load(data: dict):
        write_to_warehouse(data)

    raw = extract()
    cleaned = transform(raw)
    load(cleaned)

etl_daily_users()
```

Prefer the TaskFlow API for Python-only DAGs — it handles XCom serialization automatically and makes data dependencies explicit.

### Idempotency

Tasks must be idempotent — re-running a task with the same inputs should produce the same result without side effects. Use upserts instead of inserts. Partition output by execution date. Delete-then-insert is acceptable for full reloads.

## Configuration

- Store connection credentials in Airflow Connections (Admin > Connections), not in DAG code or environment variables.
- Use Airflow Variables for runtime configuration that changes between environments (dev/staging/prod).
- Access Variables and Connections inside task callables, never at module level — module-level access runs on every DAG parse and can cause import errors.
- Set `AIRFLOW__CORE__DAGS_FOLDER` to the `dags/` directory. Keep DAG files lean — heavy imports slow the scheduler.
- Use `airflow.cfg` or environment variables (`AIRFLOW__SECTION__KEY`) for Airflow-level configuration.

## Performance

- Keep DAG file parsing fast: avoid heavy imports, database queries, or API calls at module level.
- Use `@task.external_python` or `KubernetesPodOperator` to isolate heavyweight dependencies from the Airflow scheduler.
- Set `max_active_tasks_per_dag` to prevent a single DAG from consuming all worker slots.
- Use connection pooling (Airflow pools) to limit concurrent access to rate-limited external systems.
- Prefer `BashOperator` or `PythonOperator` over custom operators when the logic is straightforward — fewer moving parts.

## Security

- Never hardcode credentials in DAG files — use Airflow Connections with the Secrets Backend (Vault, AWS Secrets Manager).
- Set appropriate DAG-level and task-level access controls via Airflow RBAC.
- Use `execution_timeout` on all tasks to prevent hung tasks from blocking workers indefinitely.
- Audit DAG access: restrict who can modify DAGs in the `dags/` directory via Git branch protection.
- Use encrypted connections for all external system integrations.

## Testing

- Test task callables as plain Python functions with mock inputs — no Airflow runtime required.
- Use `dag.test()` (Airflow 2.5+) for local DAG execution with a single-threaded executor.
- Validate DAG structure: `dagbag = DagBag(); assert dagbag.import_errors == {}`.
- Test idempotency: run a task twice with the same inputs and verify identical outputs.
- Use `airflow dags test <dag_id> <date>` for end-to-end local testing.

## Dos
- Set `catchup=False` on all DAGs unless backfills are intentionally needed.
- Define `retries`, `retry_delay`, and `execution_timeout` in `default_args` for every DAG.
- Make all tasks idempotent — re-execution must produce the same result.
- Access Variables and Connections inside task callables, never at module level.
- Use the TaskFlow API for Python DAGs to make data dependencies explicit.
- Tag DAGs with meaningful labels for filtering in the Airflow UI.
- Set `max_active_runs=1` for pipelines that cannot safely overlap.

## Don'ts
- Don't access `Variable.get()` or `Connection.get()` at module level — it runs on every scheduler parse.
- Don't create DAGs without retry configuration — transient failures will cause unnecessary alerts.
- Don't use `PythonOperator` without `execution_timeout` — hung tasks block worker slots.
- Don't use `catchup=True` without understanding the backfill implications — it can trigger hundreds of runs.
- Don't store credentials in DAG code, environment variables, or Git — use Airflow Connections.
- Don't create non-idempotent tasks — duplicate inserts and side effects make recovery impossible.
- Don't import heavyweight libraries at the module level of DAG files — it slows the scheduler.
