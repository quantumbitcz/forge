# Framework Local-Template Base Reference

> **This is NOT loaded at runtime.** It is a reference document for contributors creating or
> auditing framework `local-template.md` files. Frameworks copy-paste from this base and
> override their specific sections. Drift from this base is detectable by diffing.

## How to use this file

1. **New framework:** Copy the YAML frontmatter skeleton below into
   `modules/frameworks/{name}/local-template.md`. Fill in every `# OVERRIDE` section.
   Leave all `# SHARED DEFAULT` sections verbatim.
2. **Auditing existing frameworks:** Diff any framework's `local-template.md` against
   the `# SHARED DEFAULT` sections here. Any difference in a shared section is drift
   that should be corrected (or promoted to an intentional override with a comment).
3. **Changing a shared default:** Update this file first, then propagate to all 21
   framework templates. Run `./tests/run-all.sh structural` to verify.

## Section classification

| Marker | Meaning | Rule |
|--------|---------|------|
| `# OVERRIDE: required` | Framework MUST provide its own values | Empty/placeholder = broken template |
| `# OVERRIDE: optional` | Framework MAY override; base value is a sensible default | Omitting uses base value |
| `# SHARED DEFAULT` | Identical across ALL frameworks | Changing per-framework = drift bug |

---

## Template skeleton

