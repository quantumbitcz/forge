# Docker Compose with React

> Extends `modules/container-orchestration/docker-compose.md` with React + Vite development patterns.
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
      - "80:80"
    depends_on:
      api:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:80/"]
      interval: 30s
      timeout: 3s
      retries: 3

  api:
    image: registry.example.com/api:latest
    ports:
      - "8080:8080"
    environment:
      DATABASE_URL: postgresql://app:secret@postgres:5432/app
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

### Vite Dev Server with Hot Reload

```yaml
# compose.dev.yaml (development overlay)
services:
  frontend:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "5173:5173"
    volumes:
      - .:/app
      - /app/node_modules  # anonymous volume to prevent host overwrite
    environment:
      VITE_API_URL: http://localhost:8080
```

```dockerfile
# Dockerfile.dev
FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
EXPOSE 5173
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]
```

Run with `docker compose -f compose.yaml -f compose.dev.yaml up`. The volume mount enables Vite's HMR. The anonymous `node_modules` volume prevents the host from overwriting container dependencies.

### API Proxy in Development

```typescript
// vite.config.ts
export default defineConfig({
  server: {
    proxy: {
      "/api": {
        target: "http://api:8080",
        changeOrigin: true,
      },
    },
  },
});
```

When running inside Docker Compose, the Vite dev server can proxy API requests to the `api` service by name via the Docker network.

### Production with nginx Reverse Proxy

```yaml
services:
  frontend:
    build: .
    ports:
      - "80:80"
    environment:
      REACT_APP_API_URL: /api
```

In production, configure nginx to proxy `/api` requests to the backend service, avoiding CORS.

## Scaffolder Patterns

```yaml
patterns:
  compose: "compose.yaml"
  compose_dev: "compose.dev.yaml"
  dockerfile_dev: "Dockerfile.dev"
```

## Additional Dos

- DO use a development overlay (`compose.dev.yaml`) for Vite dev server with volume mounts
- DO use an anonymous volume for `node_modules` to prevent host/container conflicts
- DO use `depends_on` with `condition: service_healthy` for backend dependencies
- DO pass `--host 0.0.0.0` to Vite dev server when running inside Docker

## Additional Don'ts

- DON'T mount source code into the production nginx container -- only the built `dist/` folder
- DON'T expose the Vite dev server (port 5173) in production -- use the nginx-based image
- DON'T hardcode API URLs in the frontend -- use env vars or proxy configuration
- DON'T skip the anonymous `node_modules` volume -- host modules may be platform-incompatible
