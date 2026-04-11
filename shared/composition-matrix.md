# Module Composition Matrix

Defines which module combinations are valid and their load order. The most specific module wins when conventions conflict.

## Composition Order (most specific wins)

```
variant > framework-binding > framework > language > code-quality > generic-layer > testing
```

## Valid Combinations

| Language | Framework | Testing | Variant | Notes |
|----------|-----------|---------|---------|-------|
| kotlin | spring | kotest | hexagonal | Default Kotlin+Spring combo |
| kotlin | spring | junit5 | — | Alternative test framework |
| kotlin | jetpack-compose | junit5 | — | Android UI |
| java | spring | junit5 | — | Java+Spring default |
| typescript | react | vitest | — | React SPA |
| typescript | nextjs | vitest | — | Next.js SSR |
| typescript | angular | jest | — | Angular default |
| typescript | vue | vitest | — | Vue 3 + Composition API |
| typescript | svelte | vitest | — | Svelte 5 standalone |
| typescript | sveltekit | vitest | — | SvelteKit full-stack |
| typescript | nestjs | jest | — | NestJS backend |
| typescript | express | jest | — | Express.js API |
| python | fastapi | pytest | — | FastAPI default |
| python | django | pytest | — | Django default |
| rust | axum | rust-test | — | Axum web framework |
| swift | swiftui | xctest | — | SwiftUI default |
| swift | vapor | xctest | — | Vapor server-side |
| go | go-stdlib | go-testing | — | Go standard library |
| go | gin | go-testing | — | Gin HTTP framework |
| c | embedded | — | — | No test framework (embedded) |
| csharp | aspnet | xunit-nunit | — | ASP.NET default |
| null | k8s | — | — | Infrastructure only |

## Invalid Combinations

| Combination | Reason |
|-------------|--------|
| `language: null` + any non-k8s framework | Frameworks require a language |
| `react` + `angular` | Competing frontend frameworks |
| `nextjs` + `sveltekit` | Competing meta-frameworks |
| `spring` + `fastapi` | Cross-language framework conflict |

## Crosscutting Modules

These modules can be added to any valid language+framework combination:

| Module | Category | Requires |
|--------|----------|----------|
| postgresql, mysql, mongodb, redis, elasticsearch | database | — |
| flyway, alembic, prisma-migrate | migrations | matching database |
| rest, graphql, grpc, websocket | api_protocol | — |
| rabbitmq, kafka, nats | messaging | — |
| redis, memcached | caching | — |
| elasticsearch, meilisearch | search | — |
| s3, gcs, minio | storage | — |
| oauth2, jwt, session | auth | — |
| prometheus, opentelemetry, datadog | observability | — |

## Soft Cap

Convention stack soft cap: **12 files/component**. Beyond this, the orchestrator should log a WARNING and consider splitting into multiple components.
