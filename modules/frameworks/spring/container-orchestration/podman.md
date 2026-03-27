# Podman with Spring

> Extends `modules/container-orchestration/podman.md` with Spring Boot containerization patterns.
> Generic Podman conventions (rootless containers, pod definitions, systemd integration) are NOT repeated here.

## Integration Setup

```bash
podman build -t spring-app:latest .
podman run -d --name spring-app -p 8080:8080 \
  -e SPRING_PROFILES_ACTIVE=production \
  -e JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+UseG1GC" \
  spring-app:latest
```

## Framework-Specific Patterns

### Pod with Database

```bash
podman pod create --name spring-pod -p 8080:8080 -p 5432:5432

podman run -d --pod spring-pod --name postgres \
  -e POSTGRES_DB=app -e POSTGRES_USER=app -e POSTGRES_PASSWORD=secret \
  postgres:16-alpine

podman run -d --pod spring-pod --name spring-app \
  -e SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/app \
  -e SPRING_DATASOURCE_USERNAME=app \
  -e SPRING_DATASOURCE_PASSWORD=secret \
  -e SPRING_PROFILES_ACTIVE=production \
  -e JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75 -XX:+UseG1GC" \
  spring-app:latest
```

Podman pods share a network namespace -- Spring connects to PostgreSQL via `localhost`, same as Docker Compose.

### Quadlet Integration

```ini
[Container]
Image=registry.example.com/spring-app:latest
PublishPort=8080:8080
Environment=SPRING_PROFILES_ACTIVE=production
Environment=JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=75 -XX:+UseG1GC -XX:+UseContainerSupport
Secret=db-url,type=env,target=SPRING_DATASOURCE_URL

[Service]
Restart=always

[Install]
WantedBy=default.target
```

### Buildah Multi-Stage Build

```bash
# Build with Buildah for fine-grained layer control
buildah from --name extract eclipse-temurin:21-jre-alpine
buildah copy extract build/libs/*.jar /app/app.jar
buildah run extract -- java -Djarmode=layertools -jar /app/app.jar extract --destination /app/extracted

buildah from --name runtime eclipse-temurin:21-jre-alpine
buildah copy --from extract runtime /app/extracted/dependencies/ /app/
buildah copy --from extract runtime /app/extracted/spring-boot-loader/ /app/
buildah copy --from extract runtime /app/extracted/application/ /app/
buildah config --cmd '["java", "-XX:MaxRAMPercentage=75", "org.springframework.boot.loader.launch.JarLauncher"]' runtime
buildah commit runtime spring-app:latest
```

### Flyway Migration

```bash
podman run --rm --pod spring-pod \
  -e SPRING_PROFILES_ACTIVE=migration \
  -e SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/app \
  -e SPRING_DATASOURCE_USERNAME=app \
  -e SPRING_DATASOURCE_PASSWORD=secret \
  spring-app:latest
```

## Scaffolder Patterns

```yaml
patterns:
  quadlet: "deploy/spring-app.container"
```

## Additional Dos

- DO use Podman pods for Spring Boot + database development environments
- DO use Quadlet for systemd-managed production deployments
- DO set JVM flags via `JAVA_TOOL_OPTIONS` to respect container memory limits
- DO use Buildah for fine-grained layered JAR image builds

## Additional Don'ts

- DON'T set `-Xmx` -- use `-XX:MaxRAMPercentage` to adapt to container limits
- DON'T skip `--pod` when running Spring Boot with a database -- they need shared networking
- DON'T include DevTools in production images
- DON'T run as root -- Podman's rootless mode is the default
