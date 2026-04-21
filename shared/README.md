# shared/ — index

Canonical runtime contracts and shared knowledge for the forge pipeline.
Grouped by responsibility. Items marked **(auto)** are generated or
machine-validated; do not hand-edit.

## Agents & dispatch

- [`agent-communication.md`](agent-communication.md) — stage notes, findings dedup, PREEMPT, structured output
- [`agent-philosophy.md`](agent-philosophy.md) — how to design an agent
- [`agent-defaults.md`](agent-defaults.md) — shared constraints language
- [`agent-ui.md`](agent-ui.md) — UI tools (AskUserQuestion, TaskCreate, plan mode)
- [`agent-colors.md`](agent-colors.md) — cluster palette
- [`agents.md`](agents.md) — agent model, UI tiers, dispatch graph, and full registry
- [`ask-user-question-patterns.md`](ask-user-question-patterns.md) — UX patterns

## State, transitions, recovery

- [`state-schema.md`](state-schema.md) — overview, lifecycle, top-level schema
- [`state-schema.json`](state-schema.json) — JSON Schema for state
- [`state-transitions.md`](state-transitions.md) — FSM transition table
- [`sprint-state-schema.md`](sprint-state-schema.md) — sprint-mode state additions
- [`stage-contract.md`](stage-contract.md) — per-stage contracts
- [`recovery/`](recovery/) — strategies and engine
- [`error-taxonomy.md`](error-taxonomy.md) — 22 error types
- [`convergence-engine.md`](convergence-engine.md) — algorithm + counters
- [`convergence-examples.md`](convergence-examples.md) — worked examples
- [`state-integrity.sh`](state-integrity.sh) — state-file integrity check

## Scoring & review

- [`scoring.md`](scoring.md) — score formula + categories
- [`confidence-scoring.md`](confidence-scoring.md) — two-level confidence
- [`decision-log.md`](decision-log.md) — decision journaling
- [`verification-evidence.md`](verification-evidence.md) — SHIP verdict contract
- [`logging-rules.md`](logging-rules.md) — what agents log
- [`output-compression.md`](output-compression.md) — output verbosity levels
- [`input-compression.md`](input-compression.md) — caveman input modes
- [`reviewer-boundaries.md`](reviewer-boundaries.md) — reviewer scope boundaries
- [`checks/`](checks/) — check engine rules + category registry

## Knowledge & learning

- [`learnings/`](learnings/) — per-module PREEMPT item files
- [`learnings-index.md`](learnings-index.md) **(auto)** — index of all learnings
- [`cross-project-learnings.md`](cross-project-learnings.md) — cross-repo sharing
- [`learnings/memory-discovery.md`](learnings/memory-discovery.md) — auto-discovered items
- [`learnings/rule-promotion.md`](learnings/rule-promotion.md) — MEDIUM→HIGH promotion
- [`learnings/decay.md`](learnings/decay.md) — Ebbinghaus decay curves
- [`explore-cache.md`](explore-cache.md) — EXPLORE-stage cache
- [`plan-cache.md`](plan-cache.md) — plan reuse
- [`knowledge-base.md`](knowledge-base.md) — active knowledge base
- [`cache-integrity.md`](cache-integrity.md) — cache validity rules

## Integrations

- [`mcp-server/`](mcp-server/) — Python MCP server exposing .forge/
- [`mcp-provisioning.md`](mcp-provisioning.md) — init-time MCP setup
- [`mcp-detection.md`](mcp-detection.md) — which MCPs are available
- [`mcp-governance.md`](mcp-governance.md) — MCP policy + untrusted flow
- [`graph/`](graph/) — Neo4j + SQLite code graph
- [`a2a-protocol.md`](a2a-protocol.md) — cross-repo coordination (filesystem)
- [`a2a-http-transport.md`](a2a-http-transport.md) — cross-repo HTTP transport
- [`cross-repo-contracts.md`](cross-repo-contracts.md) — cross-repo contract schema
- [`context7-query-templates.md`](context7-query-templates.md) — Context7 usage

## Features (v2.0+)

- [`living-specifications.md`](living-specifications.md) — F05 spec drift
- [`spec-inference.md`](spec-inference.md) — F12 function-level specs
- [`performance-regression.md`](performance-regression.md) — F17 perf tracking
- [`accessibility-automation.md`](accessibility-automation.md) — F15 a11y
- [`i18n-validation.md`](i18n-validation.md) — F16 i18n
- [`next-task-prediction.md`](next-task-prediction.md) — F18 predictions
- [`dx-metrics.md`](dx-metrics.md) — F19 DX metrics
- [`monorepo-integration.md`](monorepo-integration.md) — F20 Nx/Turborepo
- [`feature-flag-management.md`](feature-flag-management.md) — F23 flag cleanup
- [`deployment-strategies.md`](deployment-strategies.md) — F24 canary/blue-green
- [`consumer-driven-contracts.md`](consumer-driven-contracts.md) — F25 Pact
- [`flaky-test-management.md`](flaky-test-management.md) — F14 flaky quarantine
- [`playbooks.md`](playbooks.md) — F11/F31 playbook + refinement

## Tooling scripts

