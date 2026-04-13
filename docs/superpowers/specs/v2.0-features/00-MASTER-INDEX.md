# Forge v2.0 — Master Design Index

## Status
DRAFT — 2026-04-13

## Overview

This document indexes all 35 design specifications for Forge v2.0. The specifications are organized into two tracks:

- **F-series (25 specs)**: New features and capabilities, prioritized P0–P4
- **Q-series (10 specs)**: Quality fixes and refactoring to reach A+ across all dimensions

### Current State (v1.20.1)
- Overall Grade: **B+ (84/100)**
- Weakest: Test Suite (B-, 75), Skills (B, 78), Hooks (B+, 83)
- Strongest: Core Contracts (A, 95), Module System (A, 95), Agents (A-, 90)

### Target State (v2.0)
- Overall Grade: **A+ (97+/100)**
- All dimensions at A or above
- 25 new features across 4 priority tiers
- ~118 new tests, ~60% orchestrator token reduction, ~70% pipeline cost reduction

### Research Basis
These specs are informed by competitive analysis of 19 systems (Devin, SWE-Agent, OpenHands, AutoCodeRover, Cursor, Windsurf, Cline, Aider, Continue.dev, GitHub Copilot, Amazon Q, Google Jules, JetBrains Junie, Sweep AI, OpenAI Codex, Claude Code), 12+ academic papers, and a deep internal audit.

---

## Spec Statistics

| Metric | Value |
|--------|-------|
| Total specs | 35 |
| Total lines | ~14,500 |
| Total size | ~776 KB |
| Feature specs (F-series) | 25 |
| Quality specs (Q-series) | 10 |
| New agents proposed | 3 (fg-515, fg-620, plus L0 scripts) |
| New module layers proposed | 4 (ml-ops, data-pipelines, feature-flags, deployment strategies) |
| New finding categories proposed | ~50+ |
| New bats tests proposed | ~130+ |

---

## P0 — Highest Priority (Core Pipeline Improvements)

Expected impact: 60-80% cost reduction, 30-40% fewer fix loops, syntax errors prevented at source.

| Spec | Feature | Key Innovation | Size |
|------|---------|---------------|------|
| [F02](F02-linter-gated-editing.md) | Linter-Gated Editing | L0 PreToolUse hook with tree-sitter syntax validation before edits land | 24 KB |
| [F03](F03-model-routing-default.md) | Model Routing Enabled by Default | 9 fast / 17 standard / 14 premium tier assignments with cascade fallback | 29 KB |
| [F04](F04-inner-loop-lint-test.md) | Inner-Loop Lint+Test at Implementer | Tight edit-lint-test-fix cycle inside TDD, 3-strategy affected test detection | 31 KB |

### Dependency Chain
```
F02 (L0 syntax check) ← F04 (inner loop uses L0)
F03 (model routing) ← F08 (condensation uses fast tier)
```

---

## P1 — Intelligence, DX, and Security

Expected impact: Zero-dependency code understanding, adaptive pipeline behavior, hardened security posture.

| Spec | Feature | Key Innovation | Size |
|------|---------|---------------|------|
| [F01](F01-tree-sitter-code-graph.md) | Tree-sitter Code Graph | SQLite-backed AST graph with 15 node types, 17 edge types, PageRank relevance | 28 KB |
| [F06](F06-confidence-scoring.md) | Confidence Scoring & Pre-Execution Gating | 4-dimension weighted algorithm, adaptive trust model, pre-run cost estimation | 24 KB |
| [F09](F09-active-knowledge-base.md) | Active Knowledge Base | BugBot-style learned rules, Rules vs Memories distinction, agent contribution hooks | 27 KB |
| [F10](F10-enhanced-security.md) | Enhanced Security | MCP governance, cache integrity, AST-aware secret detection, dependency provenance | 34 KB |

