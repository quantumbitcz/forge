# Docker with Express

> Extends `modules/container-orchestration/docker.md` with Express/Node.js containerization patterns.
> Generic Docker conventions (multi-stage builds, layer caching, security scanning) are NOT repeated here.

## Integration Setup

### Multi-Stage Dockerfile

```dockerfile
# Stage 1: Build
FROM node:22-slim AS builder
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY tsconfig.json ./
COPY src/ ./src/
RUN npm run build

# Stage 2: Production dependencies
FROM node:22-slim AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

# Stage 3: Runtime
FROM node:22-slim
WORKDIR /app

RUN addgroup --system app && adduser --system --group app

COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY package.json ./

USER app:app

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD node -e "fetch('http://localhost:3000/health').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"

CMD ["node", "dist/index.js"]
```

Three stages: build (compiles TypeScript), deps (production-only `node_modules`), runtime (minimal image with compiled JS and prod deps).

## Framework-Specific Patterns

### PM2 Cluster Mode

```dockerfile
RUN npm install -g pm2

CMD ["pm2-runtime", "ecosystem.config.js"]
```

```javascript
// ecosystem.config.js
module.exports = {
  apps: [{
    name: "express-app",
    script: "dist/index.js",
    instances: "max",
    exec_mode: "cluster",
    max_memory_restart: "256M"
  }]
};
```

PM2 cluster mode uses all available CPU cores. `max_memory_restart` prevents memory leaks from accumulating.

### Health Check Endpoint

```typescript
// src/routes/health.ts
app.get("/health", (req, res) => {
  res.json({ status: "ok" });
});
```

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD node -e "fetch('http://localhost:3000/health').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"
```

Use Node.js `fetch` for health checks -- no need for `curl` or `wget` in the image.

### Graceful Shutdown

```typescript
process.on("SIGTERM", () => {
  server.close(() => {
    process.exit(0);
  });
});
```

Docker sends `SIGTERM` on container stop. Close the HTTP server gracefully to finish in-flight requests before exiting.

## Scaffolder Patterns

```yaml
patterns:
  dockerfile: "Dockerfile"
  dockerignore: ".dockerignore"
```

## Additional Dos

- DO use `npm ci --omit=dev` in a separate stage for production-only dependencies
- DO use Node.js `fetch` for HEALTHCHECK in slim images without curl/wget
- DO handle `SIGTERM` for graceful shutdown in Docker containers
- DO use three-stage builds: compile, prod deps, runtime

## Additional Don'ts

- DON'T include `devDependencies` in the production image -- use `--omit=dev`
- DON'T use `npm start` in CMD when it just calls `node` -- invoke `node` directly to avoid a wrapper process
- DON'T run as root -- create an `app` user and switch before CMD
- DON'T copy `node_modules/` from the host -- always `npm ci` inside Docker
