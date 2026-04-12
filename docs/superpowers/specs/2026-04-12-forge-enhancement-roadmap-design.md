# Forge Enhancement Roadmap — Design Spec

**Date:** 2026-04-12
**Scope:** 4 themed releases (v1.17 — v1.20), 21 features
**Approach:** Inside-Out (Cost → Quality → Enterprise → DX)
**Rationale:** Cost savings compound — every efficiency gained in v1.17 makes subsequent phases cheaper to develop and test.

---

## Release Overview

| Release | Theme | Features | Key Impact |
|---------|-------|----------|------------|
| **v1.17** | Cost & Efficiency | 5 features (#1-5) | 60-80% cost reduction, faster subsequent runs |
| **v1.18** | Quality Ceiling | 5 features (#6-10) | Best-in-class code quality output |
| **v1.19** | Enterprise Ready | 6 features (#11-16) | OTel, OWASP, automations, async execution |
| **v1.20** | Developer Experience | 5 features (#17-21) | Auto-wiki, memory discovery, codebase Q&A |

---

## v1.17: Cost & Efficiency

### Feature 1: Tiered Model Routing

**Problem:** All agents use the same model tier, but ~50% of pipeline tasks are pattern-matching (convention checks, scaffolding, docs) that don't need premium reasoning. This wastes 60-80% of token spend.

**Solution:** New `model_routing:` section in `forge-config.md`. The orchestrator reads tier assignments at PREFLIGHT and passes the `model` parameter when dispatching agents.

**Configuration:**
```yaml
model_routing:
  enabled: true
  default_tier: standard          # sonnet (default for all agents)
  overrides:
    tier_1_fast:                  # haiku — pattern matching, low-stakes
      - fg-310-scaffolder
      - fg-350-docs-generator
      - fg-130-docs-discoverer
      - fg-140-deprecation-refresh
    tier_3_premium:               # opus — complex reasoning, high-stakes
      - fg-200-planner
      - fg-210-validator
      - fg-411-security-reviewer
      - fg-412-architecture-reviewer
      - fg-020-bug-investigator
      - fg-300-implementer
```

**Integration points:**
- `shared/model-routing.md` — new shared contract defining tiers and resolution
- `agents/fg-100-orchestrator.md` — model selection logic added to dispatch
- `shared/agent-defaults.md` — document the `model` parameter in dispatch
- All `forge-config-template.md` files — add `model_routing:` section

**Constraints:**
- Model names must map to Claude Code's `model` parameter: `haiku`, `sonnet`, `opus`
- If configured model is unavailable, fall back to `default_tier`
- Retrospective (fg-700) can suggest tier adjustments based on finding quality per agent

---

### Feature 2: Incremental Codebase Indexing

**Problem:** The EXPLORE stage re-analyzes the entire codebase on every run, even when only a few files changed. This is one of the most token-intensive stages.

**Solution:** Persist an explore cache across runs. On subsequent runs, only re-analyze files changed since the last explored commit SHA (via `git diff`). Reuse cached data for unchanged files.

**State schema addition (persisted across runs, not reset by `/forge-reset`):**
```json
{
  "explore_cache": {
    "last_explored_sha": "abc123",
    "file_index": {
      "src/domain/Plan.kt": {
        "hash": "def456",
        "patterns": ["repository", "entity"],
        "dependencies": ["PlanRepository", "PlanService"]
      }
    },
    "cache_age_runs": 3,
    "max_cache_age_runs": 10
  }
}
```

**Integration points:**
- `shared/explore-cache.md` — new contract (cache structure, invalidation rules, staleness threshold)
- `shared/state-schema.md` — add `explore_cache` (persisted section)
- `agents/fg-100-orchestrator.md` — cache check at PREFLIGHT, partial EXPLORE dispatch
- `forge-config.md` templates — `explore: { cache_enabled: true, max_cache_age_runs: 10 }`

**Invalidation rules:**
- Full re-explore if `cache_age_runs > max_cache_age_runs`
- Full re-explore if `forge-config.md` conventions changed (hash mismatch)
- Partial re-explore: only files in `git diff last_explored_sha..HEAD`
- Manual override: `--full-explore` flag

---

### Feature 3: Plan Caching with Similarity Matching

**Problem:** Planning from scratch for every feature is expensive, especially when projects have recurring feature structures (new CRUD entity, new API endpoint, new service integration).

**Solution:** Cache PLAN outputs in `.forge/plan-cache/`. Before dispatching the planner, compare the new requirement against cached plans via keyword overlap and structural matching. Offer high-similarity matches as starting points.

**Cache structure:**
```
.forge/plan-cache/
+-- plan-2026-04-10-add-comments.json
+-- plan-2026-04-08-auth-middleware.json
+-- index.json
```

**Cache entry schema:**
```json
{
  "requirement": "Add plan comment feature with threading",
  "requirement_keywords": ["plan", "comment", "threading", "feature"],
  "domain_area": "plan",
  "plan_hash": "abc123",
  "stories_count": 4,
  "final_score": 94,
  "created_at": "2026-04-10T10:00:00Z",
  "source_sha": "def456",
  "plan_content": "..."
}
```

**Similarity algorithm:**
1. Extract keywords from new requirement (nouns, verbs, domain terms)
2. Compute Jaccard similarity with each cached plan's `requirement_keywords`
3. If similarity > 0.6 AND same `domain_area`: offer as starting point
4. Planner receives cached plan as optional context, adapts rather than creates from scratch

**Integration points:**
- `shared/plan-cache.md` — cache schema, similarity algorithm, staleness rules
- `agents/fg-100-orchestrator.md` — cache check before PLAN dispatch
- `agents/fg-200-planner.md` — accept optional cached plan as starting point
- `shared/state-schema.md` — add plan-cache directory to structure

**Constraints:**
- Max 20 cached plans (LRU eviction)
- Plans older than 30 days are evicted
- Cache miss is the normal path — no degradation when cache is empty

---

### Feature 4: Context Isolation per Agent

**Problem:** The quality gate sends the top 20 findings from previous batches to every reviewer as dedup hints, regardless of domain relevance. A security reviewer receives architecture findings; a frontend reviewer receives backend performance findings. This wastes ~60-80% of the dedup hint context.

**Solution:** Filter dedup hints by category affinity. Each reviewer only sees findings from categories relevant to its domain.

**Affinity mapping (added to `category-registry.json`):**
```json
{
  "SEC-*":  { "affinity": ["fg-411-security-reviewer"] },
  "ARCH-*": { "affinity": ["fg-412-architecture-reviewer"] },
  "PERF-*": { "affinity": ["fg-416-backend-performance-reviewer"] },
  "FE-PERF-*": { "affinity": ["fg-413-frontend-reviewer"] },
  "A11Y-*": { "affinity": ["fg-413-frontend-reviewer"] },
  "CONV-*": { "affinity": ["fg-410-code-reviewer", "fg-413-frontend-reviewer"] },
  "TEST-*": { "affinity": ["fg-410-code-reviewer"] },
  "DOC-*":  { "affinity": ["fg-418-docs-consistency-reviewer"] },
  "DEP-*":  { "affinity": ["fg-420-dependency-reviewer"] },
  "INFRA-*": { "affinity": ["fg-419-infra-deploy-reviewer"] },
  "QUAL-ERR-*": { "affinity": ["fg-410-code-reviewer", "fg-411-security-reviewer"] },
  "QUAL-COMPLEX": { "affinity": ["fg-410-code-reviewer", "fg-412-architecture-reviewer"] }
}
```

**Integration points:**
- `shared/checks/category-registry.json` — add `affinity` field per category
- `shared/agent-communication.md` — update section 3 with domain-scoped dedup hints
- `agents/fg-400-quality-gate.md` — filtering logic in batch dispatch

**Backward compatibility:** If `affinity` is missing for a category, that finding is sent to ALL reviewers (current behavior).

---

### Feature 5: Token Budget Reporting

**Problem:** Without per-stage token measurement, you can't make data-driven decisions about model routing, identify expensive stages, or track cost optimization progress.

**Solution:** Extend `forge-token-tracker.sh` and `state.json.cost` to record per-stage and per-agent token breakdowns.

**State schema extension:**
```json
{
  "cost": {
    "total_input_tokens": 450000,
    "total_output_tokens": 85000,
    "per_stage": {
      "PREFLIGHT": { "input": 15000, "output": 3000, "agents": ["fg-130", "fg-140"] },
      "EXPLORE":   { "input": 120000, "output": 25000, "agents": ["explorer"] },
      "PLAN":      { "input": 45000, "output": 12000, "agents": ["fg-200"] },
      "REVIEW":    { "input": 180000, "output": 30000, "agents": ["fg-410","fg-411","fg-412"] }
    },
    "model_distribution": { "haiku": 0.35, "sonnet": 0.45, "opus": 0.20 },
    "wall_time_seconds": 340,
    "estimated_cost_usd": 2.40
  }
}
```

**Integration points:**
- `shared/state-schema.md` — extend `cost` object with per-stage breakdown
- `shared/forge-token-tracker.sh` — per-stage tracking (increment on each agent dispatch)
- `agents/fg-700-retrospective.md` — analyze token distribution, suggest routing changes
- `agents/fg-710-post-run.md` — include token summary in recap report

---

## v1.18: Quality Ceiling

### Feature 6: LLM-Based Mutation Testing

**Problem:** Test suites can have 100% line coverage but only 4% mutation score — meaning they execute every line but catch almost no bugs. Meta's research (FSE 2025) shows LLM-generated targeted mutants with LLM-generated tests achieve 73% acceptance rate.

**Solution:** New optional `fg-510-mutation-analyzer` agent dispatched after tests pass in VERIFY. Generates targeted mutants for changed code and verifies tests catch them.

**New agent: `fg-510-mutation-analyzer`**
- Tier 4 (no UI)
- Tools: `Read`, `Write`, `Edit`, `Bash`, `Grep`, `Glob`
- Dispatched by: `fg-500-test-gate` after Phase B passes
- Input: changed files list, test commands, mutation categories
- Output: surviving mutants as findings in standard format

**Mutation categories:**
- `boundary_conditions` — off-by-one, `<=` vs `<`
- `null_handling` — removed null checks
- `error_paths` — swallowed exceptions, wrong error type
- `logic_inversions` — `&&` vs `||`, negated conditions

**New finding categories:**
| Code | Severity | Description |
|------|----------|-------------|
| `TEST-MUTATION-SURVIVE` | WARNING | Mutant survived — test gap |
| `TEST-MUTATION-TIMEOUT` | INFO | Mutant caused timeout (likely good — infinite loop) |
| `TEST-MUTATION-EQUIVALENT` | INFO | Mutant is functionally equivalent |

**Configuration:**
```yaml
mutation_testing:
  enabled: true
  scope: changed_files_only
  max_mutants_per_file: 5
  severity_on_surviving: WARNING
  categories:
    - boundary_conditions
    - null_handling
    - error_paths
    - logic_inversions
```

**Flow:**
1. `fg-500-test-gate` completes Phase B (tests pass)
2. If `mutation_testing.enabled`: orchestrator dispatches `fg-510-mutation-analyzer`
3. Agent reads changed files, generates 3-5 targeted mutants per file
4. Agent runs existing test suite against each mutant (in worktree copy)
5. Surviving mutants become `TEST-MUTATION-*` findings
6. Findings flow into quality gate as normal (convergence handles fix cycles)

**Integration points:**
- `agents/fg-510-mutation-analyzer.md` — new agent
- `agents/fg-500-test-gate.md` — dispatch mutation analyzer after Phase B
- `shared/scoring.md` — add `TEST-MUTATION-*` categories
- `shared/checks/category-registry.json` — register new categories
- `shared/agent-registry.md` — register fg-510
- `forge-config.md` templates — `mutation_testing:` section
- Tests: bump `MIN_AGENTS` in `module-lists.bash`

---

### Feature 7: Reviewer Deliberation Protocol

**Problem:** When reviewers produce conflicting findings (e.g., architecture says "extract to module" while performance says "keep inline for locality"), the current static priority ordering may discard valid findings without consideration.

**Solution:** Optional deliberation round in the quality gate. When conflicts are detected, both originating reviewers see each other's findings and can revise, maintain, or withdraw.

**Deliberation flow:**
1. Quality gate collects and deduplicates all findings
2. Detects conflicts: same `(file, line)` with contradictory recommendations from different agents
3. For each conflict cluster: re-dispatches both agents with narrow scope containing both findings
4. Each agent responds: `MAINTAIN` (keep as-is + reasoning), `REVISE` (adjust severity), or `WITHDRAW`
5. Quality gate applies deliberation results, proceeds with scoring

**Constraints:**
- Max 1 deliberation round (no infinite debate)
- Only for conflicts involving >= WARNING severity
- 60-second timeout per agent re-dispatch (original finding stands on timeout)
- Disabled by default

**Configuration:**
```yaml
quality_gate:
  deliberation: true
  deliberation_threshold: WARNING
  deliberation_timeout: 60
```

**Integration points:**
- `agents/fg-400-quality-gate.md` — deliberation dispatch logic
- `shared/agent-communication.md` — section 3.1 extended with deliberation protocol
- `shared/agent-defaults.md` — deliberation response format for reviewers

---

### Feature 8: Per-Finding Confidence Scores

**Problem:** All findings are treated with equal certainty. A reviewer that's 95% sure about a security flaw and 30% sure about a style nit both produce findings with the same authority. This hurts trust — developers learn to ignore findings when too many are false positives.

**Solution:** Extend finding format with a confidence field (HIGH/MEDIUM/LOW). Confidence affects scoring weight and routing.

**Extended finding format:**
```
file:line | CATEGORY-CODE | SEVERITY | CONFIDENCE | message | fix_hint
```

**Scoring interaction:**
| Confidence | Deduction Multiplier | Routing |
|------------|---------------------|---------|
| HIGH | 1.0x (full) | Auto-sent to implementer |
| MEDIUM | 1.0x (full) | Sent to implementer with annotation |
| LOW | 0.5x (half) | Flagged for human review, NOT auto-sent |

**Backward compatibility:** If confidence is omitted, default to HIGH (current behavior).

**Integration points:**
- `shared/checks/output-format.md` — add confidence field
- `shared/scoring.md` — confidence-weighted scoring rules
- `shared/agent-defaults.md` — confidence guidelines for reviewers
- All 9 reviewer agents — add confidence to output
- `agents/fg-400-quality-gate.md` — confidence-based routing

---

### Feature 9: Visual UI Verification

**Problem:** Frontend code review is code-only. Agents can't see what the UI actually looks like, missing layout breaks, responsive issues, and visual regressions that are obvious to a human looking at the screen.

**Solution:** When Playwright MCP is available and frontend files changed, take screenshots at multiple breakpoints and analyze them alongside code.

**Flow (fg-413 frontend reviewer):**
1. Navigate to relevant pages using dev server URL
2. Screenshots at 3 breakpoints: mobile (375px), tablet (768px), desktop (1440px)
3. Analyze for: visual regressions, layout breaks, contrast issues, responsive behavior
4. Include screenshot-based findings alongside code-based findings

**Flow (fg-320 frontend polisher):**
1. Take "before" screenshot at stage start
2. Apply polish changes
3. Take "after" screenshot
4. Verify: design token compliance, spacing consistency, visual hierarchy

**Configuration:**
```yaml
visual_verification:
  enabled: true
  dev_server_url: "http://localhost:3000"
  breakpoints: [375, 768, 1440]
  pages: []                        # auto-detected from changed routes, or explicit
```

**Graceful degradation:** If Playwright unavailable or dev server not running, skip visual checks with INFO finding.

**Integration points:**
- `agents/fg-413-frontend-reviewer.md` — visual verification section
- `agents/fg-320-frontend-polisher.md` — before/after comparison
- `shared/visual-verification.md` — new contract
- `forge-config.md` templates — `visual_verification:` section

---

### Feature 10: LSP Integration

**Problem:** Current code analysis is fundamentally "text search" — grep for patterns, read files, infer structure. This misses type-level issues, has false positives from pattern matching, and can't precisely resolve symbols.

**Solution:** Teach agents to use the LSP tool for compiler-level code understanding: go-to-definition, find-references, type checking, diagnostics.

**Value per agent:**
| Agent | Current | With LSP |
|-------|---------|----------|
| fg-412 (architecture) | Grep imports, infer boundaries | Precise dependency graph |
| fg-416 (performance) | Pattern match for N+1 | Type-aware analysis |
| fg-300 (implementer) | Grep for patterns | Accurate refactoring |
| fg-410 (code quality) | Pattern matching | Compiler warnings, unused code |
| Explorer | Broad file reading | Symbol-level codebase map |

**Configuration:**
```yaml
lsp:
  enabled: true
  languages:
    - typescript
    - kotlin
    - python
    - rust
    - go
```

**Graceful degradation:** LSP is optional. If unavailable, agents use current grep/glob approach.

**Integration points:**
- `shared/lsp-integration.md` — new contract (when to use, timeout handling)
- Reviewer and implementer agents — LSP usage sections
- `shared/agent-defaults.md` — LSP as optional integration

---

## v1.19: Enterprise Ready

### Feature 11: OpenTelemetry-Based Observability

**Problem:** No structured observability for pipeline performance. Token costs, stage durations, agent effectiveness are tracked in state.json but not in an industry-standard format suitable for enterprise dashboards.

**Solution:** Instrument the pipeline with OTel traces and metrics. Local mode stores in state.json; OTel mode exports to a collector.

**Trace hierarchy:**
```
Pipeline Run (root span)
+-- PREFLIGHT (stage span)
|   +-- fg-130-docs-discoverer (agent span)
|   +-- fg-140-deprecation-refresh (agent span)
+-- EXPLORE (stage span)
+-- PLAN (stage span)
+-- ...
+-- REVIEW (stage span)
|   +-- fg-400-quality-gate (agent span)
|   |   +-- batch-1 (batch span)
|   |   +-- deliberation (optional span)
+-- SHIP (stage span)
```

**Metrics:**
| Metric | Type |
|--------|------|
| `forge.stage.duration_seconds` | histogram |
| `forge.agent.duration_seconds` | histogram |
| `forge.agent.tokens.input` | counter |
| `forge.agent.tokens.output` | counter |
| `forge.convergence.iterations` | gauge |
| `forge.score` | gauge |
| `forge.findings.count` | counter (by category, severity) |
| `forge.recovery.budget_used` | gauge |
| `forge.model.distribution` | histogram |

**Configuration:**
```yaml
observability:
  enabled: true
  export: local                    # local | otel
  otel_endpoint: ""
  trace_all_agents: true
  metrics_in_recap: true
```

**Integration points:**
- `shared/observability.md` — new contract
- `shared/forge-otel-export.sh` — new script
- `shared/state-schema.md` — add `telemetry` object
- `agents/fg-100-orchestrator.md` — emit spans on transitions
- `agents/fg-700-retrospective.md` — analyze telemetry
- `agents/fg-710-post-run.md` — telemetry in recap

---

### Feature 12: Data Classification & Secret Redaction

**Problem:** Pipeline artifacts (state.json, stage notes, decision logs) may contain secrets or PII that leaked from source code. No systematic detection or redaction.

**Solution:** L1 check engine rules for secret detection, plus a redaction pass on pipeline artifacts.

**Classification tiers:**
| Tier | Pipeline Action |
|------|----------------|
| PUBLIC | No restriction |
| INTERNAL | No restriction (already gitignored) |
| CONFIDENTIAL | Redact from state.json, mask in logs |
| RESTRICTED | Block from artifacts entirely, WARNING finding |

**Detection patterns (L1):**
- API keys, tokens, passwords: `SEC-SECRET` (CRITICAL)
- Private keys: `SEC-SECRET` (CRITICAL)
- Email addresses, PII: `SEC-PII` (INFO)

**Redaction:** Fields matching CONFIDENTIAL/RESTRICTED are stored as `"[REDACTED:SEC-SECRET-001]"` in pipeline artifacts.

**Configuration:**
```yaml
data_classification:
  enabled: true
  redact_artifacts: true
  custom_patterns: []
  pii_detection: true
  block_restricted: true
```

**Integration points:**
- `shared/data-classification.md` — new contract
- `shared/checks/engine.sh` — add secret detection L1 patterns
- `shared/scoring.md` — add `SEC-SECRET`, `SEC-PII`, `SEC-REDACT` categories
- `shared/checks/category-registry.json` — register categories
- `agents/fg-411-security-reviewer.md` — reference data classification
- `forge-config.md` templates — `data_classification:` section

---

### Feature 13: Event-Driven Automations

**Problem:** Forge is manually invoked. Competing systems (Cursor Automations, Jules API, Kiro Hooks) trigger agents from CI failures, Slack messages, PR events — forge should too.

**Solution:** Automation definitions in `forge-config.md` that map external events to forge skills.

**Automation types:**
```yaml
automations:
  - name: ci-failure-fix
    trigger: ci_failure
    action: forge-fix
    filter: { branch: "main", workflow: "test" }
    cooldown_minutes: 30

  - name: pr-review
    trigger: pr_opened
    action: forge-review --full
    filter: { base: "main", label_exclude: ["skip-forge"] }

  - name: scheduled-health
    trigger: cron
    schedule: "0 6 * * 1"
    action: codebase-health
```

**Safety constraints:**
- Cooldown period per automation (prevent loops)
- Max concurrent automations: 3
- Destructive actions always require human approval
- All automations log to `.forge/automation-log.jsonl`

**Integration points:**
- `shared/automations.md` — new contract
- `hooks/automation-trigger.sh` — new script
- `skills/forge-automation.md` — new skill for managing automations
- `shared/state-schema.md` — add `.forge/automation-log.jsonl`
- `forge-config.md` templates — `automations:` section

---

### Feature 14: Async Background Execution

**Problem:** Long pipeline runs block the terminal. Users can't work while forge runs.

**Solution:** `--background` flag triggers artifact-based progress reporting instead of interactive UI.

**Progress artifacts:**
```
.forge/progress/
+-- status.json          # current stage, score, ETA
+-- timeline.jsonl       # append-only event log
+-- stage-summary/       # completed stage summaries
+-- alerts.json          # issues requiring attention
```

**`status.json` fields:**
- `run_id`, `stage`, `stage_number`, `progress_pct`, `score`
- `convergence_phase`, `convergence_iteration`
- `started_at`, `last_update`, `alerts`
- `model_usage` breakdown

**User interaction:**
- `/forge-status` reads progress artifacts
- `/forge-status --watch` polls with live updates
- Background run pauses at escalation points, writes to `alerts.json`
- Slack notification if Slack MCP available

**Integration points:**
- `shared/background-execution.md` — new contract
- `agents/fg-100-orchestrator.md` — background mode
- `skills/forge-status.md` — enhanced to read progress artifacts
- `shared/state-schema.md` — add `.forge/progress/` directory

---

### Feature 15: A2A Protocol for Cross-Repo Communication

**Problem:** Cross-repo coordination uses custom file-based polling. The industry is converging on Google's A2A protocol (JSON-RPC 2.0, structured task lifecycle, 150+ supporting organizations).

**Solution:** Enhance `fg-103-cross-repo-coordinator` to speak A2A, with fallback to current file-based coordination.

**A2A task lifecycle mapping:**
| A2A State | Forge State |
|-----------|-------------|
| `pending` | PREFLIGHT - PLANNING |
| `in-progress` | IMPLEMENTING - REVIEWING |
| `input-required` | Escalation / CONCERNS |
| `completed` | SHIPPED |
| `failed` | Abort |

**Agent card (`.well-known/agent.json`):**
```json
{
  "name": "forge-pipeline",
  "description": "Autonomous 10-stage development pipeline",
  "capabilities": { "streaming": false, "stateTransitionHistory": true },
  "skills": [
    { "id": "implement-feature" },
    { "id": "fix-bug" },
    { "id": "review-code" }
  ]
}
```

**Integration points:**
- `shared/a2a-protocol.md` — new contract
- `agents/fg-103-cross-repo-coordinator.md` — A2A dispatch logic
- `.well-known/agent.json` — agent card
- `shared/agent-communication.md` — section 7 updated

---

### Feature 16: OWASP Agentic Security Compliance

**Problem:** The OWASP Top 10 for Agentic Applications (2026) identifies specific risks. Forge should systematically address them.

**OWASP mapping:**
| Risk | Current Mitigation | Enhancement |
|------|-------------------|-------------|
| ASI01 Goal Hijacking | Orchestrator curates prompts | Input sanitization for requirements |
| ASI02 Tool Misuse | Read-only reviewers | Tool call audit log + anomaly detection |
| ASI03 Identity Abuse | Worktree isolation | Document permission model per tier |
| ASI04 Supply Chain | Convention file hashing | Signature verification |
| ASI05 Code Execution | Worktree | Document sandbox options (gVisor, Firecracker) |
| ASI06 Memory Poisoning | PREEMPT decay | Data classification (Feature 12) |
| ASI07 Inter-Agent Comms | All via orchestrator | A2A protocol (Feature 15) |
| ASI08 Cascading Failures | Recovery engine | Fan-out caps, anomaly detection |
| ASI09 Trust Exploitation | AskUserQuestion | Confidence scores (Feature 8) |
| ASI10 Rogue Agents | Forbidden actions | Tool call budget per agent |

**New security configuration:**
```yaml
security:
  input_sanitization: true
  tool_call_budget:
    default: 50
    overrides:
      fg-300-implementer: 200
      fg-500-test-gate: 150
  anomaly_detection:
    max_calls_per_minute: 30
    max_session_cost_usd: 10
  convention_signatures: true
```

**Integration points:**
- `shared/security-posture.md` — new contract
- `agents/fg-100-orchestrator.md` — input sanitization, budget enforcement
- `agents/fg-411-security-reviewer.md` — OWASP-aware review
- `SECURITY.md` — updated documentation
- `forge-config.md` templates — `security:` section

---

## v1.20: Developer Experience

### Feature 17: Auto-Generated Codebase Wiki

**Problem:** New team members and agents lack quick structural understanding of the codebase. Devin Wiki auto-indexes repos into architecture diagrams + documentation; forge should too.

**Solution:** New `fg-135-wiki-generator` agent that produces `.forge/wiki/` — a structured, auto-generated codebase reference.

**Wiki structure:**
```
.forge/wiki/
+-- index.md
+-- architecture.md
+-- modules/
|   +-- domain-plan.md
|   +-- infra-persistence.md
+-- api-surface.md
+-- data-model.md
+-- conventions-summary.md
+-- dependency-graph.md
+-- .wiki-meta.json
```

**New agent: `fg-135-wiki-generator`**
- Tier 3, Tools: `Read`, `Glob`, `Grep`, `Write`, `LSP`
- Dispatched at PREFLIGHT (full generation) and LEARN (incremental update)
- Skips if `.wiki-meta.json` `last_sha` matches HEAD

**Configuration:**
```yaml
wiki:
  enabled: true
  auto_update: true
  include_api_surface: true
  include_data_model: true
  max_module_depth: 3
```

**Integration points:**
- `agents/fg-135-wiki-generator.md` — new agent
- `shared/state-schema.md` — wiki directory structure
- `agents/fg-100-orchestrator.md` — dispatch at PREFLIGHT/LEARN
- `shared/agent-registry.md` — register fg-135
- Tests: bump `MIN_AGENTS`

---

### Feature 18: Autonomous Memory Discovery

**Problem:** Developers know codebase patterns tacitly but never document them. When agents run without this context, they produce code that violates unwritten conventions.

**Solution:** Enhance `fg-700-retrospective` to discover patterns across runs and store them as auto-discovered PREEMPT items.

**Discovery categories:** Naming patterns, architecture decisions, test patterns, configuration quirks, dependency patterns, error patterns.

**Discovery flow:**
1. EXPLORE: Note structural patterns
2. REVIEW: Note recurring conventions
3. LEARN: Compare observations across runs:
   - Pattern in 2+ runs → candidate
   - Candidate confirmed by code evidence → PREEMPT item (`source: auto-discovered`, confidence: MEDIUM)
   - Applied successfully → promoted to HIGH
   - False positive → demoted 2x faster

**New PREEMPT item fields:**
```yaml
- id: auto-repo-pattern-001
  source: auto-discovered
  confidence: MEDIUM
  evidence: { files_matching: 12, files_violating: 0 }
  decay_multiplier: 2
```

**Constraints:**
- Max 5 auto-discovered items per run
- Must have code evidence (3+ files)
- Clearly labeled, user can promote or dismiss

**Configuration:**
```yaml
memory_discovery:
  enabled: true
  max_discoveries_per_run: 5
  min_evidence_files: 3
  auto_promote_after_runs: 3
```

**Integration points:**
- `shared/learnings/memory-discovery.md` — new contract
- `agents/fg-700-retrospective.md` — discovery logic
- `shared/learnings/README.md` — document auto-discovered items
- `forge-config.md` templates — `memory_discovery:` section

---

### Feature 19: Pipeline Timeline Artifact

**Problem:** After a pipeline run, understanding what happened requires reading stage notes, state.json, and the recap separately. No single navigable artifact shows the full journey.

**Solution:** `fg-710-post-run` generates `.forge/reports/timeline-{storyId}.md` — a rich, navigable timeline of the entire run.

**Includes:**
- Run summary (duration, stages, iterations, score, model usage, tokens)
- Per-stage timeline with timestamps, key decisions, model/token data
- Convergence iteration details (score progression, findings per round)
- Decisions log (numbered, with stage and reasoning)
- Auto-discovered patterns (from Feature 18)
- Telemetry summary (from Feature 11)

**Integration points:**
- `agents/fg-710-post-run.md` — timeline generation
- `shared/state-schema.md` — add timeline report

---

### Feature 20: Codebase Q&A Search (`/forge-ask`)

**Problem:** Developers have questions about the codebase ("How does auth work?", "What tests cover payments?") that require multi-source exploration. No quick-answer mechanism.

**Solution:** New `/forge-ask` skill that queries wiki, graph, explore cache, and docs index to answer questions without a full pipeline run.

**Data source priority:**
1. `.forge/wiki/` (if enabled)
2. Neo4j graph (if available)
3. `.forge/explore-cache/` (if available)
4. `.forge/docs-index.json`
5. Direct codebase search (fallback)

**Configuration:**
```yaml
forge_ask:
  enabled: true
  deep_mode: false
  max_source_files: 20
  cache_answers: true
```

**Integration points:**
- `skills/forge-ask.md` — new skill
- No new agents — skill orchestrates existing data sources

---

### Feature 21: Pipeline Insights Dashboard (`/forge-insights`)

**Problem:** `/forge-history` shows raw run data but doesn't surface actionable trends (quality trajectory, agent effectiveness, cost analysis, convergence patterns, memory health).

**Solution:** Enhanced `/forge-insights` skill that reads reports, telemetry, and learnings to produce trend analysis.

**Insight categories:**
- Quality trajectory (score trends, recurring findings, convention candidates)
- Agent effectiveness (most impactful reviewer, least triggered, mutation kill rate)
- Cost analysis (average run cost, most expensive stage, routing savings)
- Convergence patterns (average iterations, plateau causes, safety gate failure rate)
- Memory health (active PREEMPT items, auto-discovered patterns, decay candidates)

**Integration points:**
- `skills/forge-insights.md` — new skill (or enhancement of `forge-history`)
- Reads: `.forge/reports/`, `state.json.telemetry`, `forge-log.md`

---

## New Files Summary

### New agents (3)
| Agent | Number | Tier | Release |
|-------|--------|------|---------|
| `fg-135-wiki-generator` | 135 | 3 | v1.20 |
| `fg-510-mutation-analyzer` | 510 | 4 | v1.18 |
| (Total: 40 agents, up from 38) | | | |

### New shared contracts (12)
| File | Release |
|------|---------|
| `shared/model-routing.md` | v1.17 |
| `shared/explore-cache.md` | v1.17 |
| `shared/plan-cache.md` | v1.17 |
| `shared/lsp-integration.md` | v1.18 |
| `shared/visual-verification.md` | v1.18 |
| `shared/observability.md` | v1.19 |
| `shared/data-classification.md` | v1.19 |
| `shared/automations.md` | v1.19 |
| `shared/background-execution.md` | v1.19 |
| `shared/a2a-protocol.md` | v1.19 |
| `shared/security-posture.md` | v1.19 |
| `shared/learnings/memory-discovery.md` | v1.20 |

### New skills (3)
| Skill | Release |
|-------|---------|
| `skills/forge-automation.md` | v1.19 |
| `skills/forge-ask.md` | v1.20 |
| `skills/forge-insights.md` | v1.20 |

### New scripts (2)
| Script | Release |
|--------|---------|
| `shared/forge-otel-export.sh` | v1.19 |
| `hooks/automation-trigger.sh` | v1.19 |

### Modified existing files (per release)

**v1.17:** `shared/agent-defaults.md`, `shared/state-schema.md`, `shared/checks/category-registry.json`, `shared/agent-communication.md`, `shared/forge-token-tracker.sh`, `agents/fg-100-orchestrator.md`, `agents/fg-200-planner.md`, `agents/fg-400-quality-gate.md`, `agents/fg-700-retrospective.md`, `agents/fg-710-post-run.md`, all `forge-config-template.md` files

**v1.18:** `shared/scoring.md`, `shared/checks/output-format.md`, `shared/checks/category-registry.json`, `shared/agent-defaults.md`, `agents/fg-500-test-gate.md`, `agents/fg-400-quality-gate.md`, `agents/fg-413-frontend-reviewer.md`, `agents/fg-320-frontend-polisher.md`, `agents/fg-412-architecture-reviewer.md`, `agents/fg-410-code-reviewer.md`, `agents/fg-300-implementer.md`, `shared/agent-registry.md`, all 9 reviewer agents (confidence)

**v1.19:** `shared/checks/engine.sh`, `shared/checks/rules-override.json`, `shared/state-schema.md`, `shared/agent-communication.md`, `agents/fg-100-orchestrator.md`, `agents/fg-103-cross-repo-coordinator.md`, `agents/fg-411-security-reviewer.md`, `SECURITY.md`, `skills/forge-status.md`

**v1.20:** `agents/fg-100-orchestrator.md`, `agents/fg-700-retrospective.md`, `agents/fg-710-post-run.md`, `shared/learnings/README.md`, `shared/agent-registry.md`

---

## Configuration Summary

All new configuration sections across all releases:

```yaml
# v1.17: Cost & Efficiency
model_routing:
  enabled: true
  default_tier: standard
  overrides:
    tier_1_fast: [fg-310-scaffolder, fg-350-docs-generator, fg-130-docs-discoverer, fg-140-deprecation-refresh]
    tier_3_premium: [fg-200-planner, fg-210-validator, fg-411-security-reviewer, fg-412-architecture-reviewer, fg-020-bug-investigator, fg-300-implementer]

explore:
  cache_enabled: true
  max_cache_age_runs: 10

# v1.18: Quality Ceiling
mutation_testing:
  enabled: true
  scope: changed_files_only
  max_mutants_per_file: 5
  severity_on_surviving: WARNING
  categories: [boundary_conditions, null_handling, error_paths, logic_inversions]

quality_gate:
  deliberation: false              # disabled by default
  deliberation_threshold: WARNING
  deliberation_timeout: 60

visual_verification:
  enabled: true
  dev_server_url: "http://localhost:3000"
  breakpoints: [375, 768, 1440]
  pages: []

lsp:
  enabled: true
  languages: [typescript, kotlin, python, rust, go]

# v1.19: Enterprise Ready
observability:
  enabled: true
  export: local
  otel_endpoint: ""
  trace_all_agents: true
  metrics_in_recap: true

data_classification:
  enabled: true
  redact_artifacts: true
  custom_patterns: []
  pii_detection: true
  block_restricted: true

automations: []                    # list of automation definitions

security:
  input_sanitization: true
  tool_call_budget:
    default: 50
    overrides: {}
  anomaly_detection:
    max_calls_per_minute: 30
    max_session_cost_usd: 10
  convention_signatures: true

# v1.20: Developer Experience
wiki:
  enabled: true
  auto_update: true
  include_api_surface: true
  include_data_model: true
  max_module_depth: 3

memory_discovery:
  enabled: true
  max_discoveries_per_run: 5
  min_evidence_files: 3
  auto_promote_after_runs: 3

forge_ask:
  enabled: true
  deep_mode: false
  max_source_files: 20
  cache_answers: true
```

---

## Research Sources

This design was informed by analysis of 13+ competing systems and 20+ research sources:

**Competing systems analyzed:** Cursor (cloud agents, automations), Devin (Wiki, Search, Review), GitHub Copilot (coding agent, agentic review), Google Jules (API, tools, KPI-driven), OpenAI Codex (sandbox, MCP server), Windsurf (Memories, Cascade), Amazon Q Developer, AWS Kiro (spec-first, Agent Hooks), Aider (repo map, architect mode), Cline (computer use, MCP), OpenHands (Index, SDK), Augment Code (Context Engine, Intent), OpenCode (LSP integration).

**Key research:** Anthropic context engineering blog, Manus context engineering blog, Meta LLM-based mutation testing (FSE 2025), Google multi-agent design patterns, OWASP Top 10 Agentic Applications 2026, Microsoft Agent Governance Toolkit, A2A protocol specification, Mem0/MemGPT memory architectures, SWE-bench Verified leaderboard, RedMonk 10 Things Developers Want, Zylos AI cost optimization research.
