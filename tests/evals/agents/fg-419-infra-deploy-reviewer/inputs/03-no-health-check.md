# Eval: Deployment without health checks

## Language: yaml

## Context
Kubernetes deployment with no liveness or readiness probes configured.

## Code Under Review

```yaml
# file: k8s/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-service
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: payment
          image: myregistry/payment:2.1.0
          ports:
            - containerPort: 8080
          resources:
            limits:
              memory: "512Mi"
              cpu: "1000m"
```

## Expected Behavior
Reviewer should flag missing liveness and readiness probes as a CRITICAL issue.