```yaml
---
# OVERRIDE: required -- one of: backend, frontend, fullstack, infrastructure
project_type: <backend|frontend|fullstack|infrastructure>

# OVERRIDE: required -- framework-specific stack definition
components:
  language: <lang>               # e.g., kotlin, typescript, python, go, rust, swift, ~
  framework: <framework-name>    # must match directory name
  variant: <variant>             # usually matches language; ~ for infra
  testing: <test-framework>      # e.g., kotest, vitest, pytest, go-testing, ~
  # persistence: <orm>           # optional: hibernate, prisma, sqlalchemy, gorm, etc.
  # web: <stack>                 # optional (spring only): mvc | webflux
  # build_system: <tool>         # optional: gradle | maven | npm | cargo | go | uv
  # ci: github-actions           # optional: github-actions | gitlab-ci | jenkins | etc.
  # container: docker            # optional: docker | docker-compose | podman
  # orchestrator: helm           # optional: helm | argocd | fluxcd | etc.
  code_quality: []
  code_quality_recommended: [<framework-appropriate tools>]  # OVERRIDE: required

# ---------------------------------------------------------------------------
# SHARED DEFAULT -- explore_agents
# Identical across all 21 frameworks. Do NOT change per-framework.
# ---------------------------------------------------------------------------
explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

# ---------------------------------------------------------------------------
# OVERRIDE: required -- commands
# Every value is framework-specific. Timeout values are shared defaults.
# ---------------------------------------------------------------------------
commands:
  build: "<framework build command>"       # OVERRIDE: required
  lint: "<framework lint command>"         # OVERRIDE: required
  test: "<framework test command>"         # OVERRIDE: required
  test_single: "<single test command>"     # OVERRIDE: required
  format: "<framework format command>"     # OVERRIDE: required
  # build_alt: "<alt build>"              # OVERRIDE: optional (e.g., fastapi)
  # test_alt: "<alt test>"               # OVERRIDE: optional
  # lint_alt: "<alt lint>"               # OVERRIDE: optional
  build_timeout: 120                       # SHARED DEFAULT (nextjs/vue may use 180)
  test_timeout: 300                        # SHARED DEFAULT
  lint_timeout: 60                         # SHARED DEFAULT

# ---------------------------------------------------------------------------
# OVERRIDE: required -- scaffolder
# enabled is always true (shared). patterns are fully framework-specific.
# ---------------------------------------------------------------------------
scaffolder:
  enabled: true                            # SHARED DEFAULT
  patterns:                                # OVERRIDE: required (all patterns)
    # Example (backend):
    #   handler: "src/handler/{area}.rs"
    #   service: "src/service/{area}.rs"
    #   test: "tests/{area}_test.rs"
    # Example (frontend):
    #   component: "src/app/components/{feature}/{Name}.tsx"
    #   test: "src/tests/{feature}/{Name}.test.tsx"

# ---------------------------------------------------------------------------
# OVERRIDE: required -- quality_gate
# max_review_cycles is shared. Batches are fully framework-specific.
# Backend templates typically use 2 batches; frontend templates use 3 batches.
# ---------------------------------------------------------------------------
quality_gate:
  max_review_cycles: 2                     # SHARED DEFAULT
  # --- Backend pattern (2 batches) ---
  # batch_1:
  #   - agent: fg-410-code-reviewer
  #     focus: "<framework-specific arch focus>"
  #   - agent: fg-411-security-reviewer
  #     focus: "<framework-specific security focus>"
  #   - agent: fg-416-performance-reviewer
  #     focus: "N+1 queries, blocking I/O, algorithm complexity, DB efficiency"
  # batch_2:
  #   - agent: fg-410-code-reviewer
  #     focus: "general correctness, maintainability"
  #   - agent: "pr-review-toolkit:code-reviewer"
  #     source: plugin
  #     focus: "CLAUDE.md adherence"
  #   - agent: fg-418-docs-consistency-reviewer
  #     focus: "code-docs consistency, decision violations, stale documentation"
  #
  # --- Frontend pattern (3 batches) ---
  # batch_1:
  #   - agent: fg-413-frontend-reviewer
  #   - agent: fg-411-security-reviewer
  #     focus: "<framework-specific security focus>"
  #   - agent: fg-413-frontend-reviewer
  #     mode: a11y-only
  #     focus: "WCAG 2.2 AA deep audit, color contrast, ARIA tree, touch targets"
  #   - agent: fg-410-code-reviewer
  #     focus: "general correctness, maintainability"
  #   - agent: "pr-review-toolkit:code-reviewer"
  #     source: plugin
  #     focus: "CLAUDE.md adherence"
  # batch_2:
  #   - agent: "Security Engineer"
  #     source: builtin
  #     focus: "<framework-specific security focus>"
  #   - agent: "Accessibility Auditor"
  #     source: builtin
  #     focus: "WCAG 2.2 AA, keyboard nav, screen reader"
  #   - agent: "pr-review-toolkit:silent-failure-hunter"
  #     source: plugin
  #     focus: "<framework-specific silent failure focus>"
  # batch_3:
  #   - agent: "pr-review-toolkit:code-simplifier"
  #     source: plugin
  #     focus: "<framework-specific simplification focus>"
  #   - agent: "pr-review-toolkit:type-design-analyzer"
  #     source: plugin
  #     focus: "<framework-specific type design focus>"
  #   - agent: fg-418-docs-consistency-reviewer
  #     focus: "code-docs consistency, decision violations, stale documentation"
  #
  # --- Required for all templates (shared) ---
  inline_checks:                           # SHARED DEFAULT (some backends omit this -- drift)
    - script: "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --verify"

# ---------------------------------------------------------------------------
# OVERRIDE: required -- test_gate
# command is framework-specific. max_test_cycles and analysis_agents are shared.
# Frontend templates add codebase-audit-suite:ln-634-test-coverage-auditor.
# ---------------------------------------------------------------------------
test_gate:
  command: "<framework test command>"      # OVERRIDE: required (must match commands.test)
  max_test_cycles: 2                       # SHARED DEFAULT
  analysis_agents:                         # SHARED DEFAULT (base set)
    - agent: "pr-review-toolkit:pr-test-analyzer"
      source: plugin
    # Frontend templates add:
    # - agent: "codebase-audit-suite:ln-634-test-coverage-auditor"
    #   source: plugin

# ---------------------------------------------------------------------------
# SHARED DEFAULT -- validation
# Identical across all standard frameworks (backend + frontend).
# k8s overrides perspectives for infra-specific concerns.
# ---------------------------------------------------------------------------
validation:
  perspectives: [architecture, security, edge_cases, test_strategy, conventions, approach_quality, documentation_consistency]
  max_validation_retries: 2

# ---------------------------------------------------------------------------
# SHARED DEFAULT -- implementation
# Identical across ALL 21 frameworks. Do NOT change per-framework.
# ---------------------------------------------------------------------------
implementation:
  parallel_threshold: 3
  max_fix_loops: 3
  tdd: true
  scaffolder_before_impl: true

# ---------------------------------------------------------------------------
# OVERRIDE: optional -- frontend_polish
# Include ONLY for frontend/fullstack templates. Omit entirely for backend/infra.
# Values below are the shared defaults when present.
# ---------------------------------------------------------------------------
# frontend_polish:
#   enabled: true
#   aesthetic_direction: ""   # optional: "brutalist", "editorial", "luxury", "playful", etc.
#   viewport_targets: [375, 768, 1280]

# ---------------------------------------------------------------------------
# SHARED DEFAULT -- risk
# Most frameworks use MEDIUM. k8s uses LOW. Override only with justification.
# ---------------------------------------------------------------------------
risk:
  auto_proceed: MEDIUM

# ---------------------------------------------------------------------------
# SHARED DEFAULT -- linear
# Identical across ALL 21 frameworks. Do NOT change per-framework.
# ---------------------------------------------------------------------------
linear:
  enabled: false
  team: ""
  project: ""
  labels: ["pipeline-managed"]

# ---------------------------------------------------------------------------
# OVERRIDE: required -- conventions file paths
# Pattern is fixed; only the framework directory name changes.
# Not all frameworks have all convention files (variant, testing, persistence,
# web). Include only those that exist for the framework.
# ---------------------------------------------------------------------------
conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/<FRAMEWORK>/conventions.md"
# conventions_variant: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/<FRAMEWORK>/variants/${components.variant}.md"
# conventions_testing: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/<FRAMEWORK>/testing/${components.testing}.md"
# conventions_web: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/<FRAMEWORK>/web/${components.web}.md"
# conventions_persistence: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/<FRAMEWORK>/persistence/${components.persistence}.md"
conventions_code_quality: "${CLAUDE_PLUGIN_ROOT}/modules/code-quality/"
conventions_code_quality_binding: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/<FRAMEWORK>/code-quality/"
# language_file: "${CLAUDE_PLUGIN_ROOT}/modules/languages/${components.language}.md"   # omit for k8s (language: ~)
preempt_file: ".claude/forge-log.md"       # SHARED DEFAULT
config_file: ".claude/forge-admin config.md"     # SHARED DEFAULT

# ---------------------------------------------------------------------------
# OVERRIDE: optional -- infra (k8s and infra-focused frameworks only)
# ---------------------------------------------------------------------------
# infra:
#   max_verification_tier: 2
#   cluster_tool: kind
#   compose_file: deploy/docker-compose.yml

# ---------------------------------------------------------------------------
# SHARED DEFAULT -- documentation
# Structure is identical across all frameworks. Two fields vary:
#   api_docs: true  (backend/fullstack with API) or false (frontend-only/infra)
#   runbooks: true  (k8s/infra) or false (all others)
# All other values are shared defaults.
# ---------------------------------------------------------------------------
documentation:
  enabled: true
  output_dir: docs/
  auto_generate:
    readme: true
    architecture: true
    adrs: true
    api_docs: true                         # OVERRIDE: optional (false for frontend-only)
    onboarding: true
    changelogs: true
    diagrams: true
    domain_docs: true
    runbooks: false                        # OVERRIDE: optional (true for k8s/infra)
    user_guides: false
    migration_guides: true
  discovery:
    max_files: 500
    max_file_size_kb: 512
    exclude_patterns: []
  external_sources: []
  export:
    confluence:
      enabled: false
    notion:
      enabled: false
  user_maintained_marker: "<!-- user-maintained -->"

# ---------------------------------------------------------------------------
# OVERRIDE: required -- context7_libraries
# Fully framework-specific. List the primary libraries for the framework.
# ---------------------------------------------------------------------------
context7_libraries:
  - "<primary-framework-lib>"
  # - "<additional-libs>"

# ---------------------------------------------------------------------------
# SHARED DEFAULT -- graph
# Identical across ALL 21 frameworks. Do NOT change per-framework.
# ---------------------------------------------------------------------------
graph:
  enabled: true           # set to false if Docker is unavailable
  enrich_symbols: true
  neo4j_port: 7687
  neo4j_http_port: 7474

# ---------------------------------------------------------------------------
# SHARED DEFAULT -- git
# Identical across ALL 21 frameworks. Do NOT change per-framework.
# ---------------------------------------------------------------------------
# Git conventions (auto-detected or configured by /forge)
git:
  branch_template: "{type}/{ticket}-{slug}"
  branch_types: [feat, fix, refactor, chore]
  slug_max_length: 40
  ticket_source: auto
  commit_format: conventional
  commit_types: [feat, fix, test, refactor, docs, chore, perf, ci]
  commit_scopes: auto
  max_subject_length: 72
  require_scope: false
  sign_commits: false
  # commit_enforcement: external  # Uncomment if project has its own hooks

# ---------------------------------------------------------------------------
# SHARED DEFAULT -- tracking
# Identical across ALL 21 frameworks. Do NOT change per-framework.
# ---------------------------------------------------------------------------
# Kanban tracking
tracking:
  prefix: FG
  archive_after_days: 90  # Auto-archive done/ tickets (30-365, 0=disabled)
  # enabled: true  # Set to false to disable tracking
---
```

