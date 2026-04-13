# Blue-Green Deployment Strategy

## Overview

Parallel environment deployment with instant traffic switch and rollback. Two identical environments (blue and green) run simultaneously. The inactive environment receives the new deployment, is health-checked, and then traffic is switched from the active to the standby environment. If degradation is detected post-switch, traffic is instantly reverted to the previous environment.

- **Use for:** zero-downtime deployments requiring instant rollback capability, environments where gradual traffic shifting is not feasible (e.g., database schema changes that affect all traffic)
- **Avoid for:** environments with high infrastructure cost sensitivity (requires 2x resources), stateful services where environment duplication is impractical, projects without load balancer or service mesh control
- **Key differentiators:** instant rollback (traffic switch only, no re-deployment), full environment validation before traffic switch, zero mixed-version traffic during transition

## Architecture Patterns

### Environment Management

```
              Load Balancer / Service Mesh
                    |
         +----------+-----------+
         |                      |
    Blue (active)         Green (standby)
    v2.0.0                v2.1.0 (new deploy)
         |                      |
    Receives traffic      Health-checked
                          Warm-up period
                               |
                          Traffic switch
                               |
    Blue (standby)        Green (active)
    v2.0.0                v2.1.0
```

### Traffic Switch Methods

| Method | Command | Rollback |
|--------|---------|----------|
| K8s Service selector | `kubectl patch svc main -p '{"spec":{"selector":{"version":"green"}}}'` | Patch selector back to `blue` |
| Ingress backend | Update Ingress spec to point to green service | Revert Ingress spec |
| Istio VirtualService | Update route destination to green subset | Revert to blue subset |
| AWS ALB target group | `aws elbv2 modify-listener` to swap target groups | Swap back |
| Argo Rollouts | Native blue-green strategy CRD | `kubectl argo rollouts undo` |

### Deployment Flow

1. **Deploy to standby:** Execute deploy command targeting the inactive environment
2. **Warm-up:** Wait `warm_up_duration_minutes` for the new deployment to initialize (cache warming, JIT compilation, connection pool establishment)
3. **Health check:** Run `standby_health_check` against the standby environment
4. **Traffic switch:** Execute `traffic_switch_command` to route all traffic to the new environment
5. **Observation window:** Monitor metrics for `observation_window_minutes`
6. **Finalize or rollback:** If metrics are healthy, keep new active. If degraded, execute `rollback_command`

### Post-Switch Monitoring

After traffic switch, the deploy verifier (fg-620) monitors metrics from the newly active environment and compares against pre-switch baseline. Any degradation beyond configured thresholds triggers an automatic rollback.

## Configuration

```yaml
deployment:
  default_strategy: blue-green
  blue_green:
    standby_health_check: "curl -sf http://standby.internal/health"
    traffic_switch_command: "kubectl patch svc main -p '{\"spec\":{\"selector\":{\"version\":\"green\"}}}'"
    rollback_command: "kubectl patch svc main -p '{\"spec\":{\"selector\":{\"version\":\"blue\"}}}'"
    warm_up_duration_minutes: 5
    observation_window_minutes: 10
  metric_threshold:
    error_rate_pct: 1.0
    latency_p99_ms: 500
  auto_rollback: true
```

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `warm_up_duration_minutes` | 5 | 1-30 | Time for standby to warm up after deploy |
| `observation_window_minutes` | 10 | 2-60 | Post-switch monitoring duration |
| `standby_health_check` | required | command or URL | Health verification for standby before switch |
| `traffic_switch_command` | required | command | Command to switch traffic from active to standby |
| `rollback_command` | required | command | Command to switch traffic back |

## Performance

| Phase | Duration | Notes |
|-------|----------|-------|
| Deploy to standby | 2-10 min | Same as any deployment |
| Warm-up | 1-30 min | Configurable, depends on application startup |
| Health check | 10-30s | Single health endpoint call |
| Traffic switch | <5s | Service selector or routing rule change |
| Observation window | 2-60 min | Configurable monitoring period |
| Rollback (if needed) | <5s | Instant traffic revert |
| **Total** | **5-15 min typical** | Excluding warm-up configuration |

## Security

- Traffic switch and rollback commands require cluster RBAC permissions
- Both environments share the same secrets and config — ensure rotation covers both
- Health check endpoints should not expose sensitive information
- Standby environment should not receive external traffic before the switch

## Testing

```
# Validate blue-green config
- standby_health_check must be set
- traffic_switch_command must be set
- rollback_command must be set
- warm_up_duration_minutes > 0
- observation_window_minutes > 0

# Key test scenarios
- Healthy standby: traffic switch succeeds, observation healthy, finalize
- Unhealthy standby: health check fails, abort without switching traffic
- Post-switch degradation: rollback triggered, traffic returns to previous active
- Rollback command failure: CRITICAL finding, manual intervention required
- Metric endpoint unreachable: fallback to health-check-only monitoring
```

## Dos

- Always verify standby health before switching traffic
- Configure a warm-up period appropriate for your application (JVM warm-up, cache priming, etc.)
- Set rollback commands that are the exact inverse of the traffic switch
- Run the observation window long enough to detect slow-building regressions (memory leaks, connection pool exhaustion)
- Keep the previous active environment running until the observation window completes
- Use environment labels (`blue`/`green` or `v1`/`v2`) consistently across services and config

## Don'ts

- Do not tear down the previous active environment until the observation window passes
- Do not use blue-green for services that cannot tolerate traffic switching (long-lived connections without graceful drain)
- Do not skip the warm-up period — cold-start latency spikes will trigger false-positive rollbacks
- Do not configure `observation_window_minutes` below 2 minutes — metric aggregation needs time
- Do not rely on blue-green for database schema migrations without a separate migration strategy
- Do not forget to update both environments' secrets and config when rotating credentials