### Dependency Chain
```
F01 (code graph) ← F06 (confidence uses complexity from graph)
F01 (code graph) ← F10 (AST-aware secret detection uses tree-sitter)
F01 (code graph) ← F14 (predictive test selection uses file associations)
F09 (knowledge) ← F06 (familiarity signal from knowledge base)
```

---

## P2 — Quality and Developer Experience

Expected impact: 40-50% token savings on long runs, living spec enforcement, reusable task templates, smarter test execution.

| Spec | Feature | Key Innovation | Size |
|------|---------|---------------|------|
| [F05](F05-living-specifications.md) | Living Specifications | Machine-parseable AC-NNN criteria, drift detection, spec lifecycle | 20 KB |
| [F07](F07-event-sourced-pipeline-log.md) | Event-Sourced Pipeline Log | 12 event types, causal chains, replay from any point, subsumes decisions.jsonl | 25 KB |
| [F08](F08-context-condensation.md) | Context Condensation | LLM summarization with tag-based retention, 40-50% token savings | 23 KB |
| [F11](F11-playbooks.md) | Playbooks | User-defined task templates with analytics, 7 built-in, auto-suggestion | 27 KB |
| [F14](F14-flaky-test-management.md) | Flaky Test Management | flip_rate detection, auto-quarantine, predictive test selection | 33 KB |

### Dependency Chain
```
F05 (specs) ← F12 (spec inference generates specs)
F07 (events) ← F08 (condensation events recorded in log)
F14 (flaky tests) ← F01 (file associations from code graph)
F14 (flaky tests) ← F04 (inner loop uses predictive selection)
```

---

## P3 — Enhancements

Expected impact: Better bug fixes, stronger test quality, broader framework coverage, forward-looking analytics.

| Spec | Feature | Key Innovation | Size |
|------|---------|---------------|------|
| [F12](F12-function-level-spec-inference.md) | Function-Level Spec Inference | {Location, Specification} pairs from 5 evidence sources for bug fixes | 13 KB |
| [F13](F13-property-based-testing.md) | Property-Based Test Generation | fg-515 agent, 6 property categories, 10 PBT frameworks | 15 KB |
| [F15](F15-cross-browser-a11y-automation.md) | Cross-Browser & A11y Automation | Tab-order, focus, keyboard, ARIA checks + cross-browser pixel diff | 17 KB |
| [F16](F16-i18n-validation.md) | i18n Validation | Hardcoded string detection for 5 frameworks, RTL, locale formatting | 16 KB |
| [F17](F17-performance-regression-tracking.md) | Performance Regression Tracking | Benchmark store, rolling average comparison, custom metrics | 14 KB |
| [F18](F18-next-task-prediction.md) | Next-Task Prediction | 19 prediction rules, confidence ranking, accuracy tracking | 15 KB |
| [F19](F19-developer-experience-metrics.md) | DX Metrics Dashboard | 10 metrics, sprint burndown, /forge-insights integration | 14 KB |
| [F20](F20-monorepo-tooling.md) | Monorepo Tooling (Nx, Turborepo) | Affected detection, scoped testing, cache awareness | 18 KB |

---

## P4 — Forward-Looking

Expected impact: Cross-machine coordination, ML/data pipeline support, modern deployment patterns.

| Spec | Feature | Key Innovation | Size |
|------|---------|---------------|------|
| [F21](F21-a2a-network-protocol.md) | A2A Network Protocol | HTTP/WebSocket transport alongside filesystem, mTLS auth | 20 KB |
| [F22](F22-aiml-pipeline-support.md) | AI/ML Pipeline Support | MLflow, DVC, W&B, SageMaker, Airflow, Dagster, dbt modules | 21 KB |
| [F23](F23-feature-flag-management.md) | Feature Flag Management | LaunchDarkly, Unleash, Split modules, stale flag detection | 20 KB |
| [F24](F24-deployment-strategies.md) | Deployment Strategies | Canary/blue-green/rolling with fg-620-deploy-verifier agent | 24 KB |
| [F25](F25-consumer-driven-contracts.md) | Consumer-Driven Contracts | Pact integration, can-i-deploy gate, Specmatic/Spring Cloud Contract | 25 KB |

