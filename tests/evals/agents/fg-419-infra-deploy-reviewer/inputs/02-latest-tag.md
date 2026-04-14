# Eval: Container image using latest tag

## Language: yaml

## Context
Kubernetes deployment uses the :latest tag instead of a pinned version or SHA digest.

## Code Under Review

```yaml
# file: k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-frontend
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: web
          image: myregistry/web:latest
          resources:
            limits:
              memory: "256Mi"
              cpu: "500m"
```

## Expected Behavior
Reviewer should flag :latest tag usage. Images should be pinned to a specific version or SHA.
