# Rolling Deployment Strategy

## Overview

Pod-by-pod replacement of the old version with the new version, controlled by surge and unavailability settings. The Kubernetes Deployment controller replaces pods incrementally, ensuring that a minimum number of pods remain available throughout the rollout. This is the simplest and most common deployment strategy, and the default when no strategy is explicitly selected.

- **Use for:** standard deployments where gradual replacement is sufficient, environments without metric collection infrastructure, services that tolerate brief mixed-version traffic during rollout
- **Avoid for:** deployments requiring metric-based promotion decisions (use canary), deployments requiring instant rollback (use blue-green), database migrations that are incompatible with mixed versions
- **Key differentiators:** native Kubernetes support (no additional tooling), simplest configuration, built-in `kubectl rollout undo` for rollback

## Architecture Patterns

### Surge and Unavailability

The rolling update behavior is controlled by two parameters:

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%        # Max pods above desired count during rollout
      maxUnavailable: 25%  # Max pods unavailable during rollout
```

| Setting | Effect | Use Case |
|---------|--------|----------|
| `maxSurge: 25%, maxUnavailable: 0` | Always maintains full capacity, creates extra pods first | Production services with strict availability requirements |
| `maxSurge: 0, maxUnavailable: 25%` | Never exceeds desired count, removes old pods first | Resource-constrained clusters |
| `maxSurge: 25%, maxUnavailable: 25%` | Balanced — faster rollout with acceptable capacity dip | General purpose (default) |
| `maxSurge: 100%, maxUnavailable: 0` | Creates all new pods first, then removes old — effectively blue-green | Fast rollout when resources are available |

### Rollout Monitoring

During a rolling update, monitor rollout status:

```bash
# Watch rollout progress
kubectl rollout status deployment/myapp --timeout=600s

# Check rollout history
kubectl rollout history deployment/myapp

# Inspect current state
kubectl get pods -l app=myapp -o wide
```

The deploy verifier (fg-620) polls `kubectl rollout status` every 15 seconds and collects metrics during the rollout.

### Rollback

```bash
# Undo to previous revision
kubectl rollout undo deployment/myapp

# Undo to specific revision
kubectl rollout undo deployment/myapp --to-revision=3
```

Rollback is triggered automatically when:
- Metric degradation detected during rollout
- Rollout stalls (no progress for `rollout_timeout_minutes`)
- Pod crash loops detected during replacement

### Health Probes

Rolling deployments rely heavily on Kubernetes health probes to determine when new pods are ready:

```yaml
spec:
  containers:
    - name: myapp
      livenessProbe:
        httpGet:
          path: /health/live
          port: 8080
        initialDelaySeconds: 10
        periodSeconds: 10
      readinessProbe:
        httpGet:
          path: /health/ready
          port: 8080
        initialDelaySeconds: 5
        periodSeconds: 5
      startupProbe:
        httpGet:
          path: /health/started
          port: 8080
        failureThreshold: 30
        periodSeconds: 5
```

Without proper readiness probes, the rollout controller cannot distinguish healthy from unhealthy pods, leading to traffic routing to pods that are not ready to serve.

## Configuration

```yaml
deployment:
  default_strategy: rolling
  rolling:
    max_surge: "25%"
    max_unavailable: "25%"
    rollout_timeout_minutes: 10
  metric_threshold:
    error_rate_pct: 1.0
    latency_p99_ms: 500
  auto_rollback: true
```

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `max_surge` | `"25%"` | Percentage or integer | Maximum pods above desired count during rollout |
| `max_unavailable` | `"25%"` | Percentage or integer | Maximum pods unavailable during rollout |
| `rollout_timeout_minutes` | 10 | 2-60 | Maximum time for rollout completion |

## Performance

| Deployment Size | Typical Duration | Variables |
|-----------------|------------------|-----------|
| 1-3 pods | 1-3 min | Image pull, readiness probe delay |
| 5-10 pods | 3-7 min | Pod count, surge setting |
| 20+ pods | 5-15 min | Pod count, max_surge percentage |

Duration is primarily determined by: image pull time + readiness probe `initialDelaySeconds` + probe success threshold x pod count / parallelism (governed by `maxSurge`).

## Security

- Rolling updates use the same RBAC as standard deployments
- During rollout, mixed versions are serving traffic — ensure API backward compatibility
- Image tags should be immutable (use SHA digests, not `latest`)
- Pod Security Standards apply equally to old and new pods during transition

## Testing

```
# Validate rolling config
- max_surge must be a valid percentage or integer
- max_unavailable must be a valid percentage or integer
- max_surge and max_unavailable cannot both be 0
- rollout_timeout_minutes > 0

# Key test scenarios
- Clean rollout: all pods replaced, rollout status completes
- Stalled rollout: new pods fail readiness, timeout triggers WARNING
- Metric degradation: rollout undo triggered during replacement
- Crash loop: new pods CrashLoopBackOff, rollout undo triggered
- Image pull failure: pods stuck in ImagePullBackOff, timeout reached
```

## Dos

- Configure readiness probes on all containers — the rollout controller depends on them
- Set `maxSurge` and `maxUnavailable` based on your capacity and availability requirements
- Use immutable image tags (SHA digests) to ensure reproducible deployments
- Monitor rollout status actively — a stalled rollout may indicate a problem before metrics degrade
- Set `rollout_timeout_minutes` to a reasonable ceiling based on your pod startup time
- Ensure API backward compatibility between old and new versions during mixed-version traffic

## Don'ts

- Do not set both `maxSurge` and `maxUnavailable` to 0 — the rollout cannot progress
- Do not use `latest` image tag — it makes rollback unreliable and defeats cache optimization
- Do not skip readiness probes — without them, traffic routes to unready pods during rollout
- Do not set `rollout_timeout_minutes` too low — slow image pulls or JVM startup will trigger false timeouts
- Do not deploy database schema changes simultaneously with a rolling update if the old version cannot read the new schema
- Do not ignore stalled rollout warnings — they often precede cascading failures
