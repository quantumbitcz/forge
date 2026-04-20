---
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
# See shared/learnings/decay.md for the canonical decay contract.
# Per-item base_confidence may be inherited from the legacy "Confidence: HIGH/MEDIUM/LOW" lines:
# HIGH→0.95, MEDIUM→0.75, LOW→0.5, ARCHIVED→0.3.
---
# Cross-Project Learnings: nx

## PREEMPT items

### KS-PREEMPT-001: Nx affected requires --base in CI
- **Domain:** build
- **Pattern:** CI pipelines using `nx affected` must pass `--base=origin/main` explicitly — the default base ref may not match the PR target branch
- **Applies when:** `build_system: nx` and CI pipeline
- **Confidence:** HIGH
- **Hit count:** 0

### KS-PREEMPT-002: @nrwl packages renamed to @nx
- **Domain:** dependencies
- **Pattern:** All `@nrwl/*` packages were renamed to `@nx/*` in Nx 16. Mixed `@nrwl` and `@nx` imports cause version resolution failures.
- **Applies when:** `build_system: nx` and Nx version >= 16
- **Confidence:** HIGH
- **Hit count:** 0

### KS-PREEMPT-003: Module boundary tags must be non-empty
- **Domain:** architecture
- **Pattern:** Empty `tags: []` in project.json disables module boundary enforcement for that project. Every project must have at least type and scope tags.
- **Applies when:** `build_system: nx` with `@nx/enforce-module-boundaries`
- **Confidence:** HIGH
- **Hit count:** 0
