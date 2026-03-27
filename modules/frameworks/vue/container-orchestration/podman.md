# Podman with Vue

> Extends `modules/container-orchestration/podman.md` with Vue.js SPA containerization patterns.
> Generic Podman conventions (rootless containers, pod definitions, systemd integration) are NOT repeated here.

## Integration Setup

```bash
podman build -t vue-app:latest .
podman run -d --name vue-app -p 8080:8080 vue-app:latest
```

## Framework-Specific Patterns

### Multi-Stage Dockerfile

```dockerfile
FROM node:22-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=builder /app/dist/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf

USER 1001
EXPOSE 8080
```

Vite builds Vue to `dist/` by default. The production image contains only static assets served by Nginx.

### Nginx Configuration for Vue Router

```nginx
server {
    listen 8080;
    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    location /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

Vue Router in `history` mode requires `try_files` fallback to `index.html`. Nginx listens on 8080 for rootless compatibility.

### Buildah Build

```bash
buildah from --name builder node:22-slim
buildah copy builder . /app/
buildah run builder -- sh -c 'cd /app && npm ci && npm run build'

buildah from --name runtime nginx:alpine
buildah copy --from builder runtime /app/dist/ /usr/share/nginx/html/
buildah copy runtime nginx.conf /etc/nginx/conf.d/default.conf
buildah commit runtime vue-app:latest
```

### Development Pod with API Backend

```bash
podman pod create --name vue-dev-pod -p 5173:5173 -p 8080:8080

podman run -d --pod vue-dev-pod --name api \
  api-server:latest

podman run -d --pod vue-dev-pod --name vue-app \
  -v ./src:/app/src:Z \
  vue-dev:latest npm run dev -- --host 0.0.0.0
```

### Quadlet Integration

```ini
[Container]
Image=registry.example.com/vue-app:latest
PublishPort=8080:8080

[Service]
Restart=always

[Install]
WantedBy=default.target
```

## Scaffolder Patterns

```yaml
patterns:
  quadlet: "deploy/vue-app.container"
  nginx_conf: "nginx.conf"
```

## Additional Dos

- DO use Nginx or Caddy to serve Vite-built assets
- DO configure `try_files` fallback for Vue Router history mode
- DO use `:Z` volume flag for SELinux compatibility in rootless Podman
- DO listen on port 8080 for rootless compatibility

## Additional Don'ts

- DON'T include `node_modules/` or source files in the production image
- DON'T use `npm run dev` in production containers
- DON'T skip cache headers for Vite's hashed asset files
- DON'T listen on port 80 -- rootless Podman cannot bind to privileged ports
