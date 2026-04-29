---
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
# See shared/learnings/decay.md for the canonical decay contract.
# Per-item base_confidence may be inherited from the legacy "Confidence: HIGH/MEDIUM/LOW" lines:
# HIGH→0.95, MEDIUM→0.75, LOW→0.5, ARCHIVED→0.3.
---
# Cross-Project Learnings: spring

## PREEMPT items

### KS-PREEMPT-001: R2DBC updates all columns
- **Domain:** persistence
- **Pattern:** R2DBC update adapters must fetch-then-set to preserve @CreatedDate/@LastModifiedDate
- **Applies when:** `persistence: r2dbc`
- **Confidence:** HIGH
- **Hit count:** 0

### KS-PREEMPT-002: Generated OpenAPI sources excluded from detekt
- **Domain:** build
- **Pattern:** Detekt globs don't work with srcDir-added generated sources — use post-eval exclusion
- **Confidence:** HIGH
- **Hit count:** 0

### KS-PREEMPT-003: Kotlin core must use kotlin.uuid.Uuid not java.util.UUID
- **Domain:** domain
- **Pattern:** Core module uses Kotlin types; persistence layer uses Java types. Never mix.
- **Confidence:** HIGH
- **Hit count:** 0
# Cross-Project Learnings: spring (Java variant)

## PREEMPT items
