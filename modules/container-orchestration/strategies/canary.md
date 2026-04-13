# Canary Deployment Strategy

## Overview

Incremental traffic shifting from a small percentage to full deployment, with metric-based promotion and automatic rollback. The canary receives a fraction of production traffic while the stable version handles the rest. At each step, metrics are compared against baseline and promotion thresholds to decide whether to advance, hold, or rollback.

- **Use for:** production deployments requiring confidence that the new version does not degrade error rates, latency, or resource utilization before full rollout
- **Avoid for:** stateful services where traffic splitting is not feasible, environments without metric collection, simple staging/dev deployments where rolling is sufficient
- **Key differentiators:** metric-driven promotion at each step, automatic rollback on threshold breach, Argo Rollouts integration for native canary CRDs

## Architecture Patterns

### Step-Based Progression

Canary deployments progress through a series of weight steps. Each step shifts a percentage of traffic to the canary and holds for an observation window:

```
Step 1:  5% traffic  -> observe 2 min -> promote if healthy
Step 2: 25% traffic  -> observe 2 min -> promote if healthy
Step 3: 50% traffic  -> observe 2 min -> promote if healthy
Step 4: 100% traffic -> observe 2 min -> finalize
```

Default steps: `[5, 25, 50, 100]`. Configurable via `deployment.canary_steps`.

### Traffic Splitting Methods

| Method | Tool | How |
|--------|------|-----|
| Argo Rollouts | `kubectl argo rollouts set weight` | Native CRD-based traffic splitting via service mesh or ingress |
| Istio VirtualService | `kubectl patch virtualservice` | Weight-based routing rules |
| Nginx Ingress | Canary annotations on Ingress | `nginx.ingress.kubernetes.io/canary-weight` |
| Helm replicas | `helm upgrade` with proportional replica counts | Approximate traffic split by pod ratio |

Argo Rollouts is preferred when detected. Otherwise, fall back to ingress annotations or replica-based splitting.

### Metric Collection

During each observation window, metrics are collected every 30 seconds from configured endpoints:

```yaml
metric_endpoints:
  error_rate: "curl -s http://prometheus:9090/api/v1/query?query=rate(http_requests_total{status=~'5..'}[5m])"
  latency_p99: "curl -s http://prometheus:9090/api/v1/query?query=histogram_quantile(0.99,rate(http_request_duration_seconds_bucket[5m]))"
```

Supported metric sources: Prometheus API, CloudWatch API, health endpoints, custom scripts.

### Promotion Decision

At the end of each observation window:

| Condition | Action |
|-----------|--------|
| All metrics within `promotion_criteria` | Promote to next step |
| Any metric exceeds `rollback_criteria` | Trigger rollback immediately |
| Metrics between promotion and rollback thresholds | Extend observation by 1x `step_duration_minutes` |
| Extended observation still ambiguous | Escalate to user: promote, rollback, or extend |

### Rollback

Rollback returns all traffic to the stable version:

- **Argo Rollouts:** `kubectl argo rollouts abort <rollout>`
- **Helm:** `helm rollback <release>`
- **kubectl:** scale canary deployment to 0, verify stable deployment healthy

Rollback is automatic when `deployment.auto_rollback: true` (default).

## Configuration

```yaml
deployment:
  default_strategy: canary
  canary_steps: [5, 25, 50, 100]
  step_duration_minutes: 2
  max_total_duration_minutes: 60
  metric_threshold:
    error_rate_pct: 1.0
    latency_p99_ms: 500
  rollback_threshold:
    error_rate_pct: 5.0
    latency_p99_ms: 2000
  auto_rollback: true
  argo_rollouts_detection: true
```

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `canary_steps` | `[5, 25, 50, 100]` | Each 1-100, ascending, last must be 100 | Traffic weight progression |
| `step_duration_minutes` | 2 | 1-30 | Observation window per step |
| `max_total_duration_minutes` | 60 | 10-180 | Maximum canary duration ceiling |
| `metric_threshold.error_rate_pct` | 1.0 | 0.1-10.0 | Error rate promotion threshold |
| `metric_threshold.latency_p99_ms` | 500 | 50-10000 | P99 latency promotion threshold |
| `rollback_threshold.error_rate_pct` | 5.0 | 1.0-50.0 | Error rate rollback threshold |
| `rollback_threshold.latency_p99_ms` | 2000 | 100-30000 | P99 latency rollback threshold |

## Performance

### Duration

| Steps | Observation per Step | Typical Total |
|-------|---------------------|---------------|
| 4 (default) | 2 min | 8-15 min |
| 4 (extended) | up to 4 min | 15-60 min |
| 2 (fast) | 1 min | 2-5 min |

Metric collection overhead: ~8s per 2-minute step (4 queries x 4 intervals x 500ms). Negligible.

## Security

- Metric endpoint credentials stored in environment variables, never in config files
- Canary traffic isolated via service mesh mTLS when available
- Rollback commands require same RBAC permissions as deploy commands
- User confirmation required for production environments regardless of strategy

## Testing

```
# Validate canary config
- canary_steps must be ascending with last element = 100
- step_duration_minutes > 0
- rollback_threshold > metric_threshold for each metric
- max_total_duration_minutes >= steps * step_duration_minutes

# Key test scenarios
- Healthy canary: all steps promote, final 100% reached
- Degraded canary at step 2: rollback triggered, stable restored
- Ambiguous metrics: observation extended, then user escalation
- Metric endpoint unreachable: fallback to health-check-only
- Argo Rollouts detected: native CRD commands used
```

## Argo Rollouts Integration

When Argo Rollouts CRDs are detected (`kubectl get crd rollouts.argoproj.io`):

1. Use `kubectl argo rollouts` commands instead of manual traffic management
2. Parse `AnalysisTemplate` CRDs for metric provider configuration
3. Leverage built-in analysis for metric-based promotion
4. Support `AnalysisRun` status monitoring for step progression

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: myapp
spec:
  strategy:
    canary:
      steps:
        - setWeight: 5
        - pause: { duration: 2m }
        - setWeight: 25
        - pause: { duration: 2m }
        - setWeight: 50
        - pause: { duration: 2m }
        - setWeight: 100
      analysis:
        templates:
          - templateName: success-rate
        startingStep: 1
```

## Dos

- Always collect baseline metrics before starting the canary
- Configure both promotion and rollback thresholds — promotion alone is insufficient
- Use Argo Rollouts when available for native traffic splitting
- Set `max_total_duration_minutes` to prevent runaway canary progressions
- Monitor error rate AND latency — a low error rate with high latency is still a regression
- Include resource utilization metrics (CPU, memory) alongside application metrics
- Require user confirmation for production canary deployments

## Don'ts

- Do not skip the baseline metric collection step — without a baseline, thresholds are meaningless
- Do not set rollback thresholds lower than promotion thresholds
- Do not use canary for stateful services without understanding session affinity implications
- Do not set `step_duration_minutes` below 1 minute — metric aggregation needs time to stabilize
- Do not disable `auto_rollback` without explicit justification
- Do not ignore extended observation signals — ambiguous metrics need investigation, not blind promotion
