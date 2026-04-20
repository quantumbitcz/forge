---
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
# See shared/learnings/decay.md for the canonical decay contract.
# Per-item base_confidence may be inherited from the legacy "Confidence: HIGH/MEDIUM/LOW" lines:
# HIGH→0.95, MEDIUM→0.75, LOW→0.5, ARCHIVED→0.3.
---
# Cross-Project Learnings: turborepo

## PREEMPT items

### KS-PREEMPT-001: Undeclared env vars cause cache poisoning
- **Domain:** build
- **Pattern:** Environment variables that affect build output must be declared in turbo.json `env` or `globalEnv`. Undeclared vars produce cache hits that return output built with different environment values.
- **Applies when:** `build_system: turborepo`
- **Confidence:** HIGH
- **Hit count:** 0

### KS-PREEMPT-002: pipeline renamed to tasks in Turbo 2.0
- **Domain:** configuration
- **Pattern:** The `pipeline` key in turbo.json was renamed to `tasks` in Turborepo 2.0. Using the old key silently falls back to defaults.
- **Applies when:** `build_system: turborepo` and Turborepo version >= 2.0
- **Confidence:** HIGH
- **Hit count:** 0

### KS-PREEMPT-003: outputs required for cache correctness
- **Domain:** build
- **Pattern:** Tasks without `outputs` in turbo.json cannot have their results cached. This is commonly missed for test tasks that produce coverage reports.
- **Applies when:** `build_system: turborepo`
- **Confidence:** HIGH
- **Hit count:** 0
