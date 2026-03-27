# Docker Swarm with ASP.NET

> Extends `modules/container-orchestration/docker-swarm.md` with ASP.NET Core service deployment patterns.
> Generic Docker Swarm conventions (service replicas, overlay networks, rolling updates) are NOT repeated here.

## Integration Setup

```yaml
# docker-stack.yml
version: "3.8"

services:
  app:
    image: registry.example.com/aspnet-app:latest
    deploy:
      replicas: 3
      update_config:
        parallelism: 1
        delay: 15s
        order: start-first
        failure_action: rollback
      restart_policy:
        condition: on-failure
        max_attempts: 3
    environment:
      ASPNETCORE_ENVIRONMENT: Production
      DOTNET_EnableDiagnostics: "0"
    secrets:
      - db-connection
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 5s
      start_period: 15s
      retries: 3
    networks:
      - backend

secrets:
  db-connection:
    external: true

networks:
  backend:
    driver: overlay
```

## Framework-Specific Patterns

### Reading Secrets from Files

```csharp
// Program.cs
builder.Configuration.AddKeyPerFile("/run/secrets", optional: true);
```

ASP.NET Core's `AddKeyPerFile` reads Docker secrets from `/run/secrets/` as key-value configuration entries.

### Rolling Update Strategy

```yaml
deploy:
  update_config:
    parallelism: 1
    delay: 15s
    order: start-first
    failure_action: rollback
    monitor: 30s
```

ASP.NET starts in 2-5 seconds. Use `start-first` for zero-downtime deployments.

## Scaffolder Patterns

```yaml
patterns:
  stack: "docker-stack.yml"
```

## Additional Dos

- DO use `AddKeyPerFile` to read Docker secrets as configuration
- DO use `start-first` for zero-downtime deployments
- DO set `DOTNET_EnableDiagnostics=0` in production
- DO set `monitor` to detect post-deploy failures

## Additional Don'ts

- DON'T embed connection strings in environment variables in stack files
- DON'T use `ASPNETCORE_ENVIRONMENT=Development` in production
- DON'T set `start_period` too long -- ASP.NET starts in seconds
