# Weights & Biases (W&B) — Experiment Tracking & Sweeps

## Overview

W&B provides experiment tracking, hyperparameter sweeps, model versioning via Artifacts, and team dashboards. Use `wandb.init()` to start a run, `wandb.log()` to record metrics, and `wandb.Artifact` to version datasets and models. W&B Sweeps automate hyperparameter search with Bayesian optimization, grid search, or random search. The W&B platform hosts the dashboard — no self-hosted infrastructure required (though self-hosted is available).

## Architecture Patterns

### Experiment Tracking

```python
import wandb

wandb.init(project="churn-prediction", config={
    "learning_rate": 0.01,
    "epochs": 50,
    "batch_size": 32,
    "architecture": "xgboost",
})

for epoch in range(wandb.config.epochs):
    loss, accuracy = train_epoch(model, data)
    wandb.log({"loss": loss, "accuracy": accuracy, "epoch": epoch})

wandb.finish()
```

Every run must call `wandb.init()` with a `config` dictionary containing all hyperparameters. Use `wandb.log()` at each step/epoch for training curves. Always call `wandb.finish()` or use a context manager.

### Artifacts (Model & Data Versioning)

```python
artifact = wandb.Artifact("training-data", type="dataset")
artifact.add_dir("data/processed/")
wandb.log_artifact(artifact)

model_artifact = wandb.Artifact("churn-model", type="model")
model_artifact.add_file("models/model.pkl")
wandb.log_artifact(model_artifact)
```

Use Artifacts for all datasets and models. Artifacts provide versioning, lineage tracking, and deduplication. Reference artifacts by alias (`latest`, `production`) for deployment.

### Sweeps

```yaml
# sweep.yaml
method: bayes
metric:
  name: val_accuracy
  goal: maximize
parameters:
  learning_rate:
    min: 0.0001
    max: 0.1
    distribution: log_uniform_values
  batch_size:
    values: [16, 32, 64, 128]
  epochs:
    value: 50
```

```python
sweep_id = wandb.sweep(sweep_config, project="churn-prediction")
wandb.agent(sweep_id, function=train, count=20)
```

Define sweep configurations in YAML. Use Bayesian optimization for continuous parameters. Set `count` to limit the number of runs.

## Configuration

- Set `WANDB_API_KEY` as an environment variable — never hardcode in source.
- Use `WANDB_PROJECT` and `WANDB_ENTITY` environment variables for CI/CD runs.
- Configure `wandb.Settings(silent=True)` in production to suppress console output.
- Use `wandb.init(mode="offline")` for local development without network access, then `wandb sync` later.
- Set `WANDB_DIR` to control where local run data is stored (default: `./wandb/`).

## Performance

- Log metrics in batches: accumulate step metrics and call `wandb.log()` once per step rather than per metric.
- Use `wandb.log(commit=False)` for partial updates within a step, then `wandb.log(commit=True)` to flush.
- For large artifacts, use `artifact.add_reference()` to log a URI without uploading the actual data.
- Limit media logging (images, audio) to a sample per epoch — logging every sample overwhelms the dashboard.
- Use `wandb.init(resume="allow")` for long training runs to recover from interruptions without creating duplicate runs.

## Security

- Never log API keys, passwords, or secrets via `wandb.config` or `wandb.log()`.
- Use team-scoped projects with appropriate access controls.
- Review artifact contents before publishing — ensure no PII or credentials are included.
- Use `WANDB_API_KEY` from a secrets manager in CI/CD — never commit to `.env` files tracked by Git.

## Testing

- Use `wandb.init(mode="disabled")` in unit tests to prevent network calls and local file creation.
- Verify that `wandb.config` contains all expected hyperparameters after `wandb.init()`.
- Test sweep configurations by running a single agent with `count=1` and verifying the metric is logged.
- Use `wandb.Api()` in integration tests to verify artifacts were uploaded correctly.

## Dos
- Pass all hyperparameters to `wandb.init(config={...})` at the start of every run.
- Use `wandb.log()` at consistent intervals (per step or per epoch) for smooth training curves.
- Version datasets and models as W&B Artifacts with meaningful type labels.
- Use Sweeps for systematic hyperparameter search instead of manual trial-and-error.
- Set random seeds and log them in the config for reproducibility.
- Tag runs with metadata: `wandb.run.tags = ["baseline", "v2-features"]`.

## Don'ts
- Don't call `wandb.init()` without a config dictionary — runs without hyperparameters cannot be compared.
- Don't forget `wandb.finish()` — orphaned runs consume resources and appear as "running" in the dashboard.
- Don't log credentials or secrets via `wandb.config` or `wandb.log()`.
- Don't log high-frequency media (images/audio every step) — it overwhelms storage and slows the dashboard.
- Don't hardcode `WANDB_API_KEY` in source code — use environment variables or secrets managers.
- Don't skip artifact versioning for models — unversioned model files lack lineage and rollback capability.