---

## Q-Series — Quality Fixes (B+ → A+)

These specs target every issue identified in the comprehensive system review.

| Spec | Target Area | Current → Target | Key Changes | Size |
|------|------------|-----------------|-------------|------|
| [Q01](Q01-skill-quality-overhaul.md) | Skills | B (78) → A+ (95+) | Canonical template, all 32 skills remediated, 12+ new bats tests | 13 KB |
| [Q02](Q02-agent-quality-improvements.md) | Agents | A- (90) → A+ (97+) | 6 descriptions fixed, 13 error messages improved, structured coordinator output | 16 KB |
| [Q03](Q03-orchestrator-size-reduction.md) | Token Cost | **DEFERRED** | Split into ~700 line core + 10 stage files — deferred per user feedback; prompt caching mitigates concern | 13 KB |
| [Q04](Q04-test-suite-expansion.md) | Test Suite | B- (75) → A (92+) | 118 new tests across 3 priority tiers, redesigned run-all.sh | 23 KB |
| [Q05](Q05-hooks-system-fixes.md) | Hooks | B+ (83) → A (93+) | file_changed wired, cache invalidation, deferred queue safety, atomic writes | 16 KB |
| [Q06](Q06-core-contract-refinements.md) | Core Contracts | A (95) → A+ (98+) | MEDIUM confidence 0.75x, PREEMPT examples, expanded mode overlays, logging contract | 19 KB |
| [Q07](Q07-module-structural-tests.md) | Module System | A (95) → A+ (98+) | Framework conformance tests, cross-cutting consistency tests, variant analysis | 15 KB |
| [Q08](Q08-documentation-completeness.md) | Documentation | A- (88) → A+ (96+) | Version migration, frontend→reviewer mapping, cross-ref audit, evidence partial failure | 19 KB |
| [Q09](Q09-config-validation-centralization.md) | Configuration | A- (90) → A+ (97+) | Centralized validator, JSON schemas, diff-based change detection | 21 KB |
| [Q10](Q10-coordinator-structured-output.md) | Agent Output | N/A → Machine-parseable | FORGE_STRUCTURED_OUTPUT standard, schemas for fg-400/500/700, contract tests | 19 KB |

---

## Implementation Roadmap

### Phase 1: Foundation (Recommended First)
*Estimated: 2-3 weeks*

| Order | Spec | Rationale |
|-------|------|-----------|
| 1 | Q01 | Skill triggers are the #1 user-facing improvement — fastest path to better DX |
| 2 | Q06 | Core contract fixes unblock accurate scoring for all subsequent work |
| 3 | F03 | Model routing enabled — immediate 60-80% cost reduction on every run |
| 4 | Q04 | Test expansion — safety net before making bigger changes |
| 5 | Q05 | Hooks fixes — prerequisite for F02 (linter-gated editing) |

### Phase 2: Core Pipeline (Build on Foundation)
*Estimated: 3-4 weeks*

| Order | Spec | Rationale |
|-------|------|-----------|
| 6 | F02 | Linter-gated editing — prevents syntax errors, prerequisite for F04 |
| 7 | F04 | Inner-loop lint+test — tighter feedback, fewer Stage 5 iterations |
| 8 | F01 | Tree-sitter code graph — enables intelligence features across the pipeline |
| 9 | ~~Q03~~ | ~~Orchestrator size reduction~~ — **DEFERRED**: user established orchestrator size is acceptable; prompt caching mitigates token cost |
| 10 | Q02 | Agent quality improvements — better descriptions, structured output |
| 11 | Q10 | Coordinator structured output — enables reliable retrospective analysis |

### Phase 3: Intelligence Layer
*Estimated: 2-3 weeks*

