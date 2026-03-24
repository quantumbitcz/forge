# Crosscutting Module Layers & Multi-Service Architecture

**Date:** 2026-03-24
**Status:** Approved
**Scope:** 11 new module layers, 4 new frameworks, multi-service monorepo config, extended convention composition

## Problem

The current module system conflates framework choice with persistence, API protocol, messaging, caching, and observability choices. A Spring project always implies JPA/R2DBC + REST. There is no way to express "Spring + MongoDB + GraphQL + Kafka" or "Ktor + Exposed + gRPC" without duplicating entire convention files. Real-world projects — especially microservice monorepos — mix technologies per service.

## Design Goals

1. Decouple persistence, API protocol, messaging, caching, search, storage, auth, observability, and migrations from framework choice.
2. Support monorepos where each service has a different technology stack.
3. Maintain full backward compatibility — existing single-service configs work unchanged.
4. Follow the established pattern: generic module + framework-specific binding (same as `testing/`).
5. Keep convention composition predictable with a clear precedence order.

---

## 1. New Module Layer Architecture

### 1.1 Directory Structure

The existing 3-layer hierarchy (`language > framework > testing`) extends to 14 layers:

```
modules/
  languages/          # existing (9 files) — language-level idioms
  frameworks/         # existing (17 dirs) + 4 new — framework conventions
  testing/            # existing (11 files) — test framework patterns
  databases/          # NEW — database engine best practices
  persistence/        # NEW — ORM/mapping framework patterns
  migrations/         # NEW — schema migration tool patterns
  api-protocols/      # NEW — REST, GraphQL, gRPC, WebSocket
  messaging/          # NEW — event-driven / streaming patterns
  caching/            # NEW — cache strategy patterns
  search/             # NEW — full-text search patterns
  storage/            # NEW — object/file storage patterns
  auth/               # NEW — authentication/authorization patterns
  observability/      # NEW — metrics, tracing, logging patterns
```

Each new layer directory contains one `.md` file per technology:

```
modules/databases/
  postgresql.md
  mysql.md
  mongodb.md
  redis.md
  clickhouse.md
  sqlite.md
  dynamodb.md
  cassandra.md
```

### 1.2 Framework Bindings

Framework bindings live inside the framework module, following the existing `testing/` pattern. A binding EXTENDS the generic module — it adds framework-specific integration patterns on top.

```
modules/frameworks/spring/
  conventions.md                  # existing
  testing/kotest.md               # existing — extends modules/testing/kotest.md
  persistence/hibernate.md        # NEW — extends modules/persistence/hibernate.md
  persistence/exposed.md          # NEW — extends modules/persistence/exposed.md
  persistence/jooq.md             # NEW — extends modules/persistence/jooq.md
  persistence/koog.md             # NEW — extends modules/persistence/koog.md
  persistence/r2dbc.md            # NEW — extends modules/persistence/r2dbc.md
  databases/postgresql.md         # NEW — extends modules/databases/postgresql.md
  databases/mongodb.md            # NEW — extends modules/databases/mongodb.md
  api-protocols/rest.md           # NEW — extends modules/api-protocols/rest.md
  api-protocols/graphql.md        # NEW — extends modules/api-protocols/graphql.md
  api-protocols/grpc.md           # NEW — extends modules/api-protocols/grpc.md
  messaging/kafka.md              # NEW — extends modules/messaging/kafka.md
  messaging/rabbitmq.md           # NEW — extends modules/messaging/rabbitmq.md
  caching/caffeine.md             # NEW — extends modules/caching/caffeine.md
  caching/redis.md                # NEW — extends modules/caching/redis.md
  observability/micrometer.md     # NEW — extends modules/observability/micrometer.md
  observability/opentelemetry.md  # NEW — extends modules/observability/opentelemetry.md
  migrations/flyway.md            # NEW — extends modules/migrations/flyway.md
  migrations/liquibase.md         # NEW — extends modules/migrations/liquibase.md
  auth/oauth2.md                  # NEW — extends modules/auth/oauth2.md
  search/elasticsearch.md         # NEW — extends modules/search/elasticsearch.md
  storage/s3.md                   # NEW — extends modules/storage/s3.md
```

### 1.3 Convention Composition Order

Extended from the current order. Most specific wins on any conflicting rule:

```
variant > framework-binding > framework > language > generic-layer > testing
```

Where:
- `variant` = e.g., `modules/frameworks/spring/variants/kotlin.md`
- `framework-binding` = e.g., `modules/frameworks/spring/persistence/exposed.md` or `modules/frameworks/spring/testing/kotest.md`
- `framework` = e.g., `modules/frameworks/spring/conventions.md`
- `language` = e.g., `modules/languages/kotlin.md`
- `generic-layer` = e.g., `modules/persistence/exposed.md` or `modules/testing/kotest.md`
- `testing` = e.g., `modules/testing/kotest.md` (also a generic-layer, listed separately for backward compatibility documentation)

