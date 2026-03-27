# OpenShift with Go stdlib

> Extends `modules/container-orchestration/openshift.md` with Go stdlib deployment patterns.
> Generic OpenShift conventions (DeploymentConfig, Routes, BuildConfig) are NOT repeated here.

## Integration Setup

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: go-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: go-app
  template:
    spec:
      containers:
        - name: go-app
          image: image-registry.openshift-image-registry.svc:5000/myproject/go-app:latest
          ports:
            - containerPort: 8080
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
```

## Framework-Specific Patterns

### S2I Build

```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: go-app
spec:
  source:
    type: Git
    git:
      uri: https://github.com/org/go-app
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  output:
    to:
      kind: ImageStreamTag
      name: go-app:latest
```

### OpenShift Route

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: go-app
spec:
  to:
    kind: Service
    name: go-app
  port:
    targetPort: 8080
  tls:
    termination: edge
```

### Arbitrary UID Compliance

Go static binaries from `scratch` run under any UID. OpenShift's arbitrary UID policy works seamlessly -- no special handling needed.

## Scaffolder Patterns

```yaml
patterns:
  deployment: "openshift/deployment.yaml"
  route: "openshift/route.yaml"
  buildconfig: "openshift/buildconfig.yaml"
```

## Additional Dos

- DO listen on port 8080 (non-privileged)
- DO use Docker strategy in BuildConfig for multi-stage Dockerfile
- DO configure TLS termination at the Route level
- DO use `scratch` -- it naturally complies with OpenShift UID policies

## Additional Don'ts

- DON'T listen on ports below 1024
- DON'T hardcode image registry URLs -- use ImageStreams
- DON'T skip readiness probes -- Routes depend on them
