# F24: Canary, Blue-Green, and Rolling Deployment Strategies

## Status
DRAFT — 2026-04-13 (Forward-Looking)

## Problem Statement

Forge's `/deploy` skill (`skills/deploy/SKILL.md`) is a thin command-execution wrapper: it reads deployment commands from `forge.local.md`, performs variable substitution, executes via Bash, and runs post-deploy health checks with simple retry logic. It has no understanding of deployment strategies. Specific gaps:

1. **No canary analysis:** The skill cannot incrementally shift traffic from 5% to 100%, monitor error rates during each step, or automatically roll back if metrics degrade. Teams must manually orchestrate canary progressions outside forge.
2. **No blue-green traffic management:** The skill cannot manage parallel environments, verify the standby environment is healthy, switch traffic, or provide instant rollback to the previous environment.
3. **No rolling deployment awareness:** The skill does not understand pod-by-pod replacement, maxSurge/maxUnavailable settings, or rollout status monitoring beyond a single health check.
4. **No metric-based decisions:** Post-deploy health checks are binary (pass/fail on a single endpoint). There is no comparison of canary metrics against baseline, no error rate thresholds, no latency percentile monitoring.
5. **No Argo Rollouts integration:** ArgoCD Rollouts provides native canary and blue-green strategies with metric analysis, but forge does not detect or leverage Rollouts CRDs.

The existing `fg-610-infra-deploy-verifier` validates infrastructure artifacts (Helm charts, Dockerfiles, K8s manifests) but does not monitor live deployments. The `fg-419-infra-deploy-reviewer` reviews infrastructure code but not deployment execution. There is a gap between "infrastructure is valid" and "deployment was successful."

## Proposed Solution

Extend the `/deploy` skill with strategy-aware deployment orchestration. Add strategy definitions in `modules/container-orchestration/strategies/` that codify canary, blue-green, and rolling deployment patterns. Introduce a new agent `fg-620-deploy-verifier` that monitors deployment health during strategy execution, compares metrics against baselines, and triggers automatic rollback on degradation. Integrate with Argo Rollouts when detected.

## Detailed Design

### Architecture

```
                          /deploy --strategy=canary
                                |
                                v
                    +-------------------------+
                    |     /deploy Skill       |
                    | (enhanced with strategy |
                    |    orchestration)       |
                    +-------------------------+
                         |           |
                +--------+           +--------+
                v                             v
     Strategy Definition              fg-620-deploy-verifier
     (canary.md / blue-green.md)      (metric monitoring agent)
                |                             |
     Step-based execution              Metric collection
     (5% → 25% → 50% → 100%)          + baseline comparison
                |                             |
     ArgoCD Rollouts / kubectl         Prometheus / CloudWatch /
     / Helm upgrade                    health endpoints
                |                             |
                +--------+    +--------+------+
                         |    |
                         v    v
                    Promotion / Rollback
                    decision
```

**Components:**

1. **Strategy definitions** (`modules/container-orchestration/strategies/`) — markdown convention files defining each strategy's steps, prerequisites, metric thresholds, and rollback triggers. Loaded by the deploy skill at execution time.

2. **Deploy verifier agent** (`agents/fg-620-deploy-verifier.md`) — Tier 3 agent dispatched by the deploy skill during strategy execution. Monitors deployment health by polling configured metric endpoints, comparing canary vs baseline metrics, and producing `DEPLOY-*` findings.

3. **Deploy skill enhancement** (`skills/deploy/SKILL.md`) — extended with `--strategy` flag, step-based execution, metric collection integration, and automatic rollback triggering.

4. **Argo Rollouts integration** (`modules/container-orchestration/argo-rollouts.md`) — conventions for projects using Argo Rollouts CRDs, including `AnalysisTemplate` patterns and metric provider configuration.

### Schema / Data Model

#### New Finding Categories

Added to `shared/checks/category-registry.json`:

