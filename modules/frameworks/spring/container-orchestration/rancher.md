# Rancher with Spring

> Extends `modules/container-orchestration/rancher.md` with Spring Boot multi-cluster deployment patterns.
> Generic Rancher conventions (cluster provisioning, RBAC, monitoring) are NOT repeated here.

## Integration Setup

```yaml
# fleet/fleet.yaml
defaultNamespace: production
helm:
  releaseName: spring-app
  chart: charts/spring-app
  valuesFiles:
    - values.yaml
  values:
    image:
      repository: registry.example.com/spring-app
      tag: latest
    jvm:
      maxRamPercentage: "75"
targetCustomizations:
  - name: staging
    clusterSelector:
      matchLabels:
        env: staging
    helm:
      valuesFiles:
        - values-staging.yaml
```

## Framework-Specific Patterns

### Fleet GitOps for Spring Boot

```yaml
# fleet/gitrepo.yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: spring-app
  namespace: fleet-default
spec:
  repo: https://github.com/org/spring-app.git
  branch: main
  paths:
    - deploy/charts/
  targets:
    - name: dev
      clusterSelector:
        matchLabels:
          env: dev
    - name: production
      clusterSelector:
        matchLabels:
          env: production
```

### Spring Profile per Cluster

```yaml
# values-production.yaml
env:
  - name: SPRING_PROFILES_ACTIVE
    value: production
  - name: JAVA_TOOL_OPTIONS
    value: "-XX:MaxRAMPercentage=75 -XX:+UseG1GC -XX:+UseContainerSupport"
resources:
  requests:
    memory: 512Mi
    cpu: 500m
  limits:
    memory: 1Gi
    cpu: "2"
```

Each cluster environment activates a Spring profile via `SPRING_PROFILES_ACTIVE`. JVM tuning flags are injected as environment variables to respect container memory limits.

### Rancher Apps Catalog for Spring

```yaml
# Chart.yaml for Rancher Apps catalog
apiVersion: v2
name: spring-app
version: 1.0.0
appVersion: "1.0.0"
annotations:
  catalog.cattle.io/display-name: Spring Application
  catalog.cattle.io/os: linux
```

The `catalog.cattle.io` annotations control how the application appears in Rancher's Apps marketplace.

### Actuator Health with Fleet Health Checks

```yaml
# fleet/fleet.yaml (health check section)
helm:
  values:
    livenessProbe:
      httpGet:
        path: /actuator/health/liveness
        port: 8080
      initialDelaySeconds: 60
    readinessProbe:
      httpGet:
        path: /actuator/health/readiness
        port: 8080
```

Spring Boot Actuator health endpoints align with Fleet's health monitoring. The `initialDelaySeconds` must exceed Spring Boot's startup time.

## Scaffolder Patterns

```yaml
patterns:
  fleet_config: "fleet/fleet.yaml"
  gitrepo: "fleet/gitrepo.yaml"
  values_prod: "deploy/charts/spring-app/values-production.yaml"
```

## Additional Dos

- DO activate Spring profiles per cluster via `SPRING_PROFILES_ACTIVE`
- DO set JVM memory flags as environment variables in Fleet values
- DO use Actuator health endpoints for Fleet health monitoring
- DO set `initialDelaySeconds` above Spring Boot startup time

## Additional Don'ts

- DON'T hardcode JVM flags in the Dockerfile -- inject via environment for per-cluster tuning
- DON'T use the same memory limits across dev and production clusters
- DON'T include DevTools or Docker Compose support in production images deployed via Fleet
- DON'T skip `targetCustomizations` -- Spring profiles must match the cluster environment
