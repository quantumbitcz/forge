# Docker Compose with Vue / Nuxt

> Extends `modules/container-orchestration/docker-compose.md` with Vue 3 / Nuxt 3 development patterns.
> Generic Docker Compose conventions (service definitions, networking, volumes) are NOT repeated here.

## Integration Setup

```yaml
# compose.yaml
services:
  frontend:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    environment:
      NUXT_PUBLIC_API_BASE: http://api:8080
    depends_on:
      api:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/"]
      interval: 30s
      timeout: 3s
      retries: 3

  api:
    image: registry.example.com/api:latest
    ports:
      - "8080:8080"
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/health"]
      interval: 10s
      retries: 5

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

### Nuxt Dev Server with Hot Reload

```yaml
# compose.dev.yaml
services:
  frontend:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "3000:3000"
      - "24678:24678"  # Vite HMR WebSocket
    volumes:
      - .:/app
      - /app/node_modules
    environment:
      NUXT_PUBLIC_API_BASE: http://api:8080
```

```dockerfile
# Dockerfile.dev
FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
EXPOSE 3000 24678
CMD ["npx", "nuxt", "dev", "--host", "0.0.0.0"]
```

Expose port 24678 for Vite's HMR WebSocket. The anonymous `node_modules` volume prevents host overwrite.

### Nuxt Server Proxy (Development)

```typescript
// nuxt.config.ts
export default defineNuxtConfig({
  devProxy: {
    "/api": {
      target: "http://api:8080",
      changeOrigin: true,
    },
  },
});
```

In Docker Compose, Nuxt's dev proxy can route API requests to the backend service by Docker DNS name.

## Scaffolder Patterns

```yaml
patterns:
  compose: "compose.yaml"
  compose_dev: "compose.dev.yaml"
  dockerfile_dev: "Dockerfile.dev"
```

## Additional Dos

- DO expose port 24678 for Vite HMR WebSocket in development
- DO use `--host 0.0.0.0` for `nuxt dev` inside Docker
- DO use `NUXT_*` env vars for runtime configuration in Compose
- DO use an anonymous volume for `node_modules`

## Additional Don'ts

- DON'T use the dev server in production Compose stacks
- DON'T mount source code into the production image
- DON'T hardcode API URLs -- use `runtimeConfig` with environment variables
- DON'T skip `depends_on: condition: service_healthy` for backend dependencies
