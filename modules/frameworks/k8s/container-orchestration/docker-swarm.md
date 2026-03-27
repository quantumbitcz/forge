# Docker Swarm with Kubernetes

> Extends `modules/container-orchestration/docker-swarm.md` with Kubernetes migration and coexistence patterns.
> Generic Docker Swarm conventions (services, stacks, overlay networks) are NOT repeated here.

## Integration Setup

Docker Swarm and Kubernetes serve the same purpose (container orchestration) and are not used together in production. This binding covers migration patterns from Swarm to Kubernetes and coexistence during transition periods.

```yaml
# Swarm stack (source)
version: "3.8"
services:
  app:
    image: registry.example.com/app:latest
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 10s
      resources:
        limits:
          memory: 512M
          cpus: "1.0"
    ports:
      - "8080:8080"
```

## Framework-Specific Patterns

### Swarm-to-Kubernetes Migration

```yaml
# Equivalent Kubernetes Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  template:
    spec:
      containers:
        - name: app
          image: registry.example.com/app:latest
          ports:
            - containerPort: 8080
          resources:
            limits:
              memory: 512Mi
              cpu: "1"
```

Key mapping: Swarm `deploy.replicas` maps to `spec.replicas`, `deploy.update_config.parallelism` maps to `rollingUpdate.maxUnavailable`, `deploy.resources.limits` maps to container `resources.limits`.

### Swarm Secrets to Kubernetes Secrets

```bash
# Swarm: docker secret create db-password ./secret.txt
# Kubernetes equivalent:
kubectl create secret generic db-password --from-file=password=./secret.txt
```

```yaml
# Mount in pod spec
volumes:
  - name: db-secret
    secret:
      secretName: db-password
containers:
  - volumeMounts:
      - name: db-secret
        mountPath: /run/secrets/db-password
        readOnly: true
```

Mount Kubernetes secrets at `/run/secrets/` to maintain the same path convention that Docker Swarm uses.

### Swarm Configs to ConfigMaps

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  config.yaml: |
    key: value
```

Swarm `configs` map directly to Kubernetes ConfigMaps. Both support file-based mounting.

## Scaffolder Patterns

```yaml
patterns:
  deployment: "k8s/deployment.yaml"
  service: "k8s/service.yaml"
```

## Additional Dos

- DO migrate Swarm stacks to Kubernetes Deployments with equivalent resource limits
- DO mount secrets at `/run/secrets/` for path compatibility during migration
- DO use Kompose as a starting point for Swarm-to-Kubernetes manifest conversion
- DO plan a phased migration -- run Swarm and Kubernetes in parallel during transition

## Additional Don'ts

- DON'T run both Swarm and Kubernetes on the same nodes -- they compete for resources
- DON'T assume Swarm networking translates to Kubernetes -- Service DNS differs
- DON'T use Swarm-style `docker stack deploy` in Kubernetes workflows
- DON'T migrate without testing -- Swarm and Kubernetes have different health check semantics
