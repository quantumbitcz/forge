---
decay_tier: cross-project
default_base_confidence: 0.75
last_success_at: "2026-04-19T00:00:00Z"
last_false_positive_at: null
# See shared/learnings/decay.md for the canonical decay contract.
# Per-item base_confidence may be inherited from the legacy "Confidence: HIGH/MEDIUM/LOW" lines:
# HIGH→0.95, MEDIUM→0.75, LOW→0.5, ARCHIVED→0.3.
---
# Cross-Project Learnings: express

## PREEMPT items

### EX-PREEMPT-001: Unhandled promise rejections crash the process in async handlers
- **Domain:** error-handling
- **Pattern:** Express does not catch rejected promises in `async` route handlers. An unhandled rejection crashes the Node process. Use `express-async-errors` package or wrap every async handler with a try/catch that calls `next(err)`.
- **Confidence:** HIGH
- **Hit count:** 0

### EX-PREEMPT-002: Error middleware requires exactly 4 parameters
- **Domain:** error-handling
- **Pattern:** Express identifies error-handling middleware by its 4-parameter signature `(err, req, res, next)`. If any parameter is omitted (even if unused), Express treats it as a regular middleware and skips it during error propagation. Always declare all 4 parameters.
- **Confidence:** HIGH
- **Hit count:** 0

### EX-PREEMPT-003: Middleware order affects security — auth before validation before handler
- **Domain:** security
- **Pattern:** Placing validation middleware before auth middleware means unauthenticated requests get detailed validation errors, leaking API structure. Order must be: recovery > logging > CORS > auth > validation > handler > error handler.
- **Confidence:** HIGH
- **Hit count:** 0

### EX-PREEMPT-004: Missing Helmet middleware exposes security headers
- **Domain:** security
- **Pattern:** Express does not set security headers by default (no CSP, no X-Frame-Options, no HSTS). Adding `helmet()` middleware sets sensible defaults. Missing it leaves the app vulnerable to clickjacking, MIME sniffing, and other attacks.
- **Confidence:** HIGH
- **Hit count:** 0

### EX-PREEMPT-005: console.log in production blocks the event loop
- **Domain:** performance
- **Pattern:** `console.log` is synchronous and writes to stdout. Under high throughput it blocks the event loop. Use a structured async logger (pino, winston with async transport) for production. Reserve console.log for development only.
- **Confidence:** MEDIUM
- **Hit count:** 0

### EX-PREEMPT-006: Body parser limit defaults allow oversized payloads
- **Domain:** security
- **Pattern:** `express.json()` defaults to a 100KB body limit. For file upload endpoints this may be too low, but for API endpoints the default may be too high for abuse prevention. Set explicit `limit` per route: `express.json({ limit: '10kb' })` for APIs, higher for uploads.
- **Confidence:** MEDIUM
- **Hit count:** 0

### EX-PREEMPT-007: require() and import mixing causes dual-module hazard
- **Domain:** build
- **Pattern:** Mixing `require()` (CommonJS) and `import` (ESM) in the same project causes module resolution issues — singletons are instantiated twice, middleware state is not shared. Use ESM throughout in TypeScript projects with `"type": "module"` in package.json.
- **Confidence:** HIGH
- **Hit count:** 0
