# OpenShift with FastAPI

> Extends `modules/container-orchestration/openshift.md` with FastAPI deployment patterns.
> Generic OpenShift conventions (DeploymentConfig, Routes, BuildConfig) are NOT repeated here.

## Integration Setup

```yaml
# openshift/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: fastapi-app
  template:
    spec:
      containers:
        - name: fastapi-app
          image: image-registry.openshift-image-registry.svc:5000/myproject/fastapi-app:latest
          ports:
            - containerPort: 8000
          env:
            - name: APP_ENV
              value: production
            - name: UVICORN_WORKERS
              value: "4"
          command: ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
```

## Framework-Specific Patterns

### Source-to-Image (S2I) Build

```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: fastapi-app
spec:
  source:
    type: Git
    git:
      uri: https://github.com/org/fastapi-app
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  output:
    to:
      kind: ImageStreamTag
      name: fastapi-app:latest
```

### OpenShift Route

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: fastapi-app
spec:
  to:
    kind: Service
    name: fastapi-app
  port:
    targetPort: 8000
  tls:
    termination: edge
```

### Arbitrary UID Compliance

Python images typically run as root. Ensure the app directory is group-readable:

```dockerfile
RUN chmod -R g=u /app
USER 1001
```

OpenShift overrides the UID but keeps the group. The `g=u` permission ensures the arbitrary UID can read all files.

### Alembic Migration Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: fastapi-app-migrate
  annotations:
    argocd.argoproj.io/hook: PreSync
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: image-registry.openshift-image-registry.svc:5000/myproject/fastapi-app:latest
          command: ["alembic", "upgrade", "head"]
          envFrom:
            - secretRef:
                name: fastapi-app-db
      restartPolicy: Never
```

## Scaffolder Patterns

```yaml
patterns:
  deployment: "openshift/deployment.yaml"
  route: "openshift/route.yaml"
  buildconfig: "openshift/buildconfig.yaml"
```

## Additional Dos

- DO use Uvicorn with `--workers` for multi-process production deployment
- DO listen on port 8000 (non-privileged)
- DO use Docker strategy in BuildConfig for multi-stage Dockerfile
- DO set `g=u` permissions for arbitrary UID compliance

## Additional Don'ts

- DON'T use `--reload` in production -- it watches for file changes and wastes resources
- DON'T listen on ports below 1024
- DON'T hardcode database URLs -- use Kubernetes Secrets
- DON'T skip readiness probes -- Routes depend on them for traffic routing
