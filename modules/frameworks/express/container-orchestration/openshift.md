# OpenShift with Express

> Extends `modules/container-orchestration/openshift.md` with Express/Node.js deployment patterns.
> Generic OpenShift conventions (DeploymentConfig, Routes, BuildConfig) are NOT repeated here.

## Integration Setup

```yaml
# openshift/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: express-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: express-app
  template:
    spec:
      containers:
        - name: express-app
          image: image-registry.openshift-image-registry.svc:5000/myproject/express-app:latest
          ports:
            - containerPort: 3000
          env:
            - name: NODE_ENV
              value: production
            - name: PORT
              value: "3000"
          livenessProbe:
            httpGet:
              path: /health
              port: 3000
          readinessProbe:
            httpGet:
              path: /health
              port: 3000
```

## Framework-Specific Patterns

### Source-to-Image (S2I) Build

```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: express-app
spec:
  source:
    type: Git
    git:
      uri: https://github.com/org/express-app
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  output:
    to:
      kind: ImageStreamTag
      name: express-app:latest
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
  name: express-app
spec:
  to:
    kind: Service
    name: express-app
  port:
    targetPort: 3000
  tls:
    termination: edge
```

### Arbitrary UID Compliance

Node.js slim images create a `node` user with a fixed UID. OpenShift overrides this -- ensure the app directory is group-readable:

```dockerfile
RUN chmod -R g=u /app
```

### Graceful Shutdown

```typescript
process.on("SIGTERM", () => {
  server.close(() => {
    process.exit(0);
  });
});
```

OpenShift sends `SIGTERM` on pod termination. Close the HTTP server to finish in-flight requests.

### Database Migration Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: express-app-migrate
  annotations:
    argocd.argoproj.io/hook: PreSync
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: image-registry.openshift-image-registry.svc:5000/myproject/express-app:latest
          command: ["npx", "prisma", "migrate", "deploy"]
          envFrom:
            - secretRef:
                name: express-app-db
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

- DO use Docker strategy in BuildConfig with the three-stage Dockerfile
- DO set `NODE_ENV=production` in the deployment
- DO handle `SIGTERM` for graceful shutdown
- DO set `g=u` permissions for OpenShift's arbitrary UID policy

## Additional Don'ts

- DON'T use `npm start` when it just calls `node` -- invoke `node` directly
- DON'T listen on ports below 1024
- DON'T skip readiness probes -- Routes depend on them
- DON'T include `devDependencies` in the production image
