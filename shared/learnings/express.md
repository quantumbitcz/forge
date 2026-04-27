---
schema_version: 2
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
items:
  - id: "ex-preempt-001"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.738744Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["error-handling", "express"]
    source: "cross-project"
    archived: false
    body_ref: "#ex-preempt-001"
  - id: "ex-preempt-002"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.738744Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["error-handling", "express"]
    source: "cross-project"
    archived: false
    body_ref: "#ex-preempt-002"
  - id: "ex-preempt-003"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.738744Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "express"]
    source: "cross-project"
    archived: false
    body_ref: "#ex-preempt-003"
  - id: "ex-preempt-004"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.738744Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "express"]
    source: "cross-project"
    archived: false
    body_ref: "#ex-preempt-004"
  - id: "ex-preempt-005"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.738744Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["performance", "express"]
    source: "cross-project"
    archived: false
    body_ref: "#ex-preempt-005"
  - id: "ex-preempt-006"
    base_confidence: 0.65
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.738744Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["security", "express"]
    source: "cross-project"
    archived: false
    body_ref: "#ex-preempt-006"
  - id: "ex-preempt-007"
    base_confidence: 0.85
    half_life_days: 30
    applied_count: 0
    last_applied: null
    first_seen: "2026-04-20T10:37:16.738744Z"
    false_positive_count: 0
    last_false_positive_at: null
    pre_fp_base: null
    applies_to: ["planner", "implementer", "reviewer.code"]
    domain_tags: ["build", "express"]
    source: "cross-project"
    archived: false
    body_ref: "#ex-preempt-007"
---
# Cross-Project Learnings: express

## PREEMPT items

### EX-PREEMPT-001: Unhandled promise rejections crash the process in async handlers
<a id="ex-preempt-001"></a>
- **Domain:** error-handling
- **Pattern:** Express does not catch rejected promises in `async` route handlers. An unhandled rejection crashes the Node process. Use `express-async-errors` package or wrap every async handler with a try/catch that calls `next(err)`.
- **Confidence:** HIGH
- **Hit count:** 0

### EX-PREEMPT-002: Error middleware requires exactly 4 parameters
<a id="ex-preempt-002"></a>
- **Domain:** error-handling
- **Pattern:** Express identifies error-handling middleware by its 4-parameter signature `(err, req, res, next)`. If any parameter is omitted (even if unused), Express treats it as a regular middleware and skips it during error propagation. Always declare all 4 parameters.
- **Confidence:** HIGH
- **Hit count:** 0

### EX-PREEMPT-003: Middleware order affects security — auth before validation before handler
<a id="ex-preempt-003"></a>
- **Domain:** security
- **Pattern:** Placing validation middleware before auth middleware means unauthenticated requests get detailed validation errors, leaking API structure. Order must be: recovery > logging > CORS > auth > validation > handler > error handler.
- **Confidence:** HIGH
- **Hit count:** 0

### EX-PREEMPT-004: Missing Helmet middleware exposes security headers
<a id="ex-preempt-004"></a>
- **Domain:** security
- **Pattern:** Express does not set security headers by default (no CSP, no X-Frame-Options, no HSTS). Adding `helmet()` middleware sets sensible defaults. Missing it leaves the app vulnerable to clickjacking, MIME sniffing, and other attacks.
- **Confidence:** HIGH
- **Hit count:** 0

### EX-PREEMPT-005: console.log in production blocks the event loop
<a id="ex-preempt-005"></a>
- **Domain:** performance
- **Pattern:** `console.log` is synchronous and writes to stdout. Under high throughput it blocks the event loop. Use a structured async logger (pino, winston with async transport) for production. Reserve console.log for development only.
- **Confidence:** MEDIUM
- **Hit count:** 0

### EX-PREEMPT-006: Body parser limit defaults allow oversized payloads
<a id="ex-preempt-006"></a>
- **Domain:** security
- **Pattern:** `express.json()` defaults to a 100KB body limit. For file upload endpoints this may be too low, but for API endpoints the default may be too high for abuse prevention. Set explicit `limit` per route: `express.json({ limit: '10kb' })` for APIs, higher for uploads.
- **Confidence:** MEDIUM
- **Hit count:** 0

### EX-PREEMPT-007: require() and import mixing causes dual-module hazard
<a id="ex-preempt-007"></a>
- **Domain:** build
- **Pattern:** Mixing `require()` (CommonJS) and `import` (ESM) in the same project causes module resolution issues — singletons are instantiated twice, middleware state is not shared. Use ESM throughout in TypeScript projects with `"type": "module"` in package.json.
- **Confidence:** HIGH
- **Hit count:** 0