## Post-frontmatter context section

After the closing `---`, every template includes a brief markdown section describing
the framework context. This is framework-specific.

```markdown
## <Framework> <Type> Context

<2-4 sentences describing architecture, key patterns, and primary conventions.>

Customize the commands above to match your project's <relevant tooling>.
```

---

## Shared defaults summary (must NOT change per-framework)

These sections are byte-identical across all 21 frameworks. Any difference is drift.

| Section | Canonical value |
|---------|----------------|
| `explore_agents` | `primary: "feature-dev:code-explorer"`, `secondary: "Explore"` |
| `scaffolder.enabled` | `true` |
| `quality_gate.max_review_cycles` | `2` |
| `quality_gate.inline_checks` | `engine.sh --verify` |
| `test_gate.max_test_cycles` | `2` |
| `test_gate.analysis_agents[0]` | `pr-review-toolkit:pr-test-analyzer` |
| `validation.perspectives` | `[architecture, security, edge_cases, test_strategy, conventions, approach_quality, documentation_consistency]` |
| `validation.max_validation_retries` | `2` |
| `implementation` | `parallel_threshold: 3, max_fix_loops: 3, tdd: true, scaffolder_before_impl: true` |
| `risk.auto_proceed` | `MEDIUM` (except k8s: `LOW`) |
| `linear` | `enabled: false, team: "", project: "", labels: ["pipeline-managed"]` |
| `preempt_file` | `.claude/forge-log.md` |
| `config_file` | `.claude/forge-admin config.md` |
| `conventions_code_quality` | `${CLAUDE_PLUGIN_ROOT}/modules/code-quality/` |
| `documentation.discovery` | `max_files: 500, max_file_size_kb: 512, exclude_patterns: []` |
| `documentation.export` | confluence + notion both disabled |
| `documentation.user_maintained_marker` | `<!-- user-maintained -->` |
| `graph` | `enabled: true, enrich_symbols: true, neo4j_port: 7687, neo4j_http_port: 7474` |
| `git` | Full block (branch_template through sign_commits) |
| `tracking` | `prefix: FG, archive_after_days: 90` |
| `commands.build_timeout` | `120` (nextjs/vue override to `180`) |
| `commands.test_timeout` | `300` |
| `commands.lint_timeout` | `60` |

