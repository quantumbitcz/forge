# Podman with Express

> Extends `modules/container-orchestration/podman.md` with Express/Node.js containerization patterns.
> Generic Podman conventions (rootless containers, pod definitions, systemd integration) are NOT repeated here.

## Integration Setup

```bash
podman build -t express-app:latest .
podman run -d --name express-app -p 3000:3000 -e NODE_ENV=production express-app:latest
```

## Framework-Specific Patterns

### Pod with Database

```bash
podman pod create --name express-pod -p 3000:3000 -p 5432:5432

podman run -d --pod express-pod --name postgres \
  -e POSTGRES_DB=app -e POSTGRES_USER=app -e POSTGRES_PASSWORD=secret \
  postgres:16-alpine

podman run -d --pod express-pod --name express-app \
  -e DATABASE_URL=postgresql://app:secret@localhost:5432/app \
  -e NODE_ENV=production \
  express-app:latest
```

Podman pods share a network namespace. Express connects to PostgreSQL via `localhost`.

### Quadlet Integration

```ini
[Container]
Image=registry.example.com/express-app:latest
PublishPort=3000:3000
Environment=NODE_ENV=production
Secret=db-url,type=env,target=DATABASE_URL

[Service]
Restart=always

[Install]
WantedBy=default.target
```

### Buildah Multi-Stage Build

```bash
buildah from --name builder node:22-slim
buildah copy builder package*.json /app/
buildah run builder -- sh -c 'cd /app && npm ci'
buildah copy builder tsconfig.json /app/
buildah copy builder src/ /app/src/
buildah run builder -- sh -c 'cd /app && npm run build'

buildah from --name deps node:22-slim
buildah copy deps /app/package*.json /app/
buildah run deps -- sh -c 'cd /app && npm ci --omit=dev'

buildah from --name runtime node:22-slim
buildah copy --from deps runtime /app/node_modules/ /app/node_modules/
buildah copy --from builder runtime /app/dist/ /app/dist/
buildah copy runtime /app/package.json /app/
buildah config --cmd '["node", "dist/index.js"]' --workingdir /app runtime
buildah commit runtime express-app:latest
```

### Prisma Migration

```bash
podman run --rm --pod express-pod \
  -e DATABASE_URL=postgresql://app:secret@localhost:5432/app \
  express-app:latest npx prisma migrate deploy
```

### Graceful Shutdown

```typescript
process.on("SIGTERM", () => {
  server.close(() => {
    process.exit(0);
  });
});
```

Podman sends `SIGTERM` on container stop. Close the HTTP server gracefully to finish in-flight requests.

## Scaffolder Patterns

```yaml
patterns:
  quadlet: "deploy/express-app.container"
```

## Additional Dos

- DO use Podman pods for Express + database development environments
- DO use Quadlet for systemd-managed production deployments
- DO handle `SIGTERM` for graceful shutdown
- DO use `npm ci --omit=dev` in a separate Buildah stage

## Additional Don'ts

- DON'T include `devDependencies` in the production image
- DON'T use `npm start` when it just calls `node` -- invoke `node` directly
- DON'T skip `--pod` when running with a database
- DON'T use `--privileged`
