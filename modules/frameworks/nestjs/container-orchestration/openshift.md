# OpenShift with NestJS

> Extends `modules/container-orchestration/openshift.md` with NestJS deployment patterns.
> Generic OpenShift conventions (DeploymentConfig, Routes, BuildConfig) are NOT repeated here.

## Integration Setup

```yaml
# openshift/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nestjs-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nestjs-app
  template:
    spec:
      containers:
        - name: nestjs-app
          image: image-registry.openshift-image-registry.svc:5000/myproject/nestjs-app:latest
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
  name: nestjs-app
spec:
  source:
    type: Git
    git:
      uri: https://github.com/org/nestjs-app
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  output:
    to:
      kind: ImageStreamTag
      name: nestjs-app:latest
```

### OpenShift Route

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: nestjs-app
spec:
  to:
    kind: Service
    name: nestjs-app
  port:
    targetPort: 3000
  tls:
    termination: edge
```

### Arbitrary UID Compliance

```dockerfile
RUN chmod -R g=u /app
```

NestJS compiles to plain JavaScript -- no runtime-specific UID requirements. Ensure the app directory is group-readable for OpenShift's arbitrary UID policy.

### Terminus Health Checks

```typescript
// health.controller.ts
@Controller("health")
export class HealthController {
  constructor(
    private health: HealthCheckService,
    private db: TypeOrmHealthIndicator,
  ) {}

  @Get()
  @HealthCheck()
  check() {
    return this.health.check([
      () => this.db.pingCheck("database"),
    ]);
  }
}
```

Use `@nestjs/terminus` for standardized health checks that OpenShift probes can consume.

### TypeORM Migration Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: nestjs-app-migrate
  annotations:
    argocd.argoproj.io/hook: PreSync
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: image-registry.openshift-image-registry.svc:5000/myproject/nestjs-app:latest
          command: ["npx", "typeorm", "migration:run", "-d", "dist/data-source.js"]
          envFrom:
            - secretRef:
                name: nestjs-app-db
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

- DO use `@nestjs/terminus` for health check endpoints
- DO use Docker strategy in BuildConfig with multi-stage Dockerfile
- DO set `NODE_ENV=production` and `PORT` via environment
- DO set `g=u` permissions for arbitrary UID compliance

## Additional Don'ts

- DON'T listen on ports below 1024
- DON'T skip readiness probes -- Routes depend on them
- DON'T include `devDependencies` in the production image
- DON'T use `ts-node` in production -- compile to JavaScript and run with `node`
