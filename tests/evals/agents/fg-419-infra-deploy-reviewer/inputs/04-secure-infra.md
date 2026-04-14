# Eval: Well-configured Kubernetes deployment

## Language: yaml

## Context
Properly configured deployment with resource limits, health checks, pinned images, and security context.

## Code Under Review

```yaml
# file: k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
spec:
  replicas: 3
  template:
    spec:
      containers:
        - name: api
          image: myregistry/api@sha256:abc123def456
          ports:
            - containerPort: 8080
          resources:
            requests:
              memory: "128Mi"
              cpu: "250m"
            limits:
              memory: "256Mi"
              cpu: "500m"
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 10
          readinessProbe:
            httpGet:
              path: /readyz
              port: 8080
          securityContext:
            runAsNonRoot: true
            readOnlyRootFilesystem: true
```

## Expected Behavior
No infra findings expected. Proper resource limits, health probes, pinned image, and security context.