```json
{
  "DEPLOY-HEALTH": {
    "description": "Deployment health degradation detected (error rate spike, latency increase, pod crash)",
    "agents": ["fg-620-deploy-verifier"],
    "wildcard": false,
    "priority": 1,
    "affinity": ["fg-419-infra-deploy-reviewer", "fg-620-deploy-verifier"]
  },
  "DEPLOY-CANARY": {
    "description": "Canary deployment progress or metric report",
    "agents": ["fg-620-deploy-verifier"],
    "wildcard": false,
    "priority": 5,
    "affinity": ["fg-620-deploy-verifier"]
  },
  "DEPLOY-ROLLBACK": {
    "description": "Deployment rollback triggered or recommended",
    "agents": ["fg-620-deploy-verifier"],
    "wildcard": false,
    "priority": 2,
    "affinity": ["fg-620-deploy-verifier"]
  },
  "DEPLOY-STRATEGY": {
    "description": "Deployment strategy configuration issue (missing metric endpoint, invalid step definition)",
    "agents": ["fg-610-infra-deploy-verifier"],
    "wildcard": false,
    "priority": 3,
    "affinity": ["fg-610-infra-deploy-verifier", "fg-419-infra-deploy-reviewer"]
  }
}
```

#### Deployment State Extension

New section in `state.json` during active deployment:

```json
{
  "deployment": {
    "strategy": "canary",
    "environment": "production",
    "started_at": "2026-04-13T14:00:00Z",
    "current_step": 2,
    "total_steps": 4,
    "steps": [
      { "weight": 5,   "status": "completed", "duration_s": 120, "metrics": { "error_rate_pct": 0.1, "latency_p99_ms": 180 } },
      { "weight": 25,  "status": "monitoring", "started_at": "2026-04-13T14:04:00Z" },
      { "weight": 50,  "status": "pending" },
      { "weight": 100, "status": "pending" }
    ],
    "baseline_metrics": {
      "error_rate_pct": 0.15,
      "latency_p99_ms": 200,
      "collected_at": "2026-04-13T13:55:00Z"
    },
    "rollback_triggered": false,
    "rollback_reason": null
  }
}
```

#### Strategy Definition Schema

Each strategy file defines the execution pattern. The deploy skill parses these at runtime:

**Canary (`modules/container-orchestration/strategies/canary.md`):**

Key parameters:
- `steps`: Traffic weight progression (e.g., [5, 25, 50, 100])
- `step_duration_minutes`: Minimum observation window per step (default: 2)
- `metric_endpoints`: URLs or commands to collect metrics
- `promotion_criteria`: Metric thresholds that must hold for promotion
- `rollback_criteria`: Metric thresholds that trigger automatic rollback
- `max_total_duration_minutes`: Ceiling for entire canary progression (default: 60)

**Blue-Green (`modules/container-orchestration/strategies/blue-green.md`):**

Key parameters:
- `standby_health_check`: Command or URL to verify standby environment health
- `traffic_switch_command`: Command to switch traffic from active to standby
- `rollback_command`: Command to switch traffic back
- `warm_up_duration_minutes`: Time to allow standby to warm up after deploy (default: 5)
- `metric_endpoints`: URLs or commands to collect post-switch metrics
- `observation_window_minutes`: Time to monitor after traffic switch (default: 10)

**Rolling (`modules/container-orchestration/strategies/rolling.md`):**

Key parameters:
- `max_surge`: Maximum pods above desired count during rollout (default: "25%")
- `max_unavailable`: Maximum pods unavailable during rollout (default: "25%")
- `rollout_status_command`: Command to check rollout progress (e.g., `kubectl rollout status`)
- `rollout_timeout_minutes`: Maximum time for rollout completion (default: 10)
- `metric_endpoints`: URLs or commands to collect metrics during rollout

### Configuration

In `forge.local.md` (per-project):

