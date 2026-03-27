# Docker Compose with Kubernetes

> Extends `modules/container-orchestration/docker-compose.md` with Kubernetes local development patterns.
> Generic Docker Compose conventions (service definitions, networking, volume mounts) are NOT repeated here.

## Integration Setup

```yaml
# compose.yaml -- local development environment mirroring Kubernetes
services:
  app:
    build: .
    ports:
      - "8080:8080"
    environment:
      - APP_ENV=development
    depends_on:
      postgres:
        condition: service_healthy

  postgres:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: app
      POSTGRES_USER: app
      POSTGRES_PASSWORD: secret
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app"]
      interval: 5s
      timeout: 3s
      retries: 5
    volumes:
      - pgdata:/var/lib/postgresql/data

volumes:
  pgdata:
```

## Framework-Specific Patterns

### Local Kubernetes-Like Service Mesh

```yaml
services:
  app:
    build: .
    ports:
      - "8080:8080"
    environment:
      - SERVICE_A_URL=http://service-a:8081
      - SERVICE_B_URL=http://service-b:8082
    networks:
      - app-network

  service-a:
    build: ../service-a
    ports:
      - "8081:8081"
    networks:
      - app-network

  service-b:
    build: ../service-b
    ports:
      - "8082:8082"
    networks:
      - app-network

networks:
  app-network:
    driver: bridge
```

Docker Compose service names act as DNS hostnames, mirroring Kubernetes Service DNS (`service-name.namespace.svc.cluster.local`). This lets developers test inter-service communication locally.

### Kompose Conversion

```bash
# Convert Docker Compose to Kubernetes manifests
kompose convert -f compose.yaml -o k8s/

# Generated files:
# k8s/app-deployment.yaml
# k8s/app-service.yaml
# k8s/postgres-deployment.yaml
# k8s/postgres-service.yaml
```

Kompose translates Docker Compose files into Kubernetes resources. Use it as a starting point -- the generated manifests need tuning (resource limits, probes, secrets).

### Infrastructure Services for Integration Testing

```yaml
services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  localstack:
    image: localstack/localstack:latest
    ports:
      - "4566:4566"
    environment:
      - SERVICES=s3,sqs,dynamodb

  mailhog:
    image: mailhog/mailhog:latest
    ports:
      - "1025:1025"
      - "8025:8025"
```

Run infrastructure dependencies locally that mirror Kubernetes-deployed services. This avoids the need for a full Kubernetes cluster during development.

## Scaffolder Patterns

```yaml
patterns:
  compose: "compose.yaml"
  compose_test: "compose.test.yaml"
```

## Additional Dos

- DO use Docker Compose for local development that mirrors Kubernetes service topology
- DO use `depends_on` with `condition: service_healthy` for startup ordering
- DO use Kompose as a starting point for converting Compose to Kubernetes manifests
- DO name services to match Kubernetes Service names for URL compatibility

## Additional Don'ts

- DON'T deploy Docker Compose to production -- it is for local development only
- DON'T rely on Kompose output without tuning -- it does not generate resource limits, probes, or secrets
- DON'T use Docker Compose networking as a substitute for Kubernetes NetworkPolicies testing
- DON'T hardcode ports -- use environment variables that match Kubernetes Service ports
