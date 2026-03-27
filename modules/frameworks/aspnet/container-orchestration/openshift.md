# OpenShift with ASP.NET

> Extends `modules/container-orchestration/openshift.md` with ASP.NET Core deployment patterns.
> Generic OpenShift conventions (DeploymentConfig, Routes, BuildConfig) are NOT repeated here.

## Integration Setup

```yaml
# openshift/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aspnet-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: aspnet-app
  template:
    spec:
      containers:
        - name: aspnet-app
          image: image-registry.openshift-image-registry.svc:5000/myproject/aspnet-app:latest
          ports:
            - containerPort: 8080
          env:
            - name: ASPNETCORE_ENVIRONMENT
              value: Production
            - name: ASPNETCORE_URLS
              value: http://+:8080
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
          readinessProbe:
            httpGet:
              path: /health/ready
              port: 8080
```

## Framework-Specific Patterns

### Source-to-Image (S2I) Build

```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: aspnet-app
spec:
  source:
    type: Git
    git:
      uri: https://github.com/org/aspnet-app
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  output:
    to:
      kind: ImageStreamTag
      name: aspnet-app:latest
  triggers:
    - type: GitHub
      github:
        secret: webhook-secret
```

### OpenShift Route

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: aspnet-app
spec:
  to:
    kind: Service
    name: aspnet-app
  port:
    targetPort: 8080
  tls:
    termination: edge
```

### Non-Root Container Compliance

OpenShift runs containers with arbitrary UIDs by default. ASP.NET containers must not assume a specific UID:

```dockerfile
# Avoid USER directives with specific UIDs
# OpenShift assigns a random UID from the project's range
ENV ASPNETCORE_URLS=http://+:8080
```

### EF Core Migration Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: aspnet-app-migrate
  annotations:
    argocd.argoproj.io/hook: PreSync
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: image-registry.openshift-image-registry.svc:5000/myproject/aspnet-app:latest
          command: ["dotnet", "MyApp.Api.dll", "--migrate"]
          envFrom:
            - secretRef:
                name: aspnet-app-db
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

- DO listen on port 8080 (non-privileged) -- OpenShift blocks ports below 1024
- DO use OpenShift's internal image registry for build outputs
- DO configure TLS termination at the Route level
- DO test with arbitrary UIDs -- OpenShift assigns random UIDs

## Additional Don'ts

- DON'T use `USER` directive with UID 0 or specific UIDs -- OpenShift overrides them
- DON'T listen on ports below 1024 -- they require elevated privileges
- DON'T hardcode the image registry URL -- use ImageStreams for portability
- DON'T skip readiness probes -- OpenShift Routes depend on them for traffic routing
