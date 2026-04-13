# MLflow — Experiment Tracking & Model Registry

## Overview

MLflow provides experiment tracking, model registry, and deployment for ML projects. Use the Tracking API to log parameters, metrics, and artifacts for every training run. Register models in the Model Registry for versioned deployment. MLflow Projects define reproducible runs; MLflow Models package inference artifacts with a standard interface across flavors (sklearn, pytorch, tensorflow, etc.).

## Architecture Patterns

### Experiment Tracking

```python
import mlflow

mlflow.set_experiment("churn-prediction")
with mlflow.start_run(run_name="xgboost-v3"):
    mlflow.log_params({"learning_rate": 0.01, "max_depth": 6, "n_estimators": 500})
    model = train(X_train, y_train)
    mlflow.log_metrics({"auc": 0.87, "f1": 0.82, "precision": 0.85})
    mlflow.xgboost.log_model(model, "model", registered_model_name="churn-xgboost")
```

Every run must log: (1) all hyperparameters via `log_params`, (2) evaluation metrics via `log_metrics`, (3) the trained model via the appropriate flavor's `log_model`. Omitting any of these breaks experiment comparison and reproducibility.

### Model Registry

```python
from mlflow.tracking import MlflowClient

client = MlflowClient()
client.transition_model_version_stage(
    name="churn-xgboost", version=3, stage="Production"
)
```

Use explicit stage transitions: `None` -> `Staging` -> `Production` -> `Archived`. Never deploy a model version that has not passed through `Staging` with documented evaluation metrics.

### MLflow Projects

```yaml
# MLproject
name: churn-prediction
conda_env: conda.yaml
entry_points:
  train:
    parameters:
      learning_rate: {type: float, default: 0.01}
      max_depth: {type: int, default: 6}
    command: "python train.py --lr {learning_rate} --depth {max_depth}"
```

Define an `MLproject` file at the repository root for reproducible execution. Pin the conda/pip environment to exact versions.

## Configuration

- Set `MLFLOW_TRACKING_URI` to a remote tracking server for team collaboration — never use the default `./mlruns` local directory in production.
- Use `MLFLOW_EXPERIMENT_NAME` or `mlflow.set_experiment()` to organize runs by project or model type.
- Configure artifact storage (`--default-artifact-root`) to point to S3, GCS, or Azure Blob — not local filesystem.
- Use `mlflow.autolog()` for supported frameworks (sklearn, pytorch, tensorflow, xgboost) to capture parameters and metrics automatically. Supplement with explicit `log_param` calls for custom hyperparameters not captured by autolog.

## Performance

- Batch metric logging: use `mlflow.log_metrics()` with a dictionary rather than individual `mlflow.log_metric()` calls to reduce HTTP round-trips.
- For large artifacts (models > 100 MB), configure artifact storage on object storage (S3/GCS) rather than the MLflow server's filesystem.
- Use `mlflow.start_run()` as a context manager to ensure runs are properly closed even on exceptions.
- Limit artifact logging frequency during training — log model checkpoints at epoch boundaries, not every step.

## Security

- Never log credentials, API keys, or secrets as parameters or tags.
- Use IAM roles or service accounts for artifact storage access — never embed access keys in MLproject files.
- Restrict MLflow tracking server access via authentication (MLflow does not provide auth natively — use a reverse proxy with auth).
- Audit model stage transitions — log who promoted a model to Production and the evaluation evidence.

## Testing

- Test training scripts by running a short training loop (1-2 epochs) with `mlflow.start_run()` and verifying logged parameters, metrics, and artifacts exist.
- Use `mlflow.set_tracking_uri("sqlite:///test.db")` for integration tests to avoid depending on a remote tracking server.
- Validate model registration by checking `MlflowClient().get_registered_model(name)` returns the expected versions.
- Test model loading: `mlflow.pyfunc.load_model(model_uri)` should return a callable model that produces predictions on sample input.

## Dos
- Log all hyperparameters with `mlflow.log_params()` at the start of every run.
- Log evaluation metrics with `mlflow.log_metrics()` after training completes.
- Use `registered_model_name` in `log_model()` to automatically register models.
- Pin dependency versions in `conda.yaml` or `requirements.txt` referenced by MLproject.
- Set random seeds (numpy, torch, tensorflow, random) before training and log the seed value.
- Use `mlflow.autolog()` as a baseline and supplement with explicit logging for custom parameters.
- Tag runs with metadata: `mlflow.set_tag("team", "ml-platform")`, `mlflow.set_tag("dataset_version", "v3")`.

## Don'ts
- Don't start an MLflow run without logging parameters — an empty run is useless for comparison.
- Don't use local `./mlruns` directory for team projects — use a shared tracking server.
- Don't log model files without using the model registry — unregistered models lack versioning and stage management.
- Don't hardcode tracking URIs in source code — use environment variables or configuration files.
- Don't log sensitive data (passwords, API keys, PII) as parameters, metrics, or tags.
- Don't skip `mlflow.end_run()` — use the context manager (`with mlflow.start_run():`) to ensure cleanup.
- Don't train without setting random seeds — non-reproducible results undermine experiment comparison.
