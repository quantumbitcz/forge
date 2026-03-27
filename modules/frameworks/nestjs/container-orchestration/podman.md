# Podman with NestJS

> Extends `modules/container-orchestration/podman.md` with NestJS containerization patterns.
> Generic Podman conventions (rootless containers, pod definitions, systemd integration) are NOT repeated here.

## Integration Setup

```bash
podman build -t nestjs-app:latest .
podman run -d --name nestjs-app -p 3000:3000 -e NODE_ENV=production nestjs-app:latest
```

## Framework-Specific Patterns

### Pod with Database

```bash
podman pod create --name nestjs-pod -p 3000:3000 -p 5432:5432

podman run -d --pod nestjs-pod --name postgres \
  -e POSTGRES_DB=app -e POSTGRES_USER=app -e POSTGRES_PASSWORD=secret \
  postgres:16-alpine

podman run -d --pod nestjs-pod --name nestjs-app \
  -e DATABASE_URL=postgresql://app:secret@localhost:5432/app \
  -e NODE_ENV=production \
  nestjs-app:latest
```

Podman pods share a network namespace. NestJS connects to PostgreSQL via `localhost`.

### Quadlet Integration

```ini
[Container]
Image=registry.example.com/nestjs-app:latest
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
buildah copy builder . /app/
buildah run builder -- sh -c 'cd /app && npm run build'

buildah from --name deps node:22-slim
buildah copy deps /app/package*.json /app/
buildah run deps -- sh -c 'cd /app && npm ci --omit=dev'

buildah from --name runtime node:22-slim
buildah copy --from deps runtime /app/node_modules/ /app/node_modules/
buildah copy --from builder runtime /app/dist/ /app/dist/
buildah copy runtime /app/package.json /app/
buildah config --cmd '["node", "dist/main.js"]' --workingdir /app runtime
buildah commit runtime nestjs-app:latest
```

### TypeORM Migration

```bash
podman run --rm --pod nestjs-pod \
  -e DATABASE_URL=postgresql://app:secret@localhost:5432/app \
  nestjs-app:latest npx typeorm migration:run -d dist/data-source.js
```

## Scaffolder Patterns

```yaml
patterns:
  quadlet: "deploy/nestjs-app.container"
```

## Additional Dos

- DO use Podman pods for NestJS + database development environments
- DO use Quadlet for systemd-managed production deployments
- DO compile TypeScript before building the image -- run `node dist/main.js`
- DO use `npm ci --omit=dev` in a separate stage for production-only dependencies

## Additional Don'ts

- DON'T use `ts-node` or `nest start --watch` in production
- DON'T include `devDependencies` in the production image
- DON'T skip `--pod` when running with a database -- they need shared networking
- DON'T use `--privileged`
