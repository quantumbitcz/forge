---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "nj-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.780022Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["dependency-injection", "nestjs"]
    source: "cross-project"
    archived: false
    body_ref: "nj-preempt-001"
  - id: "nj-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.780022Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["request-handling", "nestjs"]
    source: "cross-project"
    archived: false
    body_ref: "nj-preempt-002"
  - id: "nj-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.780022Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "nestjs"]
    source: "cross-project"
    archived: false
    body_ref: "nj-preempt-003"
  - id: "nj-preempt-004"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.780022Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["persistence", "nestjs"]
    source: "cross-project"
    archived: false
    body_ref: "nj-preempt-004"
  - id: "nj-preempt-005"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.780022Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "nestjs"]
    source: "cross-project"
    archived: false
    body_ref: "nj-preempt-005"
  - id: "nj-preempt-006"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.780022Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["configuration", "nestjs"]
    source: "cross-project"
    archived: false
    body_ref: "nj-preempt-006"
  - id: "nj-preempt-007"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.780022Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["dependency-injection", "nestjs"]
    source: "cross-project"
    archived: false
    body_ref: "nj-preempt-007"
---
# Cross-Project Learnings: nestjs

## PREEMPT items

### NJ-PREEMPT-001: Circular module dependency causes undefined provider at runtime
<a id="nj-preempt-001"></a>
- **Domain:** dependency-injection
- **Pattern:** Two modules importing each other (e.g., UsersModule imports OrdersModule and vice versa) causes one provider to be `undefined` at injection time. Use `forwardRef(() => OtherModule)` or refactor to extract the shared dependency into a third module.
- **Confidence:** HIGH
- **Hit count:** 0

### NJ-PREEMPT-002: ValidationPipe whitelist strips unknown fields silently
<a id="nj-preempt-002"></a>
- **Domain:** request-handling
- **Pattern:** With `whitelist: true`, unknown properties in the request body are stripped without error. With `forbidNonWhitelisted: true`, they cause a 400 error. Teams must agree on which behavior is expected. Missing `whitelist` entirely allows extra fields to pass through to the service layer.
- **Confidence:** HIGH
- **Hit count:** 0

### NJ-PREEMPT-003: Entity leakage in controller responses exposes internal fields
<a id="nj-preempt-003"></a>
- **Domain:** security
- **Pattern:** Returning persistence entities directly from controllers exposes internal fields (password hashes, internal IDs, soft-delete flags). Apply `ClassSerializerInterceptor` globally and use `@Exclude()` on sensitive entity fields, or always map to response DTOs.
- **Confidence:** HIGH
- **Hit count:** 0

### NJ-PREEMPT-004: Auto-sync schema in production drops columns and data
<a id="nj-preempt-004"></a>
- **Domain:** persistence
- **Pattern:** TypeORM `synchronize: true` or similar auto-schema features modify the database schema to match entities at startup. In production, this can drop columns, delete data, and cause irreversible data loss. Only enable in disposable local dev databases; use migrations everywhere else.
- **Confidence:** HIGH
- **Hit count:** 0

### NJ-PREEMPT-005: Global guard with APP_GUARD requires @Public() on open endpoints
<a id="nj-preempt-005"></a>
- **Domain:** security
- **Pattern:** Registering `AuthGuard` globally via `APP_GUARD` protects all routes, including health checks and public endpoints. These must be explicitly decorated with `@Public()` (via `@SetMetadata()` + guard reflector check) or they return 401.
- **Confidence:** HIGH
- **Hit count:** 0

### NJ-PREEMPT-006: ConfigService returns string type for all env vars
<a id="nj-preempt-006"></a>
- **Domain:** configuration
- **Pattern:** `configService.get('PORT')` returns `string | undefined` regardless of the actual type. Forgetting to parse to number causes `app.listen("3000")` which works but type comparisons fail. Use `get<number>('PORT')` or validate with a typed schema at startup.
- **Confidence:** MEDIUM
- **Hit count:** 0

### NJ-PREEMPT-007: Module exports not wired prevents cross-module service injection
<a id="nj-preempt-007"></a>
- **Domain:** dependency-injection
- **Pattern:** A service in ModuleA is not injectable in ModuleB unless ModuleA adds it to `exports: []` AND ModuleB adds ModuleA to `imports: []`. Missing either side causes a cryptic "Nest can't resolve dependencies" error at startup.
- **Confidence:** HIGH
- **Hit count:** 0