| Order | Spec | Rationale |
|-------|------|-----------|
| 12 | F06 | Confidence scoring — adaptive pipeline behavior |
| 13 | F09 | Active knowledge base — pipeline gets smarter over time |
| 14 | F10 | Enhanced security — hardened posture for autonomous operation |
| 15 | F14 | Flaky test management — smarter test execution |
| 16 | F08 | Context condensation — token savings on long convergence runs |

### Phase 4: Spec & Quality Layer
*Estimated: 2-3 weeks*

| Order | Spec | Rationale |
|-------|------|-----------|
| 17 | F05 | Living specifications — spec-driven development |
| 18 | F07 | Event-sourced pipeline log — debugging and replay |
| 19 | F11 | Playbooks — reusable task templates |
| 20 | Q07 | Module structural tests |
| 21 | Q08 | Documentation completeness |
| 22 | Q09 | Config validation centralization |

### Phase 5: Enhancements
*Estimated: 3-4 weeks*

| Order | Spec | Rationale |
|-------|------|-----------|
| 23-30 | F12-F20 | All P3 features — spec inference, PBT, a11y, i18n, perf, predictions, DX metrics, monorepo |

### Phase 6: Forward-Looking
*Estimated: 4-6 weeks*

| Order | Spec | Rationale |
|-------|------|-----------|
| 31-35 | F21-F25 | All P4 features — A2A network, AI/ML, feature flags, deployment strategies, contracts |

---

## Cross-Cutting Dependencies

```
F01 (code graph) ──┬── F06 (confidence)
                   ├── F10 (security - AST detection)
                   ├── F14 (predictive test selection)
                   ├── F04 (affected test detection)
                   └── F12 (spec inference - callers)

F02 (L0 syntax) ───── F04 (inner loop uses L0)

F03 (model routing) ── F08 (condensation uses fast tier)

F07 (event log) ────── F08 (condensation events)

F09 (knowledge) ────── F06 (familiarity signal)

Q05 (hooks fixes) ──── F02 (PreToolUse hook support)

Q06 (contracts) ────── F06 (confidence multiplier accuracy)

Q10 (structured output) ── F09 (knowledge from coordinator output)
```

---

## New Artifacts Summary

### New Agents
| Agent | Spec | Purpose |
|-------|------|---------|
| `fg-515-property-test-generator` | F13 | Property-based test generation |
| `fg-620-deploy-verifier` | F24 | Deployment health monitoring |

### New Scripts
| Script | Spec | Purpose |
|--------|------|---------|
| `shared/checks/l0-syntax/validate-syntax.sh` | F02 | Tree-sitter syntax validation |
| `shared/checks/l0-syntax/apply-edit-preview.py` | F02 | Edit preview for syntax check |
| `shared/graph/build-code-graph.sh` | F01 | Tree-sitter + SQLite graph builder |
| `shared/config-validator.sh` | Q09 | Centralized config validation |
| `shared/config-diff.sh` | Q09 | Per-section config change tracking |

### New Modules
| Module | Spec |
|--------|------|
| `modules/ml-ops/{mlflow,dvc,wandb,sagemaker}/` | F22 |
| `modules/data-pipelines/{airflow,dagster,dbt}/` | F22 |
| `modules/feature-flags/{launchdarkly,unleash,split,custom}/` | F23 |
| `modules/container-orchestration/strategies/{canary,blue-green,rolling}.md` | F24 |
| `modules/api-protocols/pact/` | F25 |
| `modules/code-quality/i18n-validation/` | F16 |
| `modules/build-systems/{nx,turborepo}/` | F20 |

### New `.forge/` Files
| File | Spec | Purpose |
|------|------|---------|
| `code-graph.db` | F01 | SQLite code graph |
| `events.jsonl` | F07 | Unified event log |
| `knowledge/` | F09 | Learned rules and patterns |
| `integrity.json` | F10 | Cache integrity checksums |
| `security-audit.jsonl` | F10 | Security event audit trail |
| `specs/index.json` | F05 | Spec registry |
| `test-history.json` | F14 | Per-test outcome tracking |
| `benchmarks.json` | F17 | Performance metrics |
| `predictions.json` | F18 | Next-task prediction tracking |
| `dx-metrics.json` | F19 | Developer experience metrics |
| `playbook-analytics.json` | F11 | Playbook usage analytics |

