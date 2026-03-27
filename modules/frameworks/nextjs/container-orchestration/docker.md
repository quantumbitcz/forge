# Docker with Next.js

> Extends `modules/container-orchestration/docker.md` with Next.js containerization patterns.
> Generic Docker conventions (multi-stage builds, layer caching, security scanning) are NOT repeated here.

## Integration Setup

### Standalone Output Dockerfile

```dockerfile
FROM node:22-slim AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM node:22-slim AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM node:22-slim
WORKDIR /app

RUN addgroup --system nextjs && adduser --system --group nextjs

COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nextjs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nextjs /app/.next/static ./.next/static

USER nextjs:nextjs

EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD node -e "fetch('http://localhost:3000/api/health').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"

CMD ["node", "server.js"]
```

Requires `output: 'standalone'` in `next.config.js`. The standalone output includes only the files needed for production -- no `node_modules` copy required.

## Framework-Specific Patterns

### next.config.js for Docker

```javascript
// next.config.js
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: "standalone",
};
module.exports = nextConfig;
```

`output: 'standalone'` creates a self-contained `server.js` with minimal `node_modules`. Image size drops from ~1GB to ~100-200MB.

### ISR Cache Volume

```dockerfile
# For self-hosted ISR, persist the cache
VOLUME ["/app/.next/cache"]
```

Incremental Static Regeneration writes cache files to `.next/cache`. Mount a volume to persist cache across container restarts.

### Static Export

```dockerfile
# For static export (no server needed)
FROM node:22-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/out /usr/share/nginx/html
```

Use `output: 'export'` in `next.config.js` for fully static sites. Serve with nginx -- no Node.js runtime needed.

## Scaffolder Patterns

```yaml
patterns:
  dockerfile: "Dockerfile"
  dockerignore: ".dockerignore"
  next_config: "next.config.js"
```

## Additional Dos

- DO use `output: 'standalone'` for minimal Docker images
- DO copy `public/` and `.next/static` separately from the standalone output
- DO persist `.next/cache` as a volume for ISR-enabled deployments
- DO set `HOSTNAME="0.0.0.0"` to listen on all interfaces in containers

## Additional Don'ts

- DON'T copy `node_modules/` into the runtime image when using standalone output
- DON'T use `next start` in Docker -- use `node server.js` from standalone output
- DON'T run as root -- create a `nextjs` user
- DON'T include `.next/cache` in the image layers -- mount as a volume for ISR
