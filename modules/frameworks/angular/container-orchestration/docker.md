# Docker with Angular

> Extends `modules/container-orchestration/docker.md` with Angular containerization patterns.
> Generic Docker conventions (multi-stage builds, layer caching, security scanning) are NOT repeated here.

## Integration Setup

### Multi-Stage Dockerfile (ng build to nginx)

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
RUN npx ng build --configuration production

# Stage 3: Serve static files
FROM nginx:alpine
COPY --from=build /app/dist/app/browser /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD wget -qO- http://localhost:80/ || exit 1
```

Note the output path: Angular 17+ outputs to `dist/{project}/browser/` for the client bundle.

## Framework-Specific Patterns

### Nginx Configuration for Angular Routing

```nginx
# nginx.conf
server {
    listen 80;
    root /usr/share/nginx/html;
    index index.html;

    # Angular routing -- serve index.html for all routes
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Cache hashed assets aggressively
    location ~* \.[0-9a-f]{16}\.(js|css)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    gzip on;
    gzip_types text/css application/javascript application/json image/svg+xml;
    gzip_min_length 256;
}
```

Angular's output hashing appends content hashes to filenames. Match these with a regex for aggressive caching.

### Angular Universal SSR Docker

```dockerfile
# Stage 1: Build
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npx ng build --configuration production

# Stage 2: Run SSR server
FROM node:22-alpine
WORKDIR /app
COPY --from=build /app/dist/app ./dist/app
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD wget -qO- http://localhost:4000/ || exit 1

CMD ["node", "dist/app/server/server.mjs"]
```

SSR apps need Node.js in the runtime image. The server bundle is at `dist/{project}/server/server.mjs`.

### Runtime Environment Configuration

```typescript
// src/environments/environment.ts
export const environment = {
  apiUrl: (window as any).__env?.API_URL || "/api",
};
```

```html
<!-- index.html (injected at runtime via entrypoint script) -->
<script>
  window.__env = { API_URL: "__API_URL__" };
</script>
```

Angular bakes environment files at build time. For runtime config, use `window.__env` injection or fetch config from an API endpoint at startup.

## Scaffolder Patterns

```yaml
patterns:
  dockerfile: "Dockerfile"
  dockerignore: ".dockerignore"
  nginx_conf: "nginx.conf"
```

## Additional Dos

- DO copy from `dist/{project}/browser/` for SPA builds -- Angular 17+ uses this path
- DO include `try_files $uri $uri/ /index.html` for Angular Router's client-side routing
- DO use content-hash regex for aggressive asset caching
- DO use Node.js runtime image for Angular Universal SSR deployments

## Additional Don'ts

- DON'T include `node_modules` in the final SPA image -- only the built assets
- DON'T use Node.js to serve static Angular builds -- nginx is faster and lighter
- DON'T rely on `environment.ts` for runtime configuration -- it's baked at build time
- DON'T copy from `dist/` root -- use the correct `dist/{project}/browser/` output path
