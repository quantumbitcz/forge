# Podman with React

> Extends `modules/container-orchestration/podman.md` with React SPA containerization patterns.
> Generic Podman conventions (rootless containers, pod definitions, systemd integration) are NOT repeated here.

## Integration Setup

```bash
podman build -t react-app:latest .
podman run -d --name react-app -p 8080:8080 react-app:latest
```

## Framework-Specific Patterns

### Multi-Stage Build with Buildah

```bash
# Build stage
buildah from --name builder node:22-slim
buildah copy builder package*.json /app/
buildah run builder -- sh -c 'cd /app && npm ci'
buildah copy builder src/ /app/src/
buildah copy builder public/ /app/public/
buildah copy builder vite.config.ts tsconfig.json index.html /app/
buildah run builder -- sh -c 'cd /app && npm run build'

# Runtime stage -- serve static files with nginx
buildah from --name runtime nginx:alpine
buildah copy --from builder runtime /app/dist/ /usr/share/nginx/html/
buildah copy runtime nginx.conf /etc/nginx/conf.d/default.conf
buildah commit runtime react-app:latest
```

### Nginx Configuration for SPA Routing

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

React SPAs need `try_files` fallback to `index.html` for client-side routing. Nginx listens on port 8080 (non-privileged) for rootless compatibility.

### Development Pod with API Backend

```bash
podman pod create --name react-dev-pod -p 3000:3000 -p 8080:8080

podman run -d --pod react-dev-pod --name api \
  -e NODE_ENV=development \
  api-server:latest

podman run -d --pod react-dev-pod --name react-app \
  -v ./src:/app/src:Z \
  react-dev:latest npm run dev
```

The `:Z` flag relabels volume mounts for SELinux compatibility in rootless mode.

### Quadlet Integration

```ini
[Container]
Image=registry.example.com/react-app:latest
PublishPort=8080:8080

[Service]
Restart=always

[Install]
WantedBy=default.target
```

## Scaffolder Patterns

```yaml
patterns:
  quadlet: "deploy/react-app.container"
  nginx_conf: "nginx.conf"
```

## Additional Dos

- DO use Nginx or Caddy to serve built assets -- never serve React builds with Node.js in production
- DO configure `try_files` fallback for client-side routing
- DO use `:Z` volume flag for SELinux compatibility in rootless Podman
- DO listen on port 8080 for rootless compatibility

## Additional Don'ts

- DON'T include `node_modules/` or source files in the production image -- only built assets
- DON'T use `npm run dev` in production containers
- DON'T skip cache headers for hashed asset files
- DON'T listen on port 80 -- rootless Podman cannot bind to privileged ports