### New Finding Categories (~50+)
Spread across: `SPEC-DRIFT-*`, `SPEC-INFERENCE-*`, `TEST-PROPERTY-*`, `TEST-FLAKY`, `A11Y-KEYBOARD`, `A11Y-FOCUS`, `A11Y-ARIA`, `FE-BROWSER-COMPAT`, `I18N-*`, `PERF-REGRESSION-*`, `ML-*`, `FLAG-*`, `DEPLOY-*`, `CONTRACT-PACT-*`, `SEC-SUPPLY-*`

**Note**: The existing system has 24 categories (21 wildcard prefixes + 3 discrete). v2.0 adds ~50+, nearly tripling the count. Impact mitigation: all new categories use the same scoring formula, new categories default to opt-in (not enabled unless their feature is enabled), and category-registry.json gains a `feature_gate` field linking each category to its enabling config flag.

### Files Surviving `/forge-reset` (CLAUDE.md Update Required)
Existing: `explore-cache.json`, `plan-cache/`, `wiki/`, `agent-card.json`

New additions that MUST be documented in CLAUDE.md gotchas:
| File | Spec | Rationale |
|------|------|-----------|
| `code-graph.db` | F01 | Expensive to rebuild; incremental updates |
| `knowledge/` | F09 | Accumulated learned rules should persist |
| `test-history.json` | F14 | Historical flaky data is cross-run |
| `benchmarks.json` | F17 | Performance baselines are cross-run |
| `predictions.json` | F18 | Prediction accuracy tracking is cross-run |
| `dx-metrics.json` | F19 | DX trends are cross-run |
| `playbook-analytics.json` | F11 | Usage analytics are cross-run |

---

## Cross-Cutting Review Findings

Issues identified during spec review that affect multiple specs:

### 1. Acceptance Criteria Format
F05 defines `[AC-NNN] GIVEN/WHEN/THEN` as the standard format. Specs F12, F13, F15, F16, F17, F18, F19, F20 use numbered lists instead. **Resolution**: During implementation, all specs will adopt AC-NNN format in their acceptance criteria. The numbered lists in these specs are functionally equivalent and will be converted.

### 2. fg-710-post-run Agent Overload
Three specs add work: F11 (auto-suggestion), F18 (predictions), F19 (DX metrics). F17 also adds benchmark stats. **Resolution**: fg-710 will be restructured into modular parts. Each addition is gated by its feature config flag and produces a self-contained section. If combined token cost exceeds budget, low-priority parts (predictions, DX metrics) are condensed to summary-only.

### 3. Config Namespace Organization
v2.0 adds 10+ new top-level config sections. **Resolution**: Group under namespaces:
- `quality.*` — living_specs, property_testing, i18n, accessibility
- `performance.*` — performance_tracking, condensation, model_routing
- `testing.*` — test_history, flaky_detection, predictive_selection  
- `dx.*` — predictions, dx_metrics, playbooks
- Existing sections remain unchanged for backward compatibility.

### 4. Cumulative Token Cost
Individual specs claim low overhead, but combined cost is unaddressed. **Resolution**: All new features default to opt-in (disabled) except: model routing (F03, enabled), DX metrics (F19, negligible), and next-task prediction (F18, negligible). Users enable features they need; the pipeline doesn't pay for unused features.

### 5. Event Log Soft Dependencies
F08 and F14 emit events into F07's event log. **Resolution**: Both specs correctly declare this as optional. When F07 is unavailable, events are simply not emitted. No circular dependency — F08 defines CONDENSATION as its own event type and F07 includes it in the schema.
