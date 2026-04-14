# Deployment Strategies

Strategy-aware deployment orchestration for the `/forge-deploy` skill. Extends simple command execution with metric-based canary progression, blue-green traffic switching, and rolling update monitoring.

## Strategy Selection

When `/forge-deploy` is invoked, the strategy is resolved in this order:

1. Explicit `--strategy=<name>` flag on the command
2. Per-environment `strategy` in `forge.local.md` (e.g., `production.strategy: canary`)
3. `deployment.default_strategy` in `forge-config.md`
4. Hardcoded fallback: `rolling`

Supported strategies: `canary`, `blue-green`, `rolling`.

When no `--strategy` flag is provided and no strategy is configured, the deploy skill executes the raw deploy command as before (backward compatible).

## Strategy Definitions

Strategy convention files live in `modules/container-orchestration/strategies/`:

| File | Strategy | Key Behavior |
|------|----------|-------------|
| `canary.md` | Canary | Step-based traffic shift (5% -> 25% -> 50% -> 100%), metric-based promotion, auto-rollback |
| `blue-green.md` | Blue-Green | Parallel environment, standby health check, traffic switch, instant rollback |
| `rolling.md` | Rolling | Pod-by-pod replacement, surge/unavailability settings, rollout status monitoring |

## Metric Monitoring

All strategies support metric monitoring via configurable endpoints. The deploy verifier agent (`fg-620-deploy-verifier`) is dispatched during strategy execution to:

1. **Collect baseline metrics** before deployment begins
2. **Monitor metrics** during deployment at 30-second intervals
3. **Compare against thresholds** for promotion/rollback decisions
4. **Produce findings** (`DEPLOY-HEALTH`, `DEPLOY-CANARY`, `DEPLOY-ROLLBACK`)

### Metric Endpoints

Configured in `forge.local.md` under the strategy section:

```yaml
deploy:
  canary:
    metric_endpoints:
      error_rate: "curl -s http://prometheus:9090/api/v1/query?query=..."
      latency_p99: "curl -s http://prometheus:9090/api/v1/query?query=..."
```

Supported sources: Prometheus API, CloudWatch API, health endpoints, custom scripts returning numeric values.

### Thresholds

Two threshold levels control automated decisions:

| Level | Purpose | Default Error Rate | Default Latency P99 |
|-------|---------|-------------------|---------------------|
| `metric_threshold` | Promotion criteria (must be below) | 1.0% | 500ms |
| `rollback_threshold` | Rollback trigger (above = immediate rollback) | 5.0% | 2000ms |

Metrics between promotion and rollback thresholds extend the observation window by 1x. If still ambiguous after extension, the decision escalates to the user.

## Rollback Triggers

Automatic rollback is triggered when:

| Condition | Strategy | Action |
|-----------|----------|--------|
| Metric exceeds rollback threshold | All | Immediate rollback |
| Rollout stalls (no progress) | Rolling | `kubectl rollout undo` |
| Standby health check fails | Blue-Green | Abort without switching traffic |
| Pod crash loops detected | Rolling, Canary | Rollback to stable version |
| Max total duration exceeded | Canary | Escalate to user |

Rollback is automatic when `deployment.auto_rollback: true` (default). When disabled, the deploy skill escalates to the user instead.

## Argo Rollouts Integration

When `deployment.argo_rollouts_detection: true` (default) and Argo Rollouts CRDs are detected at PREFLIGHT:

1. Canary and blue-green strategies use `kubectl argo rollouts` commands
2. `AnalysisTemplate` CRDs are parsed for metric provider configuration
3. Built-in Argo analysis replaces custom metric collection where available
4. `state.json.integrations.argo_rollouts.available` is set to `true`

Detection: `kubectl get crd rollouts.argoproj.io 2>/dev/null`

When Argo Rollouts is not available, strategies fall back to manual traffic management via kubectl, Helm, or ingress annotations.

## Configuration Reference

### forge-config.md (plugin-wide defaults)

```yaml
deployment:
  default_strategy: rolling
  canary_steps: [5, 25, 50, 100]
  metric_threshold:
    error_rate_pct: 1
    latency_p99_ms: 500
```

### forge.local.md (per-project)

```yaml
deploy:
  default_strategy: canary
  canary:
    steps: [5, 25, 50, 100]
    step_duration_minutes: 2
    metric_endpoints:
      error_rate: "curl -s ..."
      latency_p99: "curl -s ..."
    promotion_criteria:
      error_rate_pct: 1.0
      latency_p99_ms: 500
    rollback_criteria:
      error_rate_pct: 5.0
      latency_p99_ms: 2000
  staging:
    command: "helm upgrade ..."
    strategy: rolling
  production:
    command: "helm upgrade ..."
    strategy: canary
    require_confirmation: true
```

## Finding Categories

| Category | Severity | Description |
|----------|----------|-------------|
| `DEPLOY-HEALTH` | CRITICAL | Deployment health degradation (error rate spike, latency increase, pod crash) |
| `DEPLOY-CANARY` | INFO | Canary deployment progress or metric report |
| `DEPLOY-ROLLBACK` | WARNING | Deployment rollback triggered or recommended |
| `DEPLOY-STRATEGY` | WARNING | Strategy configuration issue (missing metric endpoint, invalid step definition) |

## Error Handling

| Failure Mode | Behavior |
|-------------|----------|
| Metric endpoint unreachable | WARNING, fallback to health-check-only |
| Rollback command fails | CRITICAL, manual intervention required |
| Argo Rollouts CRD not found | INFO, fallback to manual traffic management |
| kubectl/helm CLI missing | CRITICAL, abort deployment |
| Baseline collection fails | WARNING, absolute thresholds only |
| Max duration exceeded (canary) | Escalate to user |

## Deployment State

During active deployment, `state.json` includes:

```json
{
  "deployment": {
    "strategy": "canary",
    "environment": "production",
    "started_at": "2026-04-13T14:00:00Z",
    "current_step": 2,
    "total_steps": 4,
    "baseline_metrics": {
      "error_rate_pct": 0.15,
      "latency_p99_ms": 200
    },
    "rollback_triggered": false,
    "rollback_reason": null
  }
}
```

## Agent Interaction

| Agent | Role |
|-------|------|
| `/forge-deploy` skill | Orchestrates strategy execution, dispatches fg-620 |
| `fg-620-deploy-verifier` | Monitors metrics, produces findings |
| `fg-610-infra-deploy-verifier` | Validates strategy configuration at PREFLIGHT |
| `fg-419-infra-deploy-reviewer` | Reviews strategy configuration in code review |