## Framework-specific overrides summary (must be customized)

| Section | What varies | Backend pattern | Frontend pattern | Infra pattern |
|---------|-------------|-----------------|------------------|---------------|
| `project_type` | type | `backend` | `frontend` | `infrastructure` |
| `components` | full block | lang + testing + persistence | lang + testing | `language: ~`, `testing: ~` |
| `commands.*` (non-timeout) | all 5 commands | build tool specific | package manager specific | helm/kubectl specific |
| `scaffolder.patterns` | all patterns | domain layers | component/page patterns | chart/manifest patterns |
| `quality_gate.batch_*` | all batches | 2 batches (arch+sec+perf, quality+docs) | 3 batches (+design+a11y+type) | 2 batches (infra+sec+docs) |
| `test_gate.command` | test command | matches `commands.test` | matches `commands.test` | dry-run validation |
| `test_gate.analysis_agents` | extra agents | base only | +coverage auditor | base only |
| `frontend_polish` | presence | absent | present | absent |
| `infra` | presence | absent | absent | present |
| `conventions_*` | file paths | framework dir | framework dir | framework dir (fewer files) |
| `documentation.api_docs` | boolean | `true` | `false` | `false` |
| `documentation.runbooks` | boolean | `false` | `false` | `true` |
| `context7_libraries` | full list | framework libs | framework libs | k8s/helm/docker |
| `validation.perspectives` | perspectives | standard 7 | standard 7 | infra-specific (k8s only) |
| `risk.auto_proceed` | level | `MEDIUM` | `MEDIUM` | `LOW` |

## Known intentional deviations from shared defaults

These are documented exceptions, not drift:

- **k8s**: `validation.perspectives` uses infra-specific set `[security, resource_limits, networking, rollback_safety, conventions, approach_quality, documentation_consistency]`
- **k8s**: `risk.auto_proceed: LOW` (infrastructure changes are higher risk)
- **k8s**: No `language_file`, `conventions_variant`, `conventions_testing` (language is null)
- **k8s**: Adds `infra:` section (unique to infrastructure templates)
- **nextjs, vue**: `commands.build_timeout: 180` (SSR builds are slower)
- **Frontend templates**: Extra `analysis_agents` entry in `test_gate` (coverage auditor)
- **Frontend templates**: Include `frontend_polish` section
