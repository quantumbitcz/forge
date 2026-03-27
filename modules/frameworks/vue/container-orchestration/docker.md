# Docker with Vue / Nuxt

> Extends `modules/container-orchestration/docker.md` with Vue 3 / Nuxt 3 containerization patterns.
> Generic Docker conventions (multi-stage builds, layer caching, security scanning) are NOT repeated here.

## Integration Setup

### Nuxt SSR (adapter-node)

```dockerfile
# Stage 1: Install dependencies
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

# Stage 2: Build
FROM node:22-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

# Stage 3: Run SSR server
FROM node:22-alpine
WORKDIR /app

RUN addgroup -S nuxt && adduser -S nuxt -G nuxt

COPY --from=build /app/.output ./.output

USER nuxt:nuxt

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD wget -qO- http://localhost:3000/ || exit 1

CMD ["node", ".output/server/index.mjs"]
```

Nuxt's default `adapter-node` produces a self-contained server in `.output/`. No `node_modules` needed at runtime -- Nitro bundles dependencies.

### Static Vue SPA (Vite build to nginx)

```dockerfile
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```

## Framework-Specific Patterns

### Nginx for Vue Router History Mode

```nginx
# nginx.conf
server {
    listen 80;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    gzip on;
    gzip_types text/css application/javascript application/json image/svg+xml;
    gzip_min_length 256;
}
```

Vue Router in history mode requires `try_files` to serve `index.html` for all routes. Without it, direct navigation to any route returns 404.

### Nuxt Runtime Configuration

```typescript
// nuxt.config.ts
export default defineNuxtConfig({
  runtimeConfig: {
    apiSecret: "", // server-only, from NUXT_API_SECRET env var
    public: {
      apiBase: "", // client+server, from NUXT_PUBLIC_API_BASE env var
    },
  },
});
```

```dockerfile
ENV NUXT_API_SECRET=changeme
ENV NUXT_PUBLIC_API_BASE=https://api.example.com
CMD ["node", ".output/server/index.mjs"]
```

Nuxt's `runtimeConfig` reads `NUXT_*` environment variables at startup. No build-time baking -- true runtime configuration.

## Scaffolder Patterns

```yaml
patterns:
  dockerfile: "Dockerfile"
  dockerignore: ".dockerignore"
  nginx_conf: "nginx.conf"
```

## Additional Dos

- DO use Nuxt's `.output/` directory for SSR -- it's self-contained (no `node_modules` needed)
- DO use `NUXT_*` env vars for runtime configuration -- they're read at startup, not build time
- DO include `try_files` in nginx for Vue Router history mode
- DO run as a non-root user in the final image

## Additional Don'ts

- DON'T copy `node_modules` into the Nuxt SSR production image -- `.output/` bundles everything
- DON'T use nginx for Nuxt SSR -- it requires Node.js to serve SSR pages
- DON'T use `nuxt dev` in Docker -- use the built `.output/server/index.mjs`
- DON'T hardcode API URLs in the build -- use `runtimeConfig` with env vars
