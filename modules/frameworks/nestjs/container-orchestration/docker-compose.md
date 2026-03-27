# Docker Compose with NestJS

> Extends `modules/container-orchestration/docker-compose.md` with NestJS service composition patterns.
> Generic Docker Compose conventions (service definitions, networking, volumes) are NOT repeated here.

## Integration Setup

```yaml
# compose.yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgresql://app:secret@postgres:5432/app
      NODE_ENV: production
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: secret
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app"]
      interval: 10s
      retries: 5

volumes:
  pgdata:
```

## Framework-Specific Patterns

### Development Overlay

```yaml
# compose.dev.yaml
services:
  app:
    command: npm run start:dev
    volumes:
      - ./src:/app/src
    environment:
      NODE_ENV: development
    ports:
      - "3000:3000"
      - "9229:9229"
```

### Microservices Transport

```yaml
services:
  api-gateway:
    build: .
    ports:
      - "3000:3000"
    environment:
      MICROSERVICE_HOST: order-service
      MICROSERVICE_PORT: 3001

  order-service:
    build: ./apps/order-service
    environment:
      DATABASE_URL: postgresql://app:secret@postgres:5432/orders
    expose:
      - "3001"
```

NestJS microservices communicate via TCP, Redis, NATS, or gRPC transport. Use `expose` (not `ports`) for internal service-to-service communication.

## Scaffolder Patterns

```yaml
patterns:
  compose: "compose.yaml"
  compose_dev: "compose.dev.yaml"
```

## Additional Dos

- DO use `depends_on` with `condition: service_healthy` for database dependencies
- DO use compose overlay files for development configuration
- DO use `expose` for inter-service ports in microservice architectures
- DO separate NestJS microservices into distinct Compose services

## Additional Don'ts

- DON'T mount `node_modules/` from host -- platform-specific binaries cause issues
- DON'T use `nest start` in production -- use `node dist/main.js`
- DON'T expose microservice transport ports to the host
