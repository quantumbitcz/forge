# Eval: Container without resource limits

## Language: yaml

## Context
Kubernetes deployment manifest with no CPU or memory limits set on containers.

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
          image: myregistry/api:1.2.3
          ports:
            - containerPort: 8080
```

## Expected Behavior
Reviewer should flag missing resource requests and limits on the container.