```yaml
deploy:
  method: argocd
  default_strategy: rolling        # canary | blue-green | rolling
  canary:
    steps: [5, 25, 50, 100]
    step_duration_minutes: 2
    metric_endpoints:
      error_rate: "curl -s http://prometheus:9090/api/v1/query?query=rate(http_requests_total{status=~'5..'}[5m])"
      latency_p99: "curl -s http://prometheus:9090/api/v1/query?query=histogram_quantile(0.99,rate(http_request_duration_seconds_bucket[5m]))"
    promotion_criteria:
      error_rate_pct: 1.0          # Must be below this to promote
      latency_p99_ms: 500          # Must be below this to promote
    rollback_criteria:
      error_rate_pct: 5.0          # Above this triggers rollback
      latency_p99_ms: 2000         # Above this triggers rollback
    argo_rollouts: true            # Use Argo Rollouts CRDs if detected
  blue_green:
    standby_health_check: "curl -sf http://standby.internal/health"
    traffic_switch_command: "kubectl patch svc main -p '{\"spec\":{\"selector\":{\"version\":\"green\"}}}'"
    rollback_command: "kubectl patch svc main -p '{\"spec\":{\"selector\":{\"version\":\"blue\"}}}'"
    warm_up_duration_minutes: 5
    observation_window_minutes: 10
  rolling:
    max_surge: "25%"
    max_unavailable: "25%"
    rollout_timeout_minutes: 10
  staging:
    command: "helm upgrade --install myapp ./charts/myapp -f values-staging.yaml"
    strategy: rolling
    post_deploy_check: "curl -sf https://staging.example.com/health"
  production:
    command: "helm upgrade --install myapp ./charts/myapp -f values-production.yaml"
    strategy: canary
    require_confirmation: true
    post_deploy_check: "curl -sf https://app.example.com/health"
  rollback:
    command: "helm rollback myapp"
```

In `forge-config.md` (plugin-wide defaults):

```yaml
deployment:
  default_strategy: rolling           # Default strategy when not specified per-environment
  canary_steps: [5, 25, 50, 100]     # Default canary weight progression
  step_duration_minutes: 2            # Default observation window per canary step
  max_total_duration_minutes: 60      # Maximum canary progression duration
  metric_threshold:
    error_rate_pct: 1.0               # Default promotion threshold
    latency_p99_ms: 500               # Default promotion threshold
  rollback_threshold:
    error_rate_pct: 5.0               # Default rollback threshold
    latency_p99_ms: 2000              # Default rollback threshold
  auto_rollback: true                 # Auto-rollback on threshold breach
  argo_rollouts_detection: true       # Auto-detect Argo Rollouts CRDs
```

| Parameter | Type | Default | Range | Description |
|---|---|---|---|---|
| `deployment.default_strategy` | string | `rolling` | `canary`, `blue-green`, `rolling` | Default deployment strategy |
| `deployment.canary_steps` | integer[] | `[5, 25, 50, 100]` | Each 1-100, ascending, last must be 100 | Traffic weight progression |
| `deployment.step_duration_minutes` | integer | `2` | 1-30 | Observation window per canary step |
| `deployment.max_total_duration_minutes` | integer | `60` | 10-180 | Maximum canary duration |
| `deployment.metric_threshold.error_rate_pct` | float | `1.0` | 0.1-10.0 | Error rate promotion threshold |
| `deployment.metric_threshold.latency_p99_ms` | integer | `500` | 50-10000 | P99 latency promotion threshold |
| `deployment.rollback_threshold.error_rate_pct` | float | `5.0` | 1.0-50.0 | Error rate rollback threshold |
| `deployment.rollback_threshold.latency_p99_ms` | integer | `2000` | 100-30000 | P99 latency rollback threshold |
| `deployment.auto_rollback` | boolean | `true` | -- | Automatically rollback on threshold breach |
| `deployment.argo_rollouts_detection` | boolean | `true` | -- | Auto-detect Argo Rollouts CRDs |

### Data Flow

#### Canary Deployment Flow