- [`forge-state.sh`](forge-state.sh) — FSM executor
- [`forge-state-write.sh`](forge-state-write.sh) — atomic JSON writes
- [`forge-token-tracker.sh`](forge-token-tracker.sh) — token budget tracking
- [`forge-linear-sync.sh`](forge-linear-sync.sh) — Linear sync
- [`forge-sim.sh`](forge-sim.sh) — pipeline simulation
- [`forge-sim-runner.py`](forge-sim-runner.py) — Python sim runner
- [`forge-timeout.sh`](forge-timeout.sh) — timeout enforcement
- [`forge-event.sh`](forge-event.sh) — event log append
- [`emit-event.sh`](emit-event.sh) — generic event emitter
- [`caveman-benchmark.sh`](caveman-benchmark.sh) — token savings
- [`compression-validation.py`](compression-validation.py) — compression eval
- [`check_prerequisites.py`](check_prerequisites.py) — Python 3.10+ validation
- [`check-environment.sh`](check-environment.sh) — optional tool detection
- [`config-validator.sh`](config-validator.sh) — legacy config validator
- [`config_validator.py`](config_validator.py) — Python config validator
- [`config-diff.sh`](config-diff.sh) — config diff helper
- [`validate-config.sh`](validate-config.sh) — config schema check
- [`validate-conventions.sh`](validate-conventions.sh) — convention lint
- [`validate-finding.sh`](validate-finding.sh) — finding shape check
- [`validate_finding.py`](validate_finding.py) — Python finding validator
- [`context-guard.sh`](context-guard.sh) — context-window guard (legacy)
- [`context_guard.py`](context_guard.py) — Python context guard
- [`cost-alerting.sh`](cost-alerting.sh) — cost ceiling alerts (legacy)
- [`cost_alerting.py`](cost_alerting.py) — Python cost alerting
- [`generate-conventions-index.sh`](generate-conventions-index.sh) — conventions index (legacy)
- [`generate_conventions_index.py`](generate_conventions_index.py) — Python conventions index
- [`orchestrator-injection-gate.sh`](orchestrator-injection-gate.sh) — prompt-injection gate
- [`preflight-injection-check.sh`](preflight-injection-check.sh) — PREFLIGHT injection scan
- [`platform.sh`](platform.sh) — OS/platform probe
- [`convergence-engine-sim.sh`](convergence-engine-sim.sh) — convergence sim (bash)
- [`convergence_engine_sim.py`](convergence_engine_sim.py) — convergence sim (Python)

## Conventions & process

- [`composition.md`](composition.md) — convention precedence
- [`composition-matrix.md`](composition-matrix.md) — composition matrix
- [`framework-gotchas.md`](framework-gotchas.md) — non-obvious per-framework
- [`preflight-constraints.md`](preflight-constraints.md) — PREFLIGHT validation
- [`model-routing.md`](model-routing.md) — model tier selection
- [`intent-classification.md`](intent-classification.md) — /forge-run routing
- [`domain-detection.md`](domain-detection.md) — domain scoping
- [`git-conventions.md`](git-conventions.md) — branch + commit rules
- [`version-resolution.md`](version-resolution.md) — version lookup policy
- [`platform-support.md`](platform-support.md) — supported OS matrix
- [`tdd-enforcement.md`](tdd-enforcement.md) — TDD inner-loop rules
- [`testing-anti-patterns.md`](testing-anti-patterns.md) — anti-pattern catalog
- [`debugging-techniques.md`](debugging-techniques.md) — debugging heuristics
- [`skill-subcommand-pattern.md`](skill-subcommand-pattern.md) — skill dispatch pattern
- [`tracking/tracking-schema.md`](tracking/tracking-schema.md) — kanban schema

## Policy & security

- [`data-classification.md`](data-classification.md) — secret redaction
- [`security-posture.md`](security-posture.md) — OWASP ASI compliance
- [`security-audit-trail.md`](security-audit-trail.md) — audit log
- [`untrusted-envelope.md`](untrusted-envelope.md) — `<untrusted>` contract
- [`prompt-injection-patterns.json`](prompt-injection-patterns.json) — regex library
- [`prompt-injection-patterns.schema.json`](prompt-injection-patterns.schema.json) — pattern schema
- [`skill-contract.md`](skill-contract.md) — skill frontmatter + doc rules
- [`hook-design.md`](hook-design.md) — hook execution model
- [`automations.md`](automations.md) — event-driven automation
- [`background-execution.md`](background-execution.md) — --background mode
- [`observability.md`](observability.md) — OTel traces
- [`visual-verification.md`](visual-verification.md) — screenshot-based verify
- [`lsp-integration.md`](lsp-integration.md) — LSP-level analysis
- [`event-log.md`](event-log.md) — event-sourced pipeline log
- [`context-condensation.md`](context-condensation.md) — stage-output compression
- [`frontend-design-theory.md`](frontend-design-theory.md) — design theory
- [`config-schema.json`](config-schema.json) — forge-config schema
- [`config-validation.md`](config-validation.md) — config validation rules
- [`pricing.json`](pricing.json) — model pricing data
- [`speculation.md`](speculation.md) — speculation candidate policy

## Generated / auto-updated

- [`learnings-index.md`](learnings-index.md) — by `scripts/gen-learnings-index.py`
- CI: `.github/workflows/docs-integrity.yml` validates freshness of this directory

---

**Item count at writing:** ~130 top-level items grouped into 10 clusters.
Strict <90 target is deferred to Phase 06b (see
[`../docs/superpowers/specs/2026-04-19-06b-shared-sub-directory-split.md`](../docs/superpowers/specs/2026-04-19-06b-shared-sub-directory-split.md)).
