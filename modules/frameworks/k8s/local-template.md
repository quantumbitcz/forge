---
project_type: infrastructure
components:
  language: ~
  framework: k8s
  variant: ~
  testing: ~
  # ci: github-actions           # github-actions | gitlab-ci | jenkins
  # container: ~                 # N/A (k8s IS the orchestrator)
  # orchestrator: argocd         # argocd | fluxcd | k3s | microk8s
  code_quality: []
  code_quality_recommended: [trivy]

explore_agents:
  primary: "feature-dev:code-explorer"
  secondary: "Explore"

commands:
  build: "helm lint charts/ || docker build ."
  lint: "kube-linter lint charts/ || hadolint Dockerfile"
  test: "helm template charts/ | kubectl apply --dry-run=client -f - || docker compose up -d && docker compose down"
  test_single: "helm template charts/ --show-only"
  format: "prettier --write '**/*.yaml' '**/*.yml'"
  build_timeout: 120
  test_timeout: 300
  lint_timeout: 60

scaffolder:
  enabled: true
  patterns:
    helm_chart: "charts/{service-name}/Chart.yaml"
    helm_values: "charts/{service-name}/values.yaml"
    helm_deployment: "charts/{service-name}/templates/deployment.yaml"
    helm_service: "charts/{service-name}/templates/service.yaml"
    helm_ingress: "charts/{service-name}/templates/ingress.yaml"
    helm_hpa: "charts/{service-name}/templates/hpa.yaml"
    helm_networkpolicy: "charts/{service-name}/templates/networkpolicy.yaml"
    helm_helpers: "charts/{service-name}/templates/_helpers.tpl"
    dockerfile: "Dockerfile"
    docker_compose: "deploy/docker-compose.yml"
    k8s_manifest: "deploy/k8s/{resource-kind}.yaml"
    migration: "migrations/V{N}__{description}.sql"

quality_gate:
  max_review_cycles: 2
  batch_1:
    - agent: fg-412-architecture-reviewer
      focus: "service boundaries, namespace structure, resource organization"
    - agent: fg-411-security-reviewer
      focus: "secrets exposure, RBAC, pod security, network policies, image provenance"
    - agent: fg-419-infra-deploy-reviewer
      focus: "deployment safety, resource limits, probes, security context"
  batch_2:
    - agent: fg-410-code-reviewer
      focus: "manifest correctness, DRY violations, configuration consistency"
    - agent: fg-417-dependency-reviewer
      condition: "dependencies_changed"
      focus: "dependency necessity, bloat, pinning, licenses"
    - agent: fg-418-docs-consistency-reviewer
      focus: "code-docs consistency, decision violations, stale documentation"
  inline_checks:
    - script: "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --verify"

test_gate:
  command: "helm template charts/ | kubectl apply --dry-run=client -f -"
  max_test_cycles: 2
  analysis_agents:
    - agent: "pr-review-toolkit:pr-test-analyzer"
      source: plugin

validation:
  perspectives: [security, resource_limits, networking, rollback_safety, conventions, approach_quality, documentation_consistency]
  max_validation_retries: 2

implementation:
  parallel_threshold: 3
  max_fix_loops: 3
  tdd: true
  scaffolder_before_impl: true

risk:
  auto_proceed: LOW

linear:
  enabled: false
  team: ""
  project: ""
  labels: ["pipeline-managed"]

conventions_file: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/k8s/conventions.md"
conventions_code_quality: "${CLAUDE_PLUGIN_ROOT}/modules/code-quality/"
conventions_code_quality_binding: "${CLAUDE_PLUGIN_ROOT}/modules/frameworks/k8s/code-quality/"
preempt_file: ".claude/forge-log.md"
config_file: ".claude/forge-config.md"

infra:
  max_verification_tier: 2
  cluster_tool: kind
  compose_file: deploy/docker-compose.yml

documentation:
  enabled: true
  output_dir: docs/
  auto_generate:
    readme: true
    architecture: true
    adrs: true
    api_docs: false
    onboarding: true
    changelogs: true
    diagrams: true
    domain_docs: true
    runbooks: true
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

context7_libraries:
  - "kubernetes"
  - "helm"
  - "docker"

graph:
  enabled: true           # set to false if Docker is unavailable
  enrich_symbols: true
  neo4j_port: 7687
  neo4j_http_port: 7474

# Git conventions (auto-detected or configured by /forge-init)
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

# Kanban tracking
tracking:
  prefix: FG
  archive_after_days: 90  # Auto-archive done/ tickets (30-365, 0=disabled)
  # enabled: true  # Set to false to disable tracking
---

## Infrastructure (K8s / Docker / Helm) Context

Kubernetes deployments via Helm charts. Docker multi-stage builds for container images.
GitOps workflow with ArgoCD or Flux. Secrets managed externally (never in values.yaml).
Local development via Docker Compose with health checks and named volumes.

Customize the commands above to match your project's chart paths and build tooling.
