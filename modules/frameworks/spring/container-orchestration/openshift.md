# OpenShift with Spring

> Extends `modules/container-orchestration/openshift.md` with Spring Boot deployment patterns.
> Generic OpenShift conventions (DeploymentConfig, Routes, BuildConfig) are NOT repeated here.

## Integration Setup

```yaml
# openshift/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spring-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: spring-app
  template:
    spec:
      containers:
        - name: spring-app
          image: image-registry.openshift-image-registry.svc:5000/myproject/spring-app:latest
          ports:
            - containerPort: 8080
          env:
            - name: SPRING_PROFILES_ACTIVE
              value: production
            - name: JAVA_TOOL_OPTIONS
              value: "-XX:MaxRAMPercentage=75 -XX:+UseG1GC -XX:+UseContainerSupport"
          livenessProbe:
            httpGet:
              path: /actuator/health/liveness
              port: 8080
            initialDelaySeconds: 60
          readinessProbe:
            httpGet:
              path: /actuator/health/readiness
              port: 8080
            initialDelaySeconds: 30
```

## Framework-Specific Patterns

### Source-to-Image (S2I) Build

```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: spring-app
spec:
  source:
    type: Git
    git:
      uri: https://github.com/org/spring-app
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: Dockerfile
  output:
    to:
      kind: ImageStreamTag
      name: spring-app:latest
  triggers:
    - type: GitHub
      github:
        secret: webhook-secret
```

Use Docker strategy with the layered JAR Dockerfile. Avoid S2I builder images for Spring Boot -- the layered JAR approach produces better Docker cache utilization.

### OpenShift Route

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: spring-app
spec:
  to:
    kind: Service
    name: spring-app
  port:
    targetPort: 8080
  tls:
    termination: edge
```

### Arbitrary UID Compliance

OpenShift runs containers with arbitrary UIDs. Spring Boot's layered JarLauncher runs under any UID, but the application directory must be world-readable:

```dockerfile
# Ensure directories are readable by arbitrary UIDs
RUN chmod -R g=u /app
```

### Flyway/Liquibase Migration Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: spring-app-migrate
  annotations:
    argocd.argoproj.io/hook: PreSync
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: image-registry.openshift-image-registry.svc:5000/myproject/spring-app:latest
          command: ["java", "-XX:MaxRAMPercentage=75", "org.springframework.boot.loader.launch.JarLauncher"]
          env:
            - name: SPRING_PROFILES_ACTIVE
              value: migration
          envFrom:
            - secretRef:
                name: spring-app-db
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

- DO use Actuator health endpoints for liveness/readiness probes
- DO set `initialDelaySeconds` above Spring Boot's startup time (typically 30-60s)
- DO set JVM flags via `JAVA_TOOL_OPTIONS` environment variable
- DO ensure application directories are group-readable for arbitrary UID compliance

## Additional Don'ts

- DON'T use `-Xmx` -- use `-XX:MaxRAMPercentage` to respect container memory limits
- DON'T listen on ports below 1024 -- OpenShift blocks privileged ports
- DON'T use S2I builder images for Spring Boot -- layered JAR Dockerfile is superior
- DON'T skip readiness probes -- OpenShift Routes depend on them for traffic routing