```
/deploy production --strategy=canary
  |
  1. Read deploy config, resolve strategy to "canary"
  2. Require user confirmation (production)
  3. Collect baseline metrics (pre-deploy snapshot)
  |
  4. Step 1: Deploy canary at 5% traffic weight
     |
     +-- Argo Rollouts: kubectl argo rollouts set weight myapp 5
     +-- Helm: helm upgrade with canary values (replicas proportional)
     +-- kubectl: kubectl set image + scale canary deployment
     |
     5. Dispatch fg-620-deploy-verifier
        - Monitor for step_duration_minutes (2 min default)
        - Collect canary metrics every 30s
        - Compare against baseline + thresholds
        |
        +-- Metrics within promotion_criteria → Promote to step 2
        +-- Metrics exceed rollback_criteria → Trigger rollback
        +-- Metrics between promotion and rollback → Extend observation (up to 2x step_duration)
  |
  6. Step 2: Promote canary to 25% traffic weight
     ... (same monitoring cycle)
  |
  7. Step 3: Promote canary to 50% traffic weight
     ... (same monitoring cycle)
  |
  8. Step 4: Full promotion to 100% traffic
     - Final observation window (2 min)
     - If healthy: report DEPLOY-CANARY | INFO | "Canary promotion complete"
     - If degraded: report DEPLOY-HEALTH | CRITICAL + trigger rollback
  |
  9. Post-deploy: run post_deploy_check (existing behavior)
  10. Report deployment summary with per-step metrics
```

#### Blue-Green Deployment Flow

```
/deploy production --strategy=blue-green
  |
  1. Read deploy config, resolve strategy to "blue-green"
  2. Require user confirmation (production)
  |
  3. Deploy to standby environment
     - Execute deploy command targeting standby
     - Wait for warm_up_duration_minutes
  |
  4. Verify standby health
     - Run standby_health_check
     - If unhealthy: abort without switching traffic, report DEPLOY-HEALTH | CRITICAL
  |
  5. Switch traffic
     - Execute traffic_switch_command
     - Start observation_window_minutes timer
  |
  6. Monitor post-switch
     - Dispatch fg-620-deploy-verifier
     - Collect metrics from new active environment
     - Compare against pre-switch baseline
     |
     +-- Healthy throughout observation → Report success
     +-- Degradation detected → Execute rollback_command, report DEPLOY-ROLLBACK | WARNING
  |
  7. Post-deploy: run post_deploy_check
  8. Report deployment summary
```

#### Rolling Deployment Flow

```
/deploy production --strategy=rolling
  |
  1. Read deploy config, resolve strategy to "rolling"
  2. Require user confirmation (production)
  |
  3. Execute rolling update
     - Helm: helm upgrade with maxSurge/maxUnavailable in values
     - kubectl: kubectl rollout + monitor status
  |
  4. Monitor rollout
     - Poll rollout_status_command every 15s
     - Dispatch fg-620-deploy-verifier for metric monitoring
     - Timeout after rollout_timeout_minutes
     |
     +-- Rollout complete + healthy → Report success
     +-- Rollout stalled → Report DEPLOY-HEALTH | WARNING
     +-- Metric degradation → kubectl rollout undo + report DEPLOY-ROLLBACK
  |
  5. Post-deploy: run post_deploy_check
  6. Report deployment summary
```

#### Argo Rollouts Detection

At PREFLIGHT, if `argo_rollouts_detection: true`:

1. Check for Argo Rollouts CRDs: `kubectl get crd rollouts.argoproj.io 2>/dev/null`
2. If present: set `state.json.integrations.argo_rollouts.available = true`
3. When deploying with canary/blue-green strategy and Argo Rollouts available:
   - Use `kubectl argo rollouts` commands instead of manual traffic management
   - Parse `AnalysisTemplate` CRDs for metric provider configuration
   - Leverage Argo Rollouts' built-in analysis for metric-based promotion

### Integration Points

