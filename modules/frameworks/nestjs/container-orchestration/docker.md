# Docker with NestJS

> Extends `modules/container-orchestration/docker.md` with NestJS containerization patterns.
> Generic Docker conventions (multi-stage builds, layer caching, security scanning) are NOT repeated here.

## Integration Setup

### Multi-Stage Dockerfile

```dockerfile
# Stage 1: Build
FROM node:22-slim AS builder
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY tsconfig*.json nest-cli.json ./
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

CMD ["node", "dist/main.js"]
```

## Framework-Specific Patterns

### Module-Based Docker Optimization

NestJS modules create a dependency graph at startup. Lazy-loading modules with `LazyModuleLoader` reduces startup time in containers:

```typescript
// main.ts
const app = await NestFactory.create(AppModule, {
  logger: ["error", "warn", "log"],
});
```

Set production-appropriate log levels to reduce I/O overhead in containers.

### Swagger Spec at Build Time

```dockerfile
# In builder stage, after npm run build:
RUN node -e "
  const { NestFactory } = require('@nestjs/core');
  const { SwaggerModule, DocumentBuilder } = require('@nestjs/swagger');
  const { AppModule } = require('./dist/app.module');
  (async () => {
    const app = await NestFactory.create(AppModule, { logger: false });
    const config = new DocumentBuilder().setTitle('API').build();
    const doc = SwaggerModule.createDocument(app, config);
    require('fs').writeFileSync('openapi.json', JSON.stringify(doc));
    await app.close();
  })();
"
```

### Graceful Shutdown

```typescript
app.enableShutdownHooks();
```

NestJS `enableShutdownHooks()` handles `SIGTERM` from Docker and calls `OnModuleDestroy` on all modules. This closes database connections and completes in-flight requests.

## Scaffolder Patterns

```yaml
patterns:
  dockerfile: "Dockerfile"
  dockerignore: ".dockerignore"
```

## Additional Dos

- DO use three-stage builds: compile, prod deps, runtime
- DO call `enableShutdownHooks()` for graceful container shutdown
- DO set production log levels to reduce container I/O
- DO use `npm ci --omit=dev` for production-only dependencies

## Additional Don'ts

- DON'T include `nest-cli.json` or `tsconfig.json` in the runtime image
- DON'T use `nest start` in production -- use `node dist/main.js` directly
- DON'T run as root -- create an `app` user
- DON'T copy `test/` or `src/` into the production image