**Note:** The existing `framework-testing` position in CLAUDE.md is a specific case of `framework-binding`. All framework subdirectory bindings (`testing/`, `persistence/`, `messaging/`, etc.) share the same precedence level. When two framework-bindings conflict on the same rule (unlikely — they cover different concerns), the layer listed later in `components:` wins.

Multiple generic layers are loaded when multiple optional fields are set (e.g., `database: postgresql` + `persistence: exposed` + `messaging: kafka` loads three generic modules and their three framework bindings).

### 1.4 Convention Path Resolution (local-template.md)

Convention paths for new layers are **derived automatically** by PREFLIGHT — they do NOT require manual entries in `local-template.md`. The resolution algorithm:

```
For each field in components: (database, persistence, migrations, api_protocol, messaging, caching, search, storage, auth, observability):
  if field is set:
    generic_path  = ${CLAUDE_PLUGIN_ROOT}/modules/{layer}/{value}.md
    binding_path  = ${CLAUDE_PLUGIN_ROOT}/modules/frameworks/{framework}/{layer}/{value}.md
    if generic_path exists:  load it
    if binding_path exists:  load it (overrides generic on conflicts)
```

Existing `conventions_file`, `conventions_variant`, and `conventions_testing` paths in `local-template.md` continue to work unchanged. The new layers use automatic path derivation only — no template changes needed.

### 1.5 Markdown Convention Merge Semantics

