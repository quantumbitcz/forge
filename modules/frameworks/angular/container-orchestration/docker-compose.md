# Docker Compose with Angular

> Extends `modules/container-orchestration/docker-compose.md` with Angular development patterns.
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

### Angular Dev Server with Live Reload

```yaml
# compose.dev.yaml
services:
  frontend:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "4200:4200"
    volumes:
      - .:/app
      - /app/node_modules
    environment:
      NODE_OPTIONS: "--max-old-space-size=4096"
```

```dockerfile
# Dockerfile.dev
FROM node:22
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
EXPOSE 4200
CMD ["npx", "ng", "serve", "--host", "0.0.0.0", "--poll", "2000"]
```

The `--poll 2000` flag enables file watching when using Docker volume mounts, which may not support native filesystem events. The anonymous `node_modules` volume prevents host overwrite.

### API Proxy in Development

```json
// proxy.conf.json
{
  "/api": {
    "target": "http://api:8080",
    "secure": false,
    "changeOrigin": true
  }
}
```

```json
// angular.json (serve options)
{
  "serve": {
    "options": {
      "proxyConfig": "proxy.conf.json"
    }
  }
}
```

The Angular dev server proxies `/api` requests to the backend Compose service.

## Scaffolder Patterns

```yaml
patterns:
  compose: "compose.yaml"
  compose_dev: "compose.dev.yaml"
  dockerfile_dev: "Dockerfile.dev"
  proxy_conf: "proxy.conf.json"
```

## Additional Dos

- DO use `--host 0.0.0.0` for `ng serve` inside Docker to accept external connections
- DO use `--poll` for file watching when Docker volume mounts lack native FS events
- DO use an anonymous volume for `node_modules` to prevent host/container conflicts
- DO use Angular's proxy config for API requests during development

## Additional Don'ts

- DON'T mount source code into the production nginx container -- only the built `dist/` folder
- DON'T expose the dev server (port 4200) in production -- use nginx
- DON'T skip the `depends_on: condition: service_healthy` for backend dependencies
- DON'T set `NODE_OPTIONS` in production images -- it's only needed for dev server memory
