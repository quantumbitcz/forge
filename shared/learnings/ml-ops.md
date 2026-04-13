# ML-Ops — Learnings

Cross-cutting learnings for ML experiment tracking and model lifecycle (MLflow, DVC, W&B, SageMaker).

## Patterns

- Every experiment must log hyperparameters, metrics, and model artifacts for reproducibility
- Data versioning alongside model versioning prevents training/serving skew
- Model registry with stage transitions (staging → production) gates deployment

## Common Issues

- Missing data versioning makes experiment reproduction impossible
- Untracked dependencies between data preprocessing and training cause silent failures
- Large model artifacts committed to git instead of artifact storage bloat repositories

## Evolution

Items below evolve via retrospective agent feedback loops.
