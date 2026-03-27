# Docker with Svelte 5 (Standalone SPA)

> Extends `modules/container-orchestration/docker.md` with Svelte 5 static build containerization.
> Generic Docker conventions (multi-stage builds, layer caching, security scanning) are NOT repeated here.

## Integration Setup

### Multi-Stage Dockerfile (Vite build to nginx)

```dockerfile
# Stage 1: Install dependencies
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

# Stage 2: Build the application
FROM node:22-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

# Stage 3: Serve static files
FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD wget -qO- http://localhost:80/ || exit 1
```

## Framework-Specific Patterns

### Bun Build Stage

```dockerfile
FROM oven/bun:latest AS deps
WORKDIR /app
COPY package.json bun.lockb ./
RUN bun install --frozen-lockfile

FROM oven/bun:latest AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN bun run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
```

### Nginx Configuration for SPA Routing

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

Standalone Svelte SPAs use client-side routing (e.g., `svelte-routing`). The `try_files` fallback ensures all routes serve `index.html`.

### Runtime Environment Injection

```html
<!-- index.html -->
<script>
  window.__env = { API_URL: "__API_URL__" };
</script>
```

```dockerfile
# inject-env.sh
#!/bin/sh
for envvar in $(env | grep '^APP_' | cut -d= -f1); do
    sed -i "s|__${envvar}__|$(printenv "$envvar")|g" /usr/share/nginx/html/index.html
done
exec nginx -g "daemon off;"
```

Vite bakes `VITE_*` env vars at build time. For runtime config, use placeholder injection at container startup.

## Scaffolder Patterns

```yaml
patterns:
  dockerfile: "Dockerfile"
  dockerignore: ".dockerignore"
  nginx_conf: "nginx.conf"
```

## Additional Dos

- DO use multi-stage builds -- the final nginx image is ~40MB
- DO include `try_files $uri $uri/ /index.html` for client-side routing
- DO cache `/assets/` aggressively -- Vite fingerprints filenames
- DO enable gzip for text-based assets

## Additional Don'ts

- DON'T include `node_modules` in the final image -- only the built `dist/`
- DON'T use Node.js to serve static files -- nginx is faster and lighter
- DON'T rely on `VITE_*` env vars for runtime configuration -- they're baked at build time
