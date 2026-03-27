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
    - agent: infra-deploy-reviewer
      focus: "deployment safety, resource limits, probes, security context"
  batch_2:
    - agent: "Security Engineer"
      source: builtin
      focus: "secrets exposure, RBAC, pod security, network policies, image provenance"
  inline_checks:
    - script: "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --verify"

test_gate:
  command: "helm template charts/ | kubectl apply --dry-run=client -f -"
  max_test_cycles: 2
  analysis_agents:
    - agent: "pr-review-toolkit:pr-test-analyzer"
      source: plugin

validation:
  perspectives: [security, resource_limits, networking, rollback_safety, conventions, approach_quality]
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
preempt_file: ".claude/pipeline-log.md"
config_file: ".claude/pipeline-config.md"

infra:
  max_verification_tier: 2
  cluster_tool: kind
  compose_file: deploy/docker-compose.yml

context7_libraries:
  - "kubernetes"
  - "helm"
  - "docker"
---

## Infrastructure (K8s / Docker / Helm) Context

Kubernetes deployments via Helm charts. Docker multi-stage builds for container images.
GitOps workflow with ArgoCD or Flux. Secrets managed externally (never in values.yaml).
Local development via Docker Compose with health checks and named volumes.

Customize the commands above to match your project's chart paths and build tooling.

graph:
  enabled: false          # set to true to enable Neo4j knowledge graph
  enrich_symbols: true
  neo4j_port: 7687
  neo4j_http_port: 7474
