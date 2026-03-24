# REST API Conventions

## Overview

REST (Representational State Transfer) is the dominant architectural style for HTTP APIs. These conventions cover
resource modeling, HTTP semantics, status codes, versioning, caching, and error handling, with the goal of producing
APIs that are predictable, cacheable, and evolvable over time.

## Architecture Patterns

### Resource Naming
- Use plural nouns for collections: `/users`, `/orders`, `/products`
- Nest resources to express ownership: `/users/{id}/orders`
- Limit nesting depth to 2 levels; deeper hierarchies become brittle
- Use kebab-case for multi-word segments: `/shipping-addresses`
- Never use verbs in resource paths; use HTTP methods instead

```
GET    /articles          # list
POST   /articles          # create
GET    /articles/{id}     # fetch one
PUT    /articles/{id}     # full replace
PATCH  /articles/{id}     # partial update
DELETE /articles/{id}     # delete
```

### HTTP Method Semantics
| Method | Safe | Idempotent | Body |
|--------|------|-----------|------|
| GET    | yes  | yes        | no   |
| HEAD   | yes  | yes        | no   |
| POST   | no   | no         | yes  |
| PUT    | no   | yes        | yes  |
| PATCH  | no   | no         | yes  |
| DELETE | no   | yes        | no   |

### Status Codes
- **200 OK** — successful GET, PUT, PATCH
- **201 Created** — successful POST; include `Location` header with new resource URL
- **204 No Content** — successful DELETE or action with no response body
- **400 Bad Request** — malformed request, validation failure
- **401 Unauthorized** — missing or invalid credentials
- **403 Forbidden** — authenticated but insufficient permissions
- **404 Not Found** — resource does not exist
- **409 Conflict** — state conflict (duplicate key, optimistic lock)
- **422 Unprocessable Entity** — well-formed but semantically invalid
- **429 Too Many Requests** — rate limit exceeded
- **500 Internal Server Error** — unhandled server failure

### Pagination

**Cursor-based** (preferred for large or frequently-updated datasets):
```json
GET /posts?limit=20&after=eyJpZCI6MTAwfQ==

{
  "data": [...],
  "pagination": {
    "next_cursor": "eyJpZCI6MTIwfQ==",
    "has_more": true
  }
}
```
Pros: stable under concurrent inserts/deletes, O(1) query cost with index.
Cons: no random-page access, cursor is opaque.

**Offset-based** (acceptable for small, stable datasets):
```json
GET /reports?page=3&per_page=25

{
  "data": [...],
  "pagination": { "total": 312, "page": 3, "per_page": 25 }
}
```
Pros: random-page access, easy UI page numbers.
Cons: drifts under concurrent mutations, expensive COUNT query.

### Versioning

| Strategy | Example | Notes |
|----------|---------|-------|
| URL path  | `/v1/users` | Most visible, easiest to route |
| Header    | `Api-Version: 2024-01-01` | Keeps URLs clean; harder to test in browser |
| Content negotiation | `Accept: application/vnd.myapi.v2+json` | Most RESTful; least ergonomic |

Prefer URL path versioning for public APIs. Support N and N-1 simultaneously; give 6-month deprecation notice.

## Configuration

### Error Format (RFC 7807 Problem Details)
```json
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/problem+json

{
  "type": "https://api.example.com/errors/validation-failed",
  "title": "Validation Failed",
  "status": 422,
  "detail": "The request body contains invalid fields.",
  "instance": "/orders/abc-123",
  "errors": [
    { "field": "quantity", "message": "must be >= 1" }
  ]
}
```

### Rate Limiting Headers
```http
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 847
X-RateLimit-Reset: 1711929600
Retry-After: 30
```

### Idempotency Keys (for POST)
```http
POST /payments
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
```
Store the key + response for at least 24 hours. Return the cached response on replay.

## Performance

### ETags and Conditional Requests
```http
# Server response
ETag: "abc123"
Cache-Control: private, max-age=300

# Client subsequent request
If-None-Match: "abc123"
# → 304 Not Modified (no body)

# Optimistic concurrency for writes
If-Match: "abc123"
# → 412 Precondition Failed if resource changed
```

### Content Negotiation
```http
Accept: application/json, application/xml;q=0.8, */*;q=0.5
Accept-Encoding: gzip, br
Accept-Language: en-US, en;q=0.9
```

## Security

- Validate and sanitize all path parameters and query strings
- Return `401` for missing auth, `403` for insufficient scope — never conflate them
- Never expose internal IDs (auto-increment PKs); use UUIDs or opaque tokens
- Set `Content-Security-Policy`, `X-Content-Type-Options: nosniff` on all responses
- Apply CORS headers server-side; never rely on client-side enforcement

## Testing

```
# Key test cases per endpoint
GET  /resources          → 200 with pagination, 400 invalid params
POST /resources          → 201 + Location, 400 validation, 409 duplicate
GET  /resources/{id}     → 200, 404 missing, 403 unauthorized
PATCH /resources/{id}    → 200 partial update, 412 ETag mismatch
DELETE /resources/{id}   → 204, 404, 409 constraint violation

# Rate limiting: verify 429 + Retry-After after threshold
# Idempotency: POST twice with same key → same 201 response
# Compression: Accept-Encoding: gzip → Content-Encoding: gzip in response
```

## HATEOAS Links

Include hypermedia links for discoverability on resource responses:
```json
{
  "id": "order-42",
  "status": "pending",
  "_links": {
    "self":   { "href": "/orders/order-42" },
    "cancel": { "href": "/orders/order-42/cancel", "method": "POST" },
    "items":  { "href": "/orders/order-42/items" }
  }
}
```

## Dos

- Use plural nouns for all resource paths
- Always return RFC 7807 Problem Details for error responses
- Include `Location` header on 201 responses
- Support `If-Match` / `ETag` for concurrent write safety
- Use cursor pagination for large or streaming datasets
- Set `Idempotency-Key` support on POST endpoints that create resources
- Document deprecated endpoints with `Deprecation` and `Sunset` response headers

## Don'ts

- Don't use verbs in URLs (`/getUser`, `/createOrder`)
- Don't return 200 with an `error` field in the body
- Don't expose sequential integer IDs in public APIs
- Don't use HTTP GET for state-mutating operations
- Don't nest resources deeper than 2 levels
- Don't return different shapes for the same status code across endpoints
- Don't silently swallow unknown query parameters — log them
