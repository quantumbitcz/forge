# forge

[![Latest Release](https://img.shields.io/github/v/release/quantumbitcz/forge?style=flat-square&color=blue)](https://github.com/quantumbitcz/forge/releases/latest)
[![License](https://img.shields.io/badge/license-Proprietary-red?style=flat-square)](LICENSE)
[![Agents](https://img.shields.io/badge/agents-42-green?style=flat-square)](#agents)
[![Skills](https://img.shields.io/badge/skills-35-green?style=flat-square)](#available-skills)
[![Frameworks](https://img.shields.io/badge/frameworks-21-orange?style=flat-square)](#available-modules)
[![Languages](https://img.shields.io/badge/languages-15-orange?style=flat-square)](#available-modules)
[![Finding Categories](https://img.shields.io/badge/finding_categories-87+-purple?style=flat-square)](#quality-scoring)
[![Build Systems](https://img.shields.io/badge/build_systems-9-blue?style=flat-square)](#available-modules)
[![Tests](https://img.shields.io/badge/tests-3040+-brightgreen?style=flat-square)](#testing)

> Autonomous 10-stage development pipeline for Claude Code. Point it at a requirement and get a tested, reviewed, documented pull request.

Claude Code is powerful, but without structure it makes inconsistent decisions, skips tests, forgets conventions, and produces PRs that need heavy review. **forge** fixes this by orchestrating **42 specialized agents** across 10 stages -- from exploration through TDD implementation, multi-perspective quality review, and self-improving retrospectives -- so every run follows the same disciplined process.

## Quick start

```bash
# 1. Install the plugin
/plugin marketplace add quantumbitcz/forge
/plugin install forge@quantumbitcz

# 2. Initialize your project (auto-detects framework, gitignores .forge/)
/forge-init

# 3. Run it
/forge-run Add user dashboard with activity feed
```

<details>
<summary>Alternative: install as Git submodule</summary>

```bash
git submodule add https://github.com/quantumbitcz/forge.git .claude/plugins/forge
```

Then add to `.claude/settings.json`:

```json
{
  "plugins": [".claude/plugins/forge"]
}
```

</details>

## Key features

- **Worktree isolation** -- Your working tree is never modified. All implementation runs in a git worktree (`.forge/worktree`).
- **L0 linter-gated editing** -- Tree-sitter syntax validation blocks invalid edits via PreToolUse hook before files are modified. Prevents cascading fix loops.
- **Inner-loop lint+test** -- Tight edit-lint-test-fix cycle inside the implementer. 3-strategy affected test detection (explore cache, code graph, directory heuristic).
- **Model routing** -- Curated tier assignments: 9 fast (haiku), 19 standard (sonnet), 14 premium (opus). 60-80% cost reduction with cascade fallback.
- **Output compression** -- 4 verbosity levels (verbose/standard/terse/minimal) per pipeline stage. 30-45% output token savings. Auto-clarity safety valve for security warnings.
- **Agent prompt compression** -- All 42 agent .md files compressed 27% (17,127 to 12,441 lines). Orchestrator reduced 53%.
- **Self-healing recovery** -- 7 recovery strategies with weighted budget (ceiling 5.5) handle transient failures, tool issues, and state corruption automatically.
- **4-layer check engine** -- L0 (tree-sitter pre-edit), L1 (regex sub-second), L2 (linter adapters), L3 (AI-driven deprecation + version compat).
- **Confidence scoring** -- 4-dimension weighted algorithm (clarity, familiarity, complexity, history) with adaptive trust model. Gates execution based on confidence.
- **Active knowledge base** -- BugBot-style learned rules from code review findings. Rules vs Memories distinction. PREEMPT integration.
- **Enhanced security** -- MCP governance allowlist, cache integrity (SHA256), Shannon entropy secret detection, 18 cloud credential patterns. OWASP ASI01-ASI10.
- **Flaky test management** -- flip_rate detection, automatic quarantine, predictive test selection via file associations (15-20% of suite).
- **Context condensation** -- LLM-powered summarization at 60% context threshold. Tag-based retention. 40-50% token savings on long convergence runs.
- **Living specifications** -- Machine-parseable AC-NNN acceptance criteria with drift detection at REVIEW. SPEC-DRIFT-* finding categories.
- **Event-sourced pipeline log** -- 12 event types with causal chains. Replay from any point. `.forge/events.jsonl`.
- **Playbooks** -- 5 built-in task templates (add-endpoint, fix-flaky-test, db-migration, webhook, extract-service) with analytics tracking.
- **Self-improving** -- Learnings from past runs proactively applied via PREEMPT system. Confidence decay prevents stale learnings.
- **Adaptive MCP detection** -- Auto-detects Linear, Playwright, Slack, Context7, Figma, Excalidraw, Neo4j at PREFLIGHT. No MCP required.
- **Version-aware deprecations** -- Schema v2 registries with `applies_from` and `removed_in` fields. Version-gated rules.
- **Frontend design quality** -- Creative polish, WCAG 2.2 AA audits (static + dynamic), cross-browser pixel diff, design system compliance.
- **Property-based testing** -- Optional fg-515 agent generates invariant/round-trip/idempotence/metamorphic tests for 10 PBT frameworks.
- **Concurrent run protection** -- Lock file prevents parallel runs. Global retry budget (default 10) prevents unbounded cascades.
- **Monorepo support** -- Nx and Turborepo modules with affected detection, scoped testing/building.
- **Environment health check** -- `/forge-init` probes for optional tools (jq, docker, tree-sitter, gh, sqlite3) and MCP integrations, displays a dashboard with platform-specific install suggestions.
- **Dynamic reviewer scaling** -- Quality gate scales review agents by change scope: <50 lines = batch 1 only, 50-500 = all batches, >500 = all batches + splitting recommendation.
- **Caveman benchmark** -- `/forge-compress output benchmark` measures actual token savings across lite/full/ultra compression modes on any file.

### The 10 stages

| # | Stage | What happens |
|---|-------|-------------|
| 0 | Preflight | Load config, detect versions, apply learnings, build code graph, assess confidence |
| 1 | Explore | Map domain models, tests, and patterns relevant to the requirement |
| 2 | Plan | Risk-assessed implementation plan with stories, tasks, parallel groups |
| 3 | Validate | 7-perspective validation (architecture, security, edge cases, tests, conventions, approach, docs) |
| 4 | Implement | TDD loop per task -- scaffold, write tests (RED), implement (GREEN), refactor. Inner-loop lint+test. |
| 5 | Verify | Build, lint, static analysis, full test suite, mutation testing, property-based testing |
| 6 | Review | Multi-agent quality review (up to 8 reviewers) with scoring and fix cycles |
| 7 | Docs | Update documentation, ADRs, API specs, changelogs |
| 8 | Ship | Evidence verification, branch, commit, PR with quality gate results |
| 9 | Learn | Retrospective analysis, config tuning, knowledge base updates, trend tracking, next-task prediction |

## Quality scoring

```
score = max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)
```

PASS >= 80, CONCERNS 60-79, FAIL < 60 or unresolved CRITICAL. Confidence-weighted: HIGH=1.0x, MEDIUM=0.75x, LOW=0.5x. **87+ finding categories** across 27 wildcard prefixes and 60+ discrete codes. See `shared/checks/category-registry.json`.

## Available skills

35 skills provide the user-facing interface.

Every skill advertises its impact with a `[read-only]` or `[writes]` prefix in its description. Read-only skills expose `--json`; writing skills expose `--dry-run`. All skills expose `--help`. See `shared/skill-contract.md` for the full contract.

| Skill | Badge | Description |
|-------|-------|-------------|
| `/forge-run` | [writes] | Main entry -- full 10-stage pipeline |
| `/forge-init` | [writes] | Initialize project config (auto-detects framework) |
| `/forge-fix` | [writes] | Bugfix workflow -- root cause investigation + targeted fix |
| `/forge-shape` | [writes] | Collaboratively shape features into structured specs |
| `/forge-sprint` | [writes] | Parallel multi-feature orchestration |
| `/forge-review` | [writes] | Review changed files (quick: 3 agents, full: 8 agents) |
| `/forge-status` | [read-only] | Show pipeline state, score, budgets |
| `/forge-recover` | [writes] | Diagnose/repair/reset/resume/rollback pipeline state (`<subcommand>` dispatch). Replaces 5 old recovery skills. |
| `/forge-abort` | [writes] | Graceful pipeline stop |
| `/forge-history` | [read-only] | Quality trends across runs |
| `/forge-profile` | [read-only] | Pipeline performance analysis |
| `/forge-insights` | [read-only] | Quality, cost, convergence analytics |
| `/forge-ask` | [read-only] | Codebase Q&A via wiki, graph, docs |
| `/forge-playbooks` | [writes] | Manage reusable task templates |
| `/forge-playbook-refine` | [writes] | Interactive review/apply of playbook refinements |
| `/forge-compress` | [writes] | Compress agents/output/status/help. Replaces `forge-caveman` and `forge-compression-help`. |
| `/forge-verify` | [read-only] | Quick build + lint + test check |
| `/forge-security-audit` | [read-only] | Module-appropriate security scanners |
| `/forge-review --scope=all` | [read-only] | Full check engine health report (codebase audit) |
| `/forge-review --scope=all --fix` | [writes] | Iterative fix loop until clean (AskUserQuestion safety gate) |
| `/forge-docs-generate` | [writes] | Generate project documentation |
| `/forge-deploy` | [writes] | Deployment (staging, production, preview, rollback) |
| `/forge-migration` | [writes] | Framework/library version migrations |
| `/forge-bootstrap` | [writes] | Scaffold new project from template |
| `/forge-verify --config` | [read-only] | Pre-pipeline config validation |
| `/forge-automation` | [writes] | Event-driven automation management |
| `/forge-graph` | [writes] | Knowledge graph dispatcher: `init`, `status`, `query <cypher>`, `rebuild`, `debug`. Replaces 5 old `forge-graph-*` skills. |
| `/forge-commit` | [writes] | Terse conventional commit from staged changes |
| `/forge-help` | [read-only] | Interactive decision tree to find the right skill |
| `/forge-tour` | [read-only] | Guided 5-stop introduction to Forge |
| `/forge-config` | [writes] | Interactive configuration editor |

## Available modules

| Category | Count | Examples |
|----------|-------|---------|
| Frameworks | 21 | spring, react, nextjs, fastapi, django, axum, angular, nestjs, vue, svelte, sveltekit, express, gin, go-stdlib, swiftui, vapor, jetpack-compose, kotlin-multiplatform, aspnet, embedded, k8s |
| Languages | 15 | kotlin, java, typescript, python, go, rust, swift, c, csharp, ruby, php, dart, elixir, scala, cpp |
| Testing | 19 | kotest, junit5, vitest, jest, pytest, go-testing, xctest, rust-test, playwright, cypress, cucumber, k6, detox, rspec, phpunit, exunit, scalatest, xunit-nunit, testcontainers |
| Build Systems | 9 | gradle, maven, npm, cargo, go, cmake, bazel, nx, turborepo |
| CI/CD | 7 | github-actions, gitlab-ci, circleci, azure-pipelines, bitbucket-pipelines, jenkins, tekton |
| Container/Orchestration | 11+ | docker, docker-compose, helm, k3s, argocd, fluxcd, openshift, rancher, podman + deployment strategies (canary, blue-green, rolling) |
| ML-Ops | 4 | mlflow, dvc, wandb, sagemaker |
| Data Pipelines | 3 | airflow, dagster, dbt |
| Feature Flags | 3 | conventions, launchdarkly, unleash |
| API Protocols | 4+ | rest, graphql, grpc, websocket, pact |
| Crosscutting | 10 dirs | databases, persistence, migrations, messaging, caching, search, storage, auth, observability, code-quality (~70 tools) |

All framework modules include `conventions.md` (with Dos/Don'ts), `local-template.md`, `forge-config-template.md`, `rules-override.json`, and `known-deprecations.json` (schema v2).

## Agents

42 agents organized by pipeline stage. See `shared/agents.md#registry` for the full list.

**Pipeline agents**: fg-010-shaper, fg-015-scope-decomposer, fg-020-bug-investigator, fg-050-project-bootstrapper, fg-090-sprint-orchestrator, fg-100-orchestrator, fg-101-worktree-manager, fg-102-conflict-resolver, fg-103-cross-repo-coordinator, fg-130-docs-discoverer, fg-135-wiki-generator, fg-140-deprecation-refresh, fg-150-test-bootstrapper, fg-160-migration-planner, fg-200-planner, fg-205-planning-critic, fg-210-validator, fg-250-contract-validator, fg-300-implementer, fg-310-scaffolder, fg-320-frontend-polisher, fg-350-docs-generator, fg-400-quality-gate, fg-500-test-gate, fg-505-build-verifier, fg-510-mutation-analyzer, fg-515-property-test-generator, fg-590-pre-ship-verifier, fg-600-pr-builder, fg-610-infra-deploy-verifier, fg-620-deploy-verifier, fg-650-preview-validator, fg-700-retrospective, fg-710-post-run.

**Review agents** (8): fg-410-code-reviewer, fg-411-security-reviewer, fg-412-architecture-reviewer, fg-413-frontend-reviewer, fg-416-performance-reviewer, fg-417-dependency-reviewer, fg-418-docs-consistency-reviewer, fg-419-infra-deploy-reviewer.

## Architecture

Visual diagrams of the pipeline, agent dispatch, and state machine:

- [Pipeline Flow](docs/architecture/pipeline-flow.md) -- 10-stage pipeline with decision points and feedback loops
- [Agent Dispatch](docs/architecture/agent-dispatch.md) -- 42 agents organized by pipeline stage
- [State Machine](docs/architecture/state-machine.md) -- 57 normal + 9 error state transitions

## Integrations

Auto-detected MCP servers at PREFLIGHT. All optional -- pipeline degrades gracefully.

| Integration | Purpose |
|-------------|---------|
| **Linear** | Epic/Story/Task tracking, status sync, quality comments |
| **Context7** | Library docs, migration guides, deprecation lookup |
| **Playwright** | Preview validation, visual regression, dynamic a11y |
| **Slack** | Notifications and status updates |
| **Figma** | Design reference and component mapping |
| **Neo4j** | Knowledge graph (dual-purpose: plugin seed + project codebase) |
| **Excalidraw** | Architecture diagrams |

## Configuration

### `forge.local.md` (static, checked into git)
Project identity: `language`, `framework`, `testing`, `commands` (build/test/lint), `scaffolder.patterns`, `quality_gate` batches, `context7_libraries`, `linear` settings.

### `forge-config.md` (mutable, auto-tuned by retrospective)
Runtime parameters: scoring weights, convergence limits (`max_iterations`, `plateau_threshold`), retry budgets (`total_retries_max`), model routing, confidence scoring, output compression, inner-loop config, test history, condensation, playbooks, and 15+ more sections. See `shared/schemas/forge-config-schema.json` for the full schema.

## Testing

```bash
# Full suite
./tests/run-all.sh

# Individual tiers
./tests/run-all.sh structural   # Plugin integrity (73 checks)
./tests/run-all.sh unit         # Shell script behavior
./tests/run-all.sh contract     # Document contract compliance
./tests/run-all.sh scenario     # Multi-script integration
```

## Benchmarks

Compression effectiveness measurements and accuracy evals. Local-only (not CI).

```bash
# Input compression: measure regex-based rule application
cd benchmarks/input-compression
./measure.sh                          # Aggressive (level 2)
./measure.sh --level 1                # Conservative
./measure.sh --level 3                # Ultra

# Output compression: 10 tasks x 5 arms via API (~$0.50)
cd benchmarks/output-compression
export ANTHROPIC_API_KEY=sk-ant-...
python3 run-benchmark.py
python3 run-benchmark.py --dry-run    # Cost estimate only

# Eval harness: 3-arm accuracy/token trade-off (~$0.50)
cd evals
python3 run-evals.py                  # Run all 10 tasks x 3 arms
python3 measure.py                    # Analyze cached results

# Token estimation (zero dependencies)
python3 benchmarks/count-tokens.py agents/fg-100-orchestrator.md
```

See `evals/README.md` for eval design, task definitions, and cost breakdown.

## Setup details

After [Quick start](#quick-start):

```bash
# Customize your project config
# Open .claude/forge.local.md and set commands, scaffolder patterns, quality gate

# Usage examples
/forge-run Add plan comment feature          # Full pipeline
/forge-run --dry-run "Add user dashboard"    # Dry-run (PREFLIGHT→VALIDATE only)
/forge-run "Add versioning" --from=implement # Resume from stage
/forge-run --playbook=add-rest-endpoint entity=Task  # Use playbook template
/forge-fix Users get 404 on group endpoint   # Bugfix workflow
/forge-sprint                                # Multi-feature parallel execution
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "No active pipeline" | Run `/forge-init` then `/forge-run` |
| Pipeline stuck | `/forge-recover diagnose` (read-only), then `/forge-recover repair` |
| Lock file blocks run | `/forge-recover reset` or remove `.forge/.lock` |
| Check engine errors | Install bash 4+ (`brew install bash`). Check `.forge/.hook-failures.jsonl` |
| Score oscillating | Check `oscillation_tolerance` in forge-config.md (default 5) |
| Budget exhausted | Check `total_retries_max` (default 10, range 5-30) |
| Evidence stale | Increase `shipping.evidence_max_age_minutes` (default 30) |
| MCP not detected | `/forge-status`. Pipeline degrades gracefully |

See `shared/error-taxonomy.md` (22 error types) and `shared/recovery/recovery-engine.md` (7 strategies).

## Adding a new module

```
modules/frameworks/{name}/
  conventions.md              # Must include Dos/Don'ts
  local-template.md           # Project config template
  forge-config-template.md    # Must include total_retries_max, oscillation_tolerance
  rules-override.json         # Check engine rule overrides
  known-deprecations.json     # Schema v2 (5-15 entries)
```

Also add `shared/learnings/{name}.md` and bump `MIN_*` in `tests/lib/module-lists.bash`.

## License

Proprietary -- QuantumBit s.r.o. See [LICENSE](LICENSE).
