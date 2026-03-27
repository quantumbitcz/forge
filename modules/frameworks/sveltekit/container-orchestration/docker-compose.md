# Docker Compose with SvelteKit

> Extends `modules/container-orchestration/docker-compose.md` with SvelteKit development patterns.
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
      APP_API_URL: http://api:8080
      APP_PUBLIC_SITE_URL: http://localhost:3000
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
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/health"]
      interval: 10s
      retries: 5
```

## Framework-Specific Patterns

### Development with Vite HMR

```yaml
# compose.dev.yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "5173:5173"
      - "24678:24678"  # Vite HMR WebSocket
    volumes:
      - .:/app
      - /app/node_modules
    environment:
      APP_API_URL: http://api:8080
```

```dockerfile
# Dockerfile.dev
FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
EXPOSE 5173 24678
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]
```

Expose port 24678 for Vite's HMR WebSocket. The anonymous `node_modules` volume prevents host overwrite.

### Server-Side Proxy

SvelteKit's `+page.server.ts` load functions can fetch from the API service directly using the Docker Compose DNS name:

```typescript
// src/routes/dashboard/+page.server.ts
export async function load({ fetch }) {
  const res = await fetch("http://api:8080/data");
  return { data: await res.json() };
}
```

Server-side fetches in SvelteKit load functions run on the Node.js server, not the browser. Docker Compose DNS resolves `api` to the correct container.

## Scaffolder Patterns

```yaml
patterns:
  compose: "compose.yaml"
  compose_dev: "compose.dev.yaml"
  dockerfile_dev: "Dockerfile.dev"
```

## Additional Dos

- DO use `$env/dynamic/private` for server-only API URLs (Docker internal DNS)
- DO expose port 24678 for Vite HMR in development
- DO use `--host 0.0.0.0` for Vite dev server inside Docker
- DO use `depends_on: condition: service_healthy` for backend dependencies

## Additional Don'ts

- DON'T expose the Vite dev server in production -- use the adapter-node built output
- DON'T hardcode API URLs in client code -- use `$env/dynamic/public` for client-side config
- DON'T mount source code into the production image
