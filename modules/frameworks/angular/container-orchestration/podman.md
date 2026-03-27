# Podman with Angular

> Extends `modules/container-orchestration/podman.md` with Angular SPA containerization patterns.
> Generic Podman conventions (rootless containers, pod definitions, systemd integration) are NOT repeated here.

## Integration Setup

```bash
podman build -t angular-app:latest .
podman run -d --name angular-app -p 8080:8080 angular-app:latest
```

## Framework-Specific Patterns

### Multi-Stage Dockerfile

```dockerfile
FROM node:22-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npx ng build --configuration=production

FROM nginx:alpine
COPY --from=builder /app/dist/angular-app/browser/ /usr/share/nginx/html/
COPY nginx.conf /etc/nginx/conf.d/default.conf

USER 1001
EXPOSE 8080
```

Angular's production build output lands in `dist/{project-name}/browser/`. The `--configuration=production` flag enables AOT compilation, tree-shaking, and minification.

### Nginx Configuration for Angular Routing

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

Angular's router requires `try_files` fallback to `index.html`. Nginx listens on 8080 for rootless Podman compatibility.

### Buildah Build

```bash
buildah from --name builder node:22-slim
buildah copy builder . /app/
buildah run builder -- sh -c 'cd /app && npm ci && npx ng build --configuration=production'

buildah from --name runtime nginx:alpine
buildah copy --from builder runtime /app/dist/angular-app/browser/ /usr/share/nginx/html/
buildah copy runtime nginx.conf /etc/nginx/conf.d/default.conf
buildah commit runtime angular-app:latest
```

### Development Pod with API Backend

```bash
podman pod create --name angular-dev-pod -p 4200:4200 -p 8080:8080

podman run -d --pod angular-dev-pod --name api \
  api-server:latest

podman run -d --pod angular-dev-pod --name angular-app \
  -v ./src:/app/src:Z \
  angular-dev:latest npx ng serve --host 0.0.0.0
```

### Quadlet Integration

```ini
[Container]
Image=registry.example.com/angular-app:latest
PublishPort=8080:8080

[Service]
Restart=always

[Install]
WantedBy=default.target
```

## Scaffolder Patterns

```yaml
patterns:
  quadlet: "deploy/angular-app.container"
  nginx_conf: "nginx.conf"
```

## Additional Dos

- DO use `--configuration=production` for AOT, tree-shaking, and minification
- DO configure `try_files` fallback for Angular's client-side routing
- DO use `:Z` volume flag for SELinux compatibility in rootless Podman
- DO listen on port 8080 for rootless compatibility

## Additional Don'ts

- DON'T include `node_modules/` or source files in the production image
- DON'T use `ng serve` in production containers
- DON'T skip cache headers for hashed asset files
- DON'T listen on port 80 -- rootless Podman cannot bind to privileged ports
