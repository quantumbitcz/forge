# Docker with SvelteKit

> Extends `modules/container-orchestration/docker.md` with SvelteKit adapter-node containerization.
> Generic Docker conventions (multi-stage builds, layer caching, security scanning) are NOT repeated here.

## Integration Setup

### adapter-node Dockerfile

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

# Stage 3: Run the server
FROM node:22-alpine
WORKDIR /app

RUN addgroup -S sveltekit && adduser -S sveltekit -G sveltekit

COPY --from=build /app/build ./build
COPY --from=build /app/package.json ./

USER sveltekit:sveltekit

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD wget -qO- http://localhost:3000/ || exit 1

ENV PORT=3000
ENV NODE_ENV=production
CMD ["node", "build/index.js"]
```

SvelteKit's `adapter-node` produces a self-contained `build/` directory. Only `build/` and `package.json` are needed at runtime -- no `node_modules` required (dependencies are bundled).

## Framework-Specific Patterns

### Static Adapter (nginx)

```dockerfile
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```

Use `adapter-static` for pure static output served by nginx. Requires `fallback: 'index.html'` in adapter config for SPA behavior.

### Environment Variables

```javascript
// svelte.config.js
import adapter from "@sveltejs/adapter-node";
export default {
  kit: {
    adapter: adapter({
      envPrefix: "APP_",
    }),
  },
};
```

```dockerfile
ENV APP_API_URL=https://api.example.com
ENV APP_PUBLIC_SITE_URL=https://example.com
CMD ["node", "build/index.js"]
```

SvelteKit reads `$env/dynamic/private` and `$env/dynamic/public` from environment variables at runtime. Use `envPrefix` to namespace your variables.

## Scaffolder Patterns

```yaml
patterns:
  dockerfile: "Dockerfile"
  dockerignore: ".dockerignore"
  nginx_conf: "nginx.conf"
```

## Additional Dos

- DO use `adapter-node` for Docker deployments -- it produces a self-contained server
- DO use `$env/dynamic/*` for runtime environment configuration in SvelteKit
- DO run as a non-root user in the final image
- DO set `NODE_ENV=production` in the runtime image

## Additional Don'ts

- DON'T copy `node_modules` into the production image -- `adapter-node` bundles dependencies
- DON'T use nginx for SSR SvelteKit apps -- it requires Node.js at runtime
- DON'T use `$env/static/*` for values that change per environment -- those are baked at build time
