# Podman with Next.js

> Extends `modules/container-orchestration/podman.md` with Next.js containerization patterns.
> Generic Podman conventions (rootless containers, pod definitions, systemd integration) are NOT repeated here.

## Integration Setup

```bash
podman build -t nextjs-app:latest .
podman run -d --name nextjs-app -p 3000:3000 -e NODE_ENV=production nextjs-app:latest
```

## Framework-Specific Patterns

### Standalone Output Build

```javascript
// next.config.js
module.exports = {
  output: "standalone",
};
```

```dockerfile
FROM node:22-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:22-slim
WORKDIR /app
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

USER 1001
EXPOSE 3000
CMD ["node", "server.js"]
```

Next.js `output: "standalone"` produces a self-contained `server.js` with only the required `node_modules`. This dramatically reduces image size.

### Development Pod with Database

```bash
podman pod create --name nextjs-pod -p 3000:3000 -p 5432:5432

podman run -d --pod nextjs-pod --name postgres \
  -e POSTGRES_DB=app -e POSTGRES_USER=app -e POSTGRES_PASSWORD=secret \
  postgres:16-alpine

podman run -d --pod nextjs-pod --name nextjs-app \
  -e DATABASE_URL=postgresql://app:secret@localhost:5432/app \
  -e NODE_ENV=production \
  nextjs-app:latest
```

### Quadlet Integration

```ini
[Container]
Image=registry.example.com/nextjs-app:latest
PublishPort=3000:3000
Environment=NODE_ENV=production
Environment=HOSTNAME=0.0.0.0
Secret=db-url,type=env,target=DATABASE_URL

[Service]
Restart=always

[Install]
WantedBy=default.target
```

### Buildah with Standalone Output

```bash
buildah from --name builder node:22-slim
buildah copy builder . /app/
buildah run builder -- sh -c 'cd /app && npm ci && npm run build'

buildah from --name runtime node:22-slim
buildah copy --from builder runtime /app/.next/standalone/ /app/
buildah copy --from builder runtime /app/.next/static/ /app/.next/static/
buildah copy --from builder runtime /app/public/ /app/public/
buildah config --cmd '["node", "server.js"]' --workingdir /app runtime
buildah commit runtime nextjs-app:latest
```

## Scaffolder Patterns

```yaml
patterns:
  quadlet: "deploy/nextjs-app.container"
```

## Additional Dos

- DO use `output: "standalone"` in `next.config.js` for minimal image size
- DO copy `.next/static` and `public` alongside the standalone server
- DO set `HOSTNAME=0.0.0.0` to bind to all interfaces in the container
- DO use Podman pods for local development with databases

## Additional Don'ts

- DON'T include full `node_modules/` -- standalone output bundles only required dependencies
- DON'T use `npm run dev` in production containers
- DON'T forget to copy `public/` and `.next/static` -- they are not included in standalone output
- DON'T listen on port 80 -- rootless Podman cannot bind to privileged ports