When a framework-binding file and a generic module file both exist, they compose as follows:
- The agent reads BOTH files (generic first, then binding).
- **Additive sections** (Dos, Don'ts, Patterns) — the binding's entries are appended to the generic's.
- **Override sections** (Configuration, Integration Setup, Scaffolder Patterns) — the binding's content replaces the generic's for that section.
- **Rule of thumb for agents:** when the binding explicitly contradicts the generic (e.g., "use entity graphs" vs. "use batch fetching"), the binding wins. When the binding adds without contradicting, both apply.

---

## 2. Extended `components:` Config

### 2.1 Single-Service Config

The `dev-pipeline.local.md` config gains optional fields:

```yaml
components:
  language: kotlin
  framework: spring
  variant: kotlin
  testing: kotest
  # NEW optional fields (all optional, omit to skip):
  database: postgresql
  persistence: exposed
  migrations: flyway
  api_protocol: rest
  messaging: kafka
  caching: caffeine
  search: elasticsearch
  storage: s3
  auth: oauth2
  observability: opentelemetry
```

All new fields are optional. If omitted, the layer is not loaded. This maintains full backward compatibility with every existing project config.

### 2.2 Multi-Service Monorepo Config

For monorepos, the existing `components:` block is extended to hold named entries with `path:` and their own technology stacks. This is a natural evolution of the existing multi-component support in `state.json.components`:

```yaml
components:
  user-service:
    path: services/user-service
    language: kotlin
    framework: spring
    variant: kotlin
    testing: kotest
    database: postgresql
    persistence: hibernate
    migrations: flyway
    api_protocol: grpc
    messaging: kafka
    caching: caffeine
    observability: opentelemetry

  notification-service:
    path: services/notification-service
    language: typescript
    framework: nestjs
    testing: vitest
    database: mongodb
    persistence: mongoose
    api_protocol: graphql
    messaging: rabbitmq
    observability: opentelemetry

  analytics-service:
    path: services/analytics-service
    language: python
    framework: fastapi
    testing: pytest
    database: clickhouse
    persistence: sqlalchemy
    api_protocol: rest
    messaging: kafka

  frontend:
    path: services/frontend
    language: typescript
    framework: angular
    testing: vitest
    api_protocol: graphql

  infra:
    path: infra/k8s
    framework: k8s

  shared:
    path: libs/common
    language: kotlin
    testing: kotest
```

### 2.3 Config Mode Detection

PREFLIGHT auto-detects the config mode:

- **Flat mode** (backward compatible): `components:` contains scalar fields (`language: kotlin`, `framework: spring`). Single-service project.
- **Multi-service mode**: `components:` contains named entries, each with a `path:` field. Monorepo with per-service stacks.

No new top-level keys. No breaking changes. The existing `state.json.components` structure already supports named entries — this extends it with richer convention data.

### 2.4 Config Rules

- Each entry's `path:` is relative to the project root and must be a valid directory.
- Entry names are lowercase-with-hyphens identifiers used in `state.json` and task tagging.
- The `shared:` entry (optional) provides conventions for shared libraries. Files matching its `path:` prefix use its stack. Without a `shared:` entry, files outside any service path get only language-level conventions (safest default).
- All new layer fields are optional in both flat and multi-service mode.

### 2.5 Layer Combination Validation

PREFLIGHT validates that component configurations are sensible. Invalid combinations produce a WARNING (not a hard block — the user may know better):

| Rule | Example | Severity |
|------|---------|----------|
| Frontend frameworks should not declare `database:` or `persistence:` | `framework: react` + `database: postgresql` | WARNING |
| SQL persistence requires SQL database | `persistence: hibernate` + `database: mongodb` | WARNING |
| Document persistence requires document database | `persistence: mongoose` + `database: postgresql` | WARNING |
| Mobile frameworks should not declare `messaging:` | `framework: swiftui` + `messaging: kafka` | WARNING |
| Infra frameworks should only use infra-relevant layers | `framework: k8s` + `persistence: hibernate` | WARNING |

Warnings are logged and shown to the user but do not block the pipeline.

### 2.6 Redis Dual-Role Clarification

Redis appears in both `modules/databases/` and `modules/caching/`. These are distinct concerns:
- `database: redis` — using Redis as a primary data store (data structures, persistence, streams).
- `caching: redis` — using Redis as a cache layer (TTL, eviction, cache-aside).

A project may declare both if Redis serves both roles. The generic modules cover different content: `databases/redis.md` focuses on data modeling and persistence (RDB/AOF), while `caching/redis.md` focuses on cache invalidation strategies and eviction policies.

---

## 3. PREFLIGHT Resolution Changes

### 3.1 Single-Service Mode (Flat `components:`)

1. Read `components:` from `dev-pipeline.local.md`.
2. Resolve existing layers: language, framework, variant, testing (unchanged).
3. For each new optional field present:
   a. Load the generic module: `modules/{layer}/{value}.md`
   b. Load the framework binding if it exists: `modules/frameworks/{framework}/{layer}/{value}.md`
4. Compose all loaded layers in precedence order (Section 1.3).
5. Store resolved convention stack in `state.json.resolved_conventions`.

### 3.2 Multi-Service Mode (Named `components:` entries)

1. Detect multi-service mode (entries have `path:` fields).
2. Validate each entry's `path:` exists.
3. For each entry, resolve its full convention stack (same as 3.1).
4. Store per-component stacks in `state.json.components[name].resolved_conventions`.
5. Build a path-prefix-to-component lookup table for runtime convention resolution.
6. Run layer combination validation (Section 2.5) and log warnings.

### 3.3 Version Detection for New Layers

PREFLIGHT detects versions for new layers from manifest files:

| Layer | Detection Source |
|-------|-----------------|
| persistence | `build.gradle.kts` (implementation deps), `package.json` (dependencies), `pyproject.toml` (dependencies), `Cargo.toml` (dependencies) |
| messaging | Same manifest files — look for kafka-clients, amqplib, aiokafka, etc. |
| caching | Same manifest files — look for caffeine, ioredis, redis-py, etc. |
| search | Same manifest files — look for elasticsearch, opensearch, meilisearch client libs |
| observability | Same manifest files — look for opentelemetry-*, micrometer-*, prom-client, etc. |

Detected versions are stored in `state.json.detected_versions` (extending the existing version detection). Version-gated deprecation rules in layer-specific `known-deprecations.json` use these versions.

### 3.4 Runtime Convention Lookup

When a task or check engine needs conventions for a file:
1. Match the file's path against the path-prefix-to-component lookup table.
2. If matched: use that component's convention stack.
3. If not matched: check for a `shared:` component entry. If present, use its stack.
4. If still not matched: use language-level conventions only (no optional layers). This is the safe default.

### 3.5 Check Engine Rule Merge

The check engine operates in hook mode (every Edit/Write). Loading and merging multiple `rules-override.json` files at runtime would be too slow. Instead:

1. **PREFLIGHT** resolves all `rules-override.json` files per component and merges them into a single cached file: `.pipeline/.rules-cache-{component}.json`.
2. The check engine hook reads only the cached file for the file's owning component.
3. Merge semantics: framework-binding overrides > generic-layer overrides > framework overrides > shared defaults. Array fields (patterns) are concatenated. Object fields are deep-merged. `"disabled": true` suppresses a rule from any lower layer.
4. Cache invalidation: the cache is rebuilt at PREFLIGHT and whenever the orchestrator detects a convention drift (SHA256 comparison).

### 3.6 Deprecation Registry Discovery

`pl-140-deprecation-refresh` discovers registries by scanning:
1. `modules/frameworks/{framework}/known-deprecations.json` (existing)
2. `modules/{layer}/{value}.known-deprecations.json` for each active layer (new)
3. `modules/frameworks/{framework}/{layer}/{value}.known-deprecations.json` for each active binding (new)

All registries use the same schema v2 (`applies_from`, `removed_in`, `applies_to`). In multi-service mode, the agent runs per-component, using that component's detected versions for gating.

---

## 4. Pipeline Behavior Changes

### 4.1 PLAN Stage

In multi-service mode, the planner:
- Decomposes the requirement into per-service tasks.
- Tags each task with its service name.
- Notes cross-service dependencies (e.g., "payment-service emits event" → "notification-service consumes event").
- Ensures each task targets exactly one service.

### 4.2 IMPLEMENT Stage

- The orchestrator sets the working directory context per task based on the service's `path:`.
- Convention-specific scaffolder patterns are resolved from the task's service stack.
- The check engine receives the correct convention stack per file.

### 4.3 REVIEW Stage

- Quality gate dispatches reviewers with per-file convention stacks.
- A single review batch may include files from multiple services — each file is annotated with its owning service's stack.
- Cross-service consistency is checked: event schemas match, API contracts align, shared types are consistent.

### 4.4 Check Engine

- Layer 1 (fast patterns): `rules-override.json` from each loaded layer is merged. Per-service in multi-service mode.
- Layer 3 (agent): deprecation refresh runs per service, checking each service's dependency versions against the correct layer-specific deprecation registries.

---

## 5. Generic Module Content Structure

Each generic module file follows a consistent structure:

```markdown
# {Technology} Best Practices

## Overview
What it is, when to use it, when NOT to use it.

## Architecture Patterns
Key patterns (with code examples) and anti-patterns.

## Configuration
Connection setup, pooling, tuning, environment-specific config.

## Performance
Optimization patterns, common bottlenecks, scaling considerations.

## Security
Authentication, encryption, injection prevention, access control.

## Testing
How to test code that uses this technology (Testcontainers, embedded mode, mocking strategies).

## Dos
- Concrete best practices with brief rationale.

## Don'ts
- Concrete anti-patterns with explanation of consequences.
```

Framework binding files follow a shorter structure (they EXTEND, not replace):

```markdown
# {Technology} with {Framework} [{Variant}]

## Integration Setup
Dependencies, configuration, DI wiring.

## Framework-Specific Patterns
Patterns that differ from the generic module because of the framework.

## Scaffolder Patterns
File path templates for this combination:
  entity: "..."
  repository: "..."
  migration: "..."

## Additional Dos/Don'ts
Framework-specific additions to the generic layer.
```

---

## 6. Full Technology Inventory

### 6.1 Databases (8 files)

| Technology | Key Focus Areas |
|-----------|----------------|
| PostgreSQL | Indexing (B-tree, GIN, GiST), JSONB patterns, partitioning, connection pooling (PgBouncer), VACUUM, CTEs, advisory locks |
| MySQL | InnoDB tuning, index optimization, replication (group replication, GTID), character sets, query cache, partitioning |
| MongoDB | Schema design (embedding vs. referencing), indexing (compound, text, TTL), aggregation pipeline, sharding, change streams |
| Redis | Data structure selection, memory management, persistence (RDB/AOF), pub/sub vs. streams, cluster vs. sentinel, eviction policies |
| ClickHouse | Column-oriented design, MergeTree family, materialized views, distributed queries, batch inserts, partition management |
| SQLite | WAL mode, connection handling (single-writer), migration strategies, file locking, appropriate use cases |
| DynamoDB | Single-table design, GSI/LSI patterns, capacity planning (on-demand vs. provisioned), DynamoDB Streams, transaction patterns |
| Cassandra | Data modeling (query-first), partition key design, consistency levels, compaction strategies, lightweight transactions |

### 6.2 Persistence / ORM (13 files)

| Technology | Framework Affinity | Key Focus Areas |
|-----------|-------------------|----------------|
| Hibernate/JPA | Spring (Java) | Entity lifecycle, lazy loading, N+1 prevention, batch fetching, L2 cache, dirty checking, JPQL vs. Criteria API |
| Exposed | Spring (Kotlin), Ktor | DSL vs. DAO, transaction management, coroutine support, type-safe queries, custom column types |
| jOOQ | Spring (Java/Kotlin) | Code generation, type-safe SQL, plain SQL templates, batch operations, stored procedure calls |
| Koog | Ktor, KMP | JetBrains Kotlin ORM, type-safe queries, coroutine-first, multiplatform considerations |
| Spring Data R2DBC | Spring (Kotlin/Java) | Reactive repositories, `@Query` for partial updates, `DatabaseClient` for complex queries, connection pooling |
| SQLAlchemy | FastAPI, Flask | Async session, relationship loading, hybrid properties, migration integration, unit of work |
| Prisma | Express, NestJS, Next.js | Schema-first, migration workflow, relation queries, raw SQL escape hatch, connection pooling |
| TypeORM | Express, NestJS | Entity decorators, repository pattern, query builder, migration generation, active record vs. data mapper |
| Drizzle | Express, NestJS, Next.js | Schema in TypeScript, prepared statements, relational queries, push vs. migration workflows |
| Mongoose | Express, NestJS | Schema design, middleware (pre/post hooks), virtuals, population, lean queries, discriminators |
| Django ORM | Django | QuerySet chaining, select_related/prefetch_related, F/Q expressions, custom managers, signals |
| Room | Jetpack Compose | DAO pattern, Flow/LiveData observation, migration strategies, type converters, embedded objects |
| SQLDelight | KMP | Multiplatform SQL, generated type-safe Kotlin, coroutine/Flow support, migration verification |

### 6.3 Migrations (8 files)

| Technology | Framework Affinity | Key Focus Areas |
|-----------|-------------------|----------------|
| Flyway | Spring (Java/Kotlin) | Versioned vs. repeatable migrations, naming conventions (V/U/R prefix), callbacks, placeholder replacement, baseline |
| Liquibase | Spring (Java/Kotlin) | Changelog format (XML/YAML/SQL), changesets, contexts, labels, rollback strategies, diff generation |
| Alembic | FastAPI, Flask | Autogenerate, batch operations, branching/merging, data migrations, offline mode |
| Prisma Migrate | Express, NestJS | Schema diff, shadow database, migration history, custom SQL steps, seeding |
| Django migrations | Django | Auto-detection, RunPython for data migrations, squashing, dependency resolution, fake migrations |
| Knex | Express, NestJS | JavaScript migration files, batch system, seed files, transaction-wrapped migrations |
| Diesel | Axum | Embed migrations, CLI workflow, down.sql conventions, print-schema, migration testing |
| SQLx | Axum | Compile-time checked SQL, migration directory, reversible migrations, offline mode |

### 6.4 API Protocols (4 files)

| Technology | Key Focus Areas |
|-----------|----------------|
| REST | Resource naming, HTTP method semantics, status codes, pagination (cursor vs. offset), versioning (URL vs. header), HATEOAS, error format (RFC 7807), rate limiting |
| GraphQL | Schema design, query complexity limits, N+1 in resolvers (DataLoader), subscriptions, federation, persisted queries, input validation, error handling |
| gRPC | Protobuf schema design, service definition, streaming (unary/server/client/bidirectional), error codes, deadlines, interceptors, health checking, reflection |
| WebSocket | Connection lifecycle, heartbeat/ping-pong, reconnection strategies, message framing, backpressure, authentication on connect, room/topic patterns |

### 6.5 Messaging (6 files)

| Technology | Key Focus Areas |
|-----------|----------------|
| Kafka | Topic design, partitioning strategies, consumer groups, exactly-once semantics, schema registry (Avro/Protobuf), dead letter topics, compaction, retention |
| RabbitMQ | Exchange types (direct/topic/fanout/headers), queue durability, prefetch, dead letter exchanges, publisher confirms, consumer acknowledgment |
| NATS | Subject-based messaging, JetStream for persistence, request-reply, queue groups, key-value store, object store |
| SQS/SNS | FIFO vs. standard queues, message deduplication, fan-out via SNS, visibility timeout, DLQ configuration, batch operations |
| Redis Streams | Consumer groups, stream trimming, pending entry list, claim/autoclaim, XREAD blocking, stream vs. pub/sub decision |
| Pulsar | Multi-tenancy, topic compaction, tiered storage, schema registry, delayed messages, dead letter topics, functions |

### 6.6 Caching (4 files)

| Technology | Key Focus Areas |
|-----------|----------------|
| Redis | Cache-aside vs. write-through, TTL strategies, eviction policies, cache stampede prevention (locking), serialization, cluster-aware caching |
| Caffeine | Local cache sizing, expiration (time/size/reference), refresh-ahead, loading cache, statistics, eviction listeners |
| Memcached | Consistent hashing, slab allocation, CAS operations, multi-get optimization, connection pooling |
| Hazelcast | Near-cache, distributed maps, entry processors, WAN replication, split-brain protection, CP subsystem |

### 6.7 Search (3 files)

| Technology | Key Focus Areas |
|-----------|----------------|
| Elasticsearch | Index design, mapping (keyword vs. text), analyzers, query DSL, aggregations, bulk indexing, reindexing strategies, cluster sizing |
| OpenSearch | Fork-specific features, security plugin, index state management, cross-cluster replication, observability integration |
| Meilisearch | Index settings, filterable/sortable attributes, typo tolerance, faceted search, ranking rules, multi-index search |

### 6.8 Storage (4 files)

| Technology | Key Focus Areas |
|-----------|----------------|
| S3 | Presigned URLs, multipart upload, lifecycle policies, versioning, server-side encryption, event notifications, access points |
| GCS | Uniform bucket-level access, signed URLs, object lifecycle, transfer service, pub/sub notifications |
| Azure Blob | Container access tiers (hot/cool/archive), SAS tokens, immutability policies, change feed, soft delete |
| MinIO | S3-compatible API, bucket notifications, erasure coding, distributed mode, ILM policies |

### 6.9 Auth (5 files)

| Technology | Key Focus Areas |
|-----------|----------------|
| OAuth2/OIDC | Authorization code flow with PKCE, token refresh, scope design, resource server validation, discovery endpoint |
| JWT | Claims design, signing algorithms (RS256 vs. ES256), token rotation, refresh token patterns, token size considerations |
| Session-based | Session storage (Redis/DB), CSRF protection, cookie security (HttpOnly/Secure/SameSite), session fixation prevention |
| Keycloak | Realm design, client configuration, role mapping, user federation, custom themes, admin REST API |
| Auth0 | Tenant architecture, Rules/Actions, universal login, organization support, M2M tokens, rate limits |

### 6.10 Observability (6 files)

| Technology | Key Focus Areas |
|-----------|----------------|
| OpenTelemetry/OTLP | SDK setup, auto-instrumentation, manual spans, context propagation, exporters, resource attributes, sampling strategies |
| Micrometer | Meter registry, dimensional metrics, timer/counter/gauge patterns, SLO histograms, percentile approximation |
| Prometheus | Metric naming conventions, label cardinality, histogram buckets, recording rules, alerting rules, federation |
| Structured logging | JSON format, correlation IDs, log levels, sensitive data masking, context enrichment, MDC/NDC patterns |
| Jaeger | Trace sampling, span references, baggage, adaptive sampling, storage backends, UI integration |
| Health checks | Liveness vs. readiness vs. startup probes, dependency health, degraded states, health aggregation |

### 6.11 New Frameworks (4 directories)

| Framework | Target Stack | Key Conventions |
|-----------|-------------|-----------------|
| Angular | TypeScript + Angular 17+ | Standalone components, signals, NgRx/SignalStore, lazy-loaded routes, OnPush, strict templates, Nx monorepo support |
| NestJS | TypeScript + NestJS | Module-based architecture, decorators, DI container, Pipes/Guards/Interceptors, microservices transport, GraphQL code-first vs. schema-first |
| Vue/Nuxt | TypeScript + Vue 3 / Nuxt 3 | Composition API, `<script setup>`, Pinia state, Nuxt auto-imports, server routes, Nitro engine, `useFetch`/`useAsyncData` |
| Svelte | TypeScript + Svelte 5 | Runes (`$state`, `$derived`, `$effect`, `$props`), component composition, `{#snippet}`, minimal abstraction, no virtual DOM patterns |

Each new framework module includes: `conventions.md`, `local-template.md`, `pipeline-config-template.md`, `rules-override.json`, `known-deprecations.json`, plus applicable bindings under `testing/`, `persistence/`, `api-protocols/`, etc.

---

## 7. Scaffolder Pattern Extension

The scaffolder patterns in `local-template.md` gain layer-specific entries. The orchestrator resolves which patterns to use based on the service's `components:`.

Example for `spring` + `exposed` + `postgresql` + `flyway` + `grpc`:

```yaml
patterns:
  # Framework patterns (existing)
  port: "core/port/input/{area}/{UseCase}Port.kt"
  use_case: "core/usecase/{area}/{UseCase}UseCase.kt"

  # Persistence patterns (from spring/persistence/exposed.md)
  entity: "adapter/output/persistence/entity/{area}/{Entity}Table.kt"
  repository: "adapter/output/persistence/repository/{area}/{Entity}Repository.kt"
  mapper: "adapter/output/persistence/mapper/{area}/{Entity}Mapper.kt"

  # Database patterns (from spring/databases/postgresql.md)
  db_config: "config/DatabaseConfig.kt"

  # Migration patterns (from spring/migrations/flyway.md)
  migration: "src/main/resources/db/migration/V{N}__{description}.sql"

  # API patterns (from spring/api-protocols/grpc.md)
  proto: "src/main/proto/{area}/{service}.proto"
  grpc_service: "adapter/input/grpc/{area}/{Service}GrpcService.kt"

  # Messaging patterns (from spring/messaging/kafka.md)
  producer: "adapter/output/messaging/{area}/{Event}Producer.kt"
  consumer: "adapter/input/messaging/{area}/{Event}Consumer.kt"
  event: "core/event/{area}/{Event}Event.kt"
```

Patterns are merged from all loaded layers during PREFLIGHT. Conflicts follow the same precedence: framework-binding > generic-layer.

### 7.1 Scaffolder Pattern Merge Rules

When multiple layers define the same pattern key (e.g., both the generic persistence module and the framework binding define `repository:`), the framework-binding wins. This follows the same precedence as convention composition (Section 1.3). Patterns from different concerns (e.g., `migration:` from migrations layer and `entity:` from persistence layer) never conflict — they cover different file types.

---

## 8. Check Engine Extension

### 8.1 Layer-Specific Rule Overrides

Each generic module can include a `rules-override.json` alongside the `.md` file:

```
modules/databases/postgresql.rules-override.json
modules/persistence/hibernate.rules-override.json
modules/messaging/kafka.rules-override.json
```

These are merged into a cached composite at PREFLIGHT (see Section 3.5), not loaded at runtime. The check engine hook reads only the cached file for performance.

### 8.2 Layer-Specific Deprecation Registries

Each generic module can include a `known-deprecations.json`:

```
modules/persistence/hibernate.known-deprecations.json
modules/messaging/kafka.known-deprecations.json
```

All registries use the same schema v2 format as framework registries. Discovery pattern is documented in Section 3.6.

### 8.3 Required vs. Optional Files per Module

Each new module layer directory has this file structure:

| File | Required | Purpose |
|------|----------|---------|
| `{technology}.md` | Yes | Best practices and conventions |
| `{technology}.rules-override.json` | No | Check engine pattern rules (omit if no automated checks) |
| `{technology}.known-deprecations.json` | No | Deprecation registry (omit if not applicable) |

Framework bindings (`modules/frameworks/{fw}/{layer}/{tech}.md`) are always single `.md` files — they do not have their own `rules-override.json` or `known-deprecations.json` (those live at the generic layer level).

---

## 9. Learnings Extension

Per-layer learnings files are added to `shared/learnings/`:

```
shared/learnings/postgresql.md
shared/learnings/hibernate.md
shared/learnings/kafka.md
shared/learnings/graphql.md
shared/learnings/opentelemetry.md
...
```

The retrospective agent classifies MODULE-GENERIC learnings by layer (not just framework) and promotes to the appropriate file.

---

## 10. Implementation Phases

| Phase | Scope | Estimated Files | Key Framework Bindings |
|-------|-------|----------------|----------------------|
| **Phase 1: Architecture** | Extended `components:` (flat + multi-service), PREFLIGHT resolution, convention composition, check engine rule cache, orchestrator multi-service task routing, state schema v1.1.0, validate-plugin.sh updates | ~15 files modified | N/A |
| **Phase 2: Database + Persistence + Migrations** | 8 database + 13 persistence + 8 migration generic modules | ~60 files | Spring: hibernate, exposed, jooq, r2dbc, flyway, liquibase. FastAPI: sqlalchemy, alembic. Express: prisma, typeorm, drizzle, knex. Django: django-orm, django-migrations. Axum: diesel, sqlx. |
| **Phase 3: API Protocols + Messaging** | 4 API protocol + 6 messaging generic modules | ~30 files | Spring: rest, graphql, grpc, kafka, rabbitmq. NestJS: graphql, grpc, kafka. FastAPI: rest, graphql. Express: rest, graphql, websocket. |
| **Phase 4: Caching + Search + Storage + Auth** | 16 generic modules | ~40 files | Spring: caffeine, redis-cache, elasticsearch, s3, oauth2. NestJS: redis-cache, elasticsearch, s3, oauth2. FastAPI: redis-cache, s3, oauth2. |
| **Phase 5: Observability** | 6 observability generic modules | ~20 files | Spring: micrometer, opentelemetry. Express/NestJS: prom-client, opentelemetry. FastAPI: prometheus, opentelemetry. |
| **Phase 6: New Frameworks** | Angular, NestJS, Vue/Nuxt, Svelte (full module structure each) | ~30 files | Each gets: conventions.md, local-template.md, pipeline-config-template.md, rules-override.json, known-deprecations.json, testing/, and applicable layer bindings. |
| **Phase 7: Gap Analysis + Polish** | Review all bindings for completeness, add missing combinations, update CLAUDE.md, CONTRIBUTING.md | ~20 files | Cross-reference matrix audit. |

**Total: ~215 files across 7 phases.**

Each phase follows: implement → `/requesting-code-review` → gap/enhancement analysis → fix → next phase.

### 10.1 Framework x Layer Binding Matrix

Frontend frameworks get only client-relevant bindings. Backend frameworks get the full set. Infra frameworks get only observability.

| Framework | DB | Persist | Migrate | API | Msg | Cache | Search | Storage | Auth | Observ |
|-----------|:--:|:-------:|:-------:|:---:|:---:|:-----:|:------:|:-------:|:----:|:------:|
| spring | x | x | x | x | x | x | x | x | x | x |
| fastapi | x | x | x | x | x | x | x | x | x | x |
| express | x | x | x | x | x | x | x | x | x | x |
| nestjs | x | x | x | x | x | x | x | x | x | x |
| django | x | x | x | x | x | x | x | x | x | x |
| axum | x | x | x | x | x | x | - | x | x | x |
| gin | x | x | x | x | x | x | - | x | x | x |
| go-stdlib | x | x | x | x | x | x | - | x | x | x |
| aspnet | x | x | x | x | x | x | x | x | x | x |
| vapor | x | x | x | x | - | x | - | x | x | x |
| react | - | - | - | x | - | - | - | - | x | - |
| nextjs | - | x | x | x | - | x | - | x | x | x |
| sveltekit | - | - | - | x | - | - | - | - | x | - |
| svelte | - | - | - | x | - | - | - | - | x | - |
| angular | - | - | - | x | - | - | - | - | x | - |
| vue | - | - | - | x | - | - | - | - | x | - |
| jetpack-compose | x | x | x | x | - | x | - | - | x | x |
| kotlin-multiplatform | x | x | x | x | - | x | - | - | x | x |
| k8s | - | - | - | - | - | - | - | - | - | x |
| embedded | - | - | - | - | - | - | - | - | - | - |

`x` = binding created. `-` = not applicable for this framework type.

---

## 11. Backward Compatibility

- Existing flat `components:` configs with only `language`, `framework`, `variant`, `testing` work unchanged (auto-detected as flat mode).
- New fields are all optional — omitting them skips the layer entirely.
- Existing framework `conventions.md` files retain their current database/persistence sections. These are progressively replaced by references to the new layer modules across phases.
- Multi-service mode is an extension of the existing `components:` structure, not a replacement. Existing multi-component configs (with `path:` and `convention_stack`) continue to work.
- **State schema:** bumps to **v1.1.0** (non-breaking additive change). New fields: `state.json.components[name].resolved_conventions` and `.pipeline/.rules-cache-{component}.json`. Old v1.0.0 state files are forward-compatible — missing fields default to empty. No `/pipeline-reset` required.

### 11.1 Worktree and Cross-Repo Clarification

- **Multi-service mode** (`components:` with named entries) is for same-repo monorepos. All services share the single `.pipeline/worktree`.
- **Cross-repo mode** (`related_projects:` in config) is for separate repositories. Each related project gets its own worktree entry in `state.json.cross_repo`.
- These modes are orthogonal — a monorepo with 5 services can also have 2 related external projects.

---

## 12. Config Detection Enhancement

`/pipeline-init` extends its detection to identify:
- **Database**: scan for connection strings, Docker Compose service images (postgres, mysql, mongo, redis), ORM config files.
- **Persistence**: scan for ORM dependencies in manifests (hibernate-core, exposed-core, prisma, sqlalchemy, etc.).
- **Migrations**: scan for migration directories and tool config (flyway.conf, alembic.ini, prisma/migrations/).
- **API Protocol**: scan for proto files (gRPC), GraphQL schema files, WebSocket dependencies.
- **Messaging**: scan for Kafka/RabbitMQ/NATS dependencies and config.
- **Caching**: scan for cache dependencies (caffeine, redis cache config).
- **Observability**: scan for OTEL dependencies, Micrometer, Prometheus config.
- **Auth**: scan for OAuth2/Keycloak/Auth0 dependencies and config.

For monorepos, detection runs per-service directory to build the multi-service `components:` block automatically.

---

## 13. Validation and Testing

### 13.1 Structural Validation (validate-plugin.sh)

Add checks for new module directories:

```bash
# Verify each new layer directory exists and has at least one .md file
for layer in databases persistence migrations api-protocols messaging caching search storage auth observability; do
  test -d "modules/$layer" || fail "Missing layer directory: modules/$layer"
  test "$(ls modules/$layer/*.md 2>/dev/null | wc -l)" -ge 1 || fail "No modules in: modules/$layer"
done

# Verify framework bindings reference existing generic modules
for binding in modules/frameworks/*/persistence/*.md modules/frameworks/*/messaging/*.md ...; do
  generic="modules/$(dirname "${binding#modules/frameworks/*/}")"/$(basename "$binding")
  test -f "$generic" || fail "Binding $binding has no generic module: $generic"
done
```

### 13.2 Contract Tests

Add bats contract tests verifying:
- Every generic module .md has the required sections (Overview, Architecture Patterns, Dos, Don'ts).
- Every framework binding .md has the required sections (Integration Setup, Framework-Specific Patterns).
- No layer combination validation rule references a technology that does not exist as a module.

---

## 14. Documentation Updates

### 14.1 CLAUDE.md Updates

- Add new module layers to the Architecture section.
- Update convention composition order documentation.
- Add "Adding a new database/persistence/etc. module" section parallel to "Adding a new framework."
- Document multi-service config mode.
- Update the agent inventory if any new review agents are added.

### 14.2 CONTRIBUTING.md Updates

Add "Adding a new layer module" section:

1. Create `modules/{layer}/{name}.md` with the required structure (Section 5).
2. Optionally add `{name}.rules-override.json` and `{name}.known-deprecations.json`.
3. Create framework bindings under `modules/frameworks/{fw}/{layer}/{name}.md` for each applicable framework (see binding matrix in Section 10.1).
4. Add a learnings file at `shared/learnings/{name}.md`.
5. Update the binding matrix in this spec.
6. Run `./tests/run-all.sh` to verify structural integrity.

### 14.3 README.md Updates

- Update the "Available modules" section with new layer counts.
- Add a "Technology stack configuration" section showing the extended `components:` structure.
- Add monorepo configuration example.

---

## 15. Quality Gate Impact

### 15.1 Existing Reviewers Gain Layer Awareness

No new review agents are created for the new layers. Instead, existing reviewers are extended:

| Reviewer | New Layer Awareness |
|----------|-------------------|
| `architecture-reviewer` | Validates persistence patterns, messaging topology, cache strategy alignment with architecture |
| `security-reviewer` | Checks auth layer configuration, database injection patterns, messaging authentication |
| `backend-performance-reviewer` | Checks N+1 queries (persistence-aware), cache hit ratios, messaging consumer lag patterns |
| `version-compat-reviewer` | Checks cross-layer version compatibility (e.g., Spring Boot 3.x + Hibernate 6.x) |

### 15.2 Quality Gate Batch Configuration

The `quality_gate` batches in `local-template.md` do not change structure. The existing reviewers automatically gain layer-awareness when conventions are loaded. No new batch entries are needed unless a project wants specialized review (e.g., a dedicated Kafka audit agent — future extension).
