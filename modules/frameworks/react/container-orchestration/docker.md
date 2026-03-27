# Docker with React

> Extends `modules/container-orchestration/docker.md` with React + Vite containerization patterns.
> Generic Docker conventions (multi-stage builds, layer caching, security scanning) are NOT repeated here.

## Integration Setup

### Multi-Stage Dockerfile (Node build, nginx serve)

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

    # SPA fallback -- serve index.html for all routes
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Cache static assets aggressively (Vite hashes filenames)
    location /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Gzip compression
    gzip on;
    gzip_types text/css application/javascript application/json image/svg+xml;
    gzip_min_length 256;
}
```

The `try_files` directive is essential for React Router's client-side routing. Without it, direct navigation to any route other than `/` returns 404.

### Environment Variables at Runtime

```dockerfile
# inject-env.sh (entrypoint script)
#!/bin/sh
# Replace placeholders in built JS with runtime env vars
for envvar in $(env | grep '^REACT_APP_' | cut -d= -f1); do
    sed -i "s|__${envvar}__|$(printenv "$envvar")|g" /usr/share/nginx/html/assets/*.js
done
exec nginx -g "daemon off;"
```

```dockerfile
ENTRYPOINT ["/docker-entrypoint.d/inject-env.sh"]
```

Vite bakes `VITE_*` env vars at build time. For runtime configuration, use placeholder replacement or load config from an API endpoint.

## Scaffolder Patterns

```yaml
patterns:
  dockerfile: "Dockerfile"
  dockerignore: ".dockerignore"
  nginx_conf: "nginx.conf"
```

## Additional Dos

- DO use multi-stage builds -- the final nginx image is ~40MB vs ~1GB with Node
- DO include `try_files $uri $uri/ /index.html` for SPA client-side routing
- DO set `Cache-Control: public, immutable` on `/assets/` -- Vite fingerprints filenames
- DO enable gzip for text-based assets in the nginx config

## Additional Don'ts

- DON'T include `node_modules` in the final image -- only the built `dist/` folder
- DON'T use Node.js to serve static files in production -- nginx is faster and lighter
- DON'T rely on `VITE_*` env vars for runtime configuration -- they're baked at build time
- DON'T run nginx as root -- use `nginx:alpine` which runs as non-root by default in recent versions
