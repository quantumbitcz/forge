---
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
# See shared/learnings/decay.md for the canonical decay contract.
# Per-item base_confidence may be inherited from the legacy "Confidence: HIGH/MEDIUM/LOW" lines:
# HIGH→0.95, MEDIUM→0.75, LOW→0.5, ARCHIVED→0.3.
---
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