| Agent / System | Integration | Change Required |
|---|---|---|
| `/deploy` skill | Add `--strategy` flag. Implement step-based canary, blue-green, and rolling execution. Add metric collection and rollback logic. | Major enhancement to `skills/deploy/SKILL.md`. |
| `fg-620-deploy-verifier` (NEW) | Dispatched by deploy skill during strategy execution. Monitors metrics, compares against baseline, produces `DEPLOY-*` findings. | New agent file. |
| `fg-610-infra-deploy-verifier` | Validate strategy configuration (valid steps, reachable metric endpoints, valid Argo Rollouts config). New `DEPLOY-STRATEGY` findings. | Add strategy validation to existing infra verification tiers. |
| `fg-419-infra-deploy-reviewer` | Review deployment strategy configuration in code review. | Add strategy-specific review checks. |
| `modules/container-orchestration/` | Add `strategies/` subdirectory with canary, blue-green, rolling convention files. Add `argo-rollouts.md` conventions. | New files in existing module. |
| `shared/checks/category-registry.json` | Add `DEPLOY-HEALTH`, `DEPLOY-CANARY`, `DEPLOY-ROLLBACK`, `DEPLOY-STRATEGY` categories. | Registry update. |
| `state-schema.md` | Add `deployment` section to state schema for tracking strategy execution. | Schema extension. |
| `shared/agent-registry.md` | Register `fg-620-deploy-verifier`. | Registry update. |

### Error Handling

| Failure Mode | Behavior | Degradation |
|---|---|---|
| Metric endpoint unreachable | Log WARNING. Continue with health check only (existing post_deploy_check). Skip metric-based promotion/rollback. | Reduced to health-check-only strategy. |
| Metric endpoint returns unexpected format | Log WARNING. Skip that metric. If all metrics unreadable, fall back to health check only. | Same as unreachable. |
| Canary step timeout (observation window exceeded with no clear signal) | Extend observation by 1x step_duration. If still ambiguous after extension, escalate to user: "Metrics are inconclusive. Promote, rollback, or extend?" | User decision required. |
| Rollback command fails | Log CRITICAL: "Rollback failed. Manual intervention required." Display rollback command for manual execution. | Manual recovery required. |
| Argo Rollouts CRD not found | Fall back to manual traffic management (kubectl/helm). Log INFO. | Slightly less automated, same outcome. |
| kubectl/helm CLI not installed | Log CRITICAL: "Required CLI not found. Cannot execute strategy." Abort deployment. | Cannot deploy. |
| Baseline metric collection fails | Log WARNING: "No baseline metrics. Promotion/rollback will use absolute thresholds only." | Absolute thresholds instead of relative comparison. |
| Deploy skill invoked without strategy config | Use `default_strategy` from config. If unconfigured, use `rolling` (safest default). | Automatic fallback to simplest strategy. |
| Max total duration exceeded (canary) | Escalate to user: "Canary duration exceeded {max_total_duration_minutes}m. Current step: {N}. Promote all, rollback, or extend?" | User decision required. |

## Performance Characteristics

### Deployment Duration

| Strategy | Typical Duration | Variables |
|---|---|---|
| Rolling | 2-10 minutes | Pod count, image pull time, readiness probe delay |
| Canary (4 steps, 2min each) | 8-15 minutes | Step count, observation windows, metric collection overhead |
| Canary (4 steps, extended) | 15-60 minutes | If steps extend due to ambiguous metrics |
| Blue-Green | 5-15 minutes | Warm-up time, observation window |

### Metric Collection Overhead

| Metric Source | Collection Latency | Notes |
|---|---|---|
| Prometheus API | 100-500ms | Single PromQL query |
| CloudWatch API | 500-2000ms | AWS API latency |
| Health endpoint | 50-200ms | Simple HTTP GET |
| Argo Rollouts status | 100-500ms | kubectl command |

Metric collection runs every 30 seconds during canary steps. Total overhead per step: 4 queries x 4 intervals = 16 metric collections at ~500ms each = ~8s overhead per 2-minute step. Negligible.

### Token Impact

The deploy verifier agent (fg-620) runs during deployment, not during the standard pipeline. Token usage is isolated from the PREFLIGHT-through-LEARNING pipeline budget. Expected: 1,000-3,000 tokens per deployment depending on strategy complexity and number of steps.

## Testing Approach

### Structural Tests

1. **Strategy files exist:** `modules/container-orchestration/strategies/` contains `canary.md`, `blue-green.md`, `rolling.md`
2. **Agent registration:** `fg-620-deploy-verifier` exists in `agents/` and is registered in `shared/agent-registry.md`
3. **Category codes:** `DEPLOY-HEALTH`, `DEPLOY-CANARY`, `DEPLOY-ROLLBACK`, `DEPLOY-STRATEGY` in `category-registry.json`

### Unit Tests (`tests/unit/deployment-strategies.bats`)

1. **Canary step progression:** Mock metric endpoints returning healthy values. Verify 4-step canary completes with all steps promoted.
2. **Canary rollback:** Mock metric endpoints returning degraded values at step 2. Verify rollback is triggered.
3. **Blue-green switch:** Mock standby health check. Verify traffic switch command executes after warm-up.
4. **Blue-green rollback:** Mock post-switch metrics showing degradation. Verify rollback command executes.
5. **Rolling timeout:** Mock stalled rollout status. Verify timeout triggers WARNING finding.
6. **Metric parsing:** Test parsing of Prometheus API response, CloudWatch response, and simple JSON health check.
7. **Config validation:** Verify canary_steps must be ascending with last = 100. Verify threshold ranges.

### Integration Tests

1. **Dry-run canary:** `/deploy production --strategy=canary --dry-run`. Verify step plan is displayed without execution.
2. **Argo Rollouts detection:** Mock `kubectl get crd` response. Verify detection and Argo-specific command generation.
3. **Strategy fallback:** Configure canary with unreachable metrics. Verify fallback to health-check-only.

### Scenario Tests

1. **Full canary with metrics:** Mock Prometheus returning gradually increasing error rate. Verify rollback triggers when rate exceeds threshold at step 3.
2. **Successful blue-green:** Mock healthy standby, successful traffic switch, healthy post-switch metrics. Verify complete flow.

## Acceptance Criteria

1. `/deploy staging --strategy=canary` executes a step-based canary deployment with metric monitoring
2. `/deploy production --strategy=blue-green` deploys to standby, verifies health, switches traffic, monitors post-switch
3. `/deploy production --strategy=rolling` monitors rollout progress with metric-based rollback
4. Canary steps promote only when metrics are within `promotion_criteria` thresholds
5. Automatic rollback triggers when metrics exceed `rollback_criteria` thresholds
6. `DEPLOY-HEALTH`, `DEPLOY-CANARY`, `DEPLOY-ROLLBACK` findings are produced by fg-620-deploy-verifier
7. Argo Rollouts CRDs are auto-detected and used when available
8. Existing `/deploy` behavior (simple command execution) is unchanged when `--strategy` is not specified
9. `./tests/validate-plugin.sh` passes with new agent and strategy files
10. Metric collection does not block deployment — if metrics are unreachable, the deployment degrades to health-check-only
11. User confirmation is still required for production deployments regardless of strategy

## Migration Path

1. **v2.0.0:** Ship strategy definitions and enhanced `/deploy` skill. Default strategy remains `rolling` (least disruptive).
2. **v2.0.0:** Ship `fg-620-deploy-verifier` agent. Conditional on strategy being explicitly selected.
3. **v2.0.0:** Add `deployment:` section to `forge-config-template.md` for k8s and compose frameworks.
4. **v2.0.0:** Add `argo-rollouts.md` to `modules/container-orchestration/`.
5. **v2.1.0 (future):** Add Flagger integration as an alternative to Argo Rollouts.
6. **v2.1.0 (future):** Add deployment analytics to `/forge-insights` (success rate, avg canary duration, rollback frequency).
7. **No breaking changes:** Existing `/deploy` users without `--strategy` flag see identical behavior. Strategy is strictly opt-in.

## Dependencies

**Depends on:**
- `/deploy` skill (`skills/deploy/SKILL.md`) — base deployment execution (extended, not replaced)
- `fg-610-infra-deploy-verifier` — strategy configuration validation at PREFLIGHT
- `modules/container-orchestration/` — module directory for strategy definitions
- kubectl / helm / argocd CLI — required for strategy execution (detected at PREFLIGHT, graceful degradation)

**Depended on by:**
- F23 (Feature Flag Management): canary deployments can coordinate with feature flags for progressive rollouts
