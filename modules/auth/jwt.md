# JWT — Best Practices

## Overview

JSON Web Tokens (JWTs) are a compact, URL-safe format for encoding signed (JWS) or encrypted
(JWE) claims between parties. Use JWTs for stateless access tokens in distributed systems where
bearer token validation must happen without a network call to a central store. JWTs are not a
session mechanism — they cannot be revoked without additional infrastructure. Choose JWTs for
short-lived access tokens; use opaque tokens with introspection when revocation is a hard requirement.

## Architecture Patterns

### Claims Design
```json
{
  "iss": "https://auth.example.com",          // issuer — who created the token
  "sub": "user:f47ac10b-58cc-4372",           // subject — immutable user identifier
  "aud": ["https://api.example.com"],          // audience — intended recipients (array preferred)
  "exp": 1800000000,                           // expiry (Unix timestamp) — validate always
  "iat": 1800000000,                           // issued at — detect future-dated tokens
  "nbf": 1800000000,                           // not before — optional valid-from constraint
  "jti": "550e8400-e29b-41d4",                 // JWT ID — unique per token (replay prevention)
  "scope": "api:read orders:read",             // OAuth2 scopes
  "roles": ["user", "premium"],                // application roles (custom claim)
  "tenant_id": "acme-corp"                     // multi-tenant isolation (custom claim)
}
```
Keep payloads small — browsers send JWTs in cookies or Authorization headers with every request.
Avoid embedding large objects (permissions trees, full user profiles). Store large lookup data
server-side and reference it by `sub` or `tenant_id`.

### Signing Algorithms

| Algorithm | Key Type        | Use Case                                              |
|-----------|-----------------|-------------------------------------------------------|
| RS256     | RSA 2048-bit    | Default for distributed systems — public key shareable via JWKS |
| ES256     | EC P-256        | Faster than RSA, smaller signatures — preferred for high-throughput |
| EdDSA     | Ed25519         | Fastest, smallest — modern systems only               |
| HS256     | Shared secret   | Single-service only — never for distributed systems   |

```python
from cryptography.hazmat.primitives.asymmetric import ec
from jose import jwt

# ES256 — generate key pair
private_key = ec.generate_private_key(ec.SECP256R1())
public_key = private_key.public_key()

# Sign
token = jwt.encode({"sub": "user-123", "exp": time() + 900}, private_key, algorithm="ES256")

# Verify (any service with the public key)
claims = jwt.decode(token, public_key, algorithms=["ES256"], audience="https://api.example.com")
```

### JWKS Endpoint (Public Key Distribution)
```python
from jose import jwk

# Expose the public key as a JWKS endpoint (GET /.well-known/jwks.json)
def get_jwks() -> dict:
    public_key_jwk = jwk.construct(public_key, algorithm="ES256").to_dict()
    public_key_jwk["kid"] = CURRENT_KEY_ID   # key ID for rotation
    public_key_jwk["use"] = "sig"
    return {"keys": [public_key_jwk]}
```
Include `kid` (key ID) in both the JWT header and the JWKS — enables clients to select the correct
key when multiple keys are published during rotation.

### Key Rotation Strategy
```
Phase 1 — Preparation (days 0-7):
  - Generate new key pair, assign new kid
  - Publish BOTH old and new keys in JWKS endpoint
  - New tokens signed with new kid

Phase 2 — Overlap (days 7-30):
  - Old tokens (kid=old) still valid and verifiable
  - All new tokens signed with new kid

Phase 3 — Retirement:
  - Remove old key from JWKS once all old tokens have expired (after max exp)
  - Old tokens become unverifiable — users must re-authenticate
```

### Refresh Token Patterns
```python
def issue_tokens(user_id: str) -> dict:
    access_token = jwt.encode({
        "sub": user_id, "exp": time() + 900,   # 15 minutes
        "iat": time(), "jti": str(uuid4()),
        "type": "access"
    }, private_key, algorithm="ES256")

    refresh_token_value = secrets.token_urlsafe(32)
    db.store_refresh_token(hash(refresh_token_value), user_id, expires_in=days(30))

    return {"access_token": access_token, "refresh_token": refresh_token_value}

def rotate_refresh_token(old_token: str) -> dict:
    token_record = db.find_refresh_token(hash(old_token))
    if not token_record or token_record.is_revoked:
        # Possible reuse attack — revoke all tokens for the user
        db.revoke_all_tokens(token_record.user_id if token_record else None)
        raise SecurityException("Refresh token reuse detected")
    db.revoke_refresh_token(hash(old_token))   # single-use
    return issue_tokens(token_record.user_id)
```
Refresh tokens are opaque values stored server-side (hashed). They must be rotated (one-time use)
and revocable. Detect reuse by revoking all tokens for the user when an already-used token is presented.

### Token Size Considerations
```
Typical JWT structure (ES256):
  Header:  ~60 bytes (base64url)
  Payload: ~300–600 bytes depending on claims
  Signature: ~86 bytes (ES256) vs ~342 bytes (RS256 2048-bit)
  Total:   ~450–750 bytes — fits comfortably in HTTP headers
```
Browser cookie limit is 4 KB per cookie; HTTP header limit varies (8 KB typical). Keep JWTs under
2 KB to avoid header truncation. If you exceed 1 KB, audit which claims are really necessary.

### Algorithm Confusion Attack Prevention
```python
# Always specify allowed algorithms explicitly — never use jwt.decode(alg=None)
claims = jwt.decode(
    token,
    key=public_key,
    algorithms=["ES256"],    # explicit allowlist — never ["RS256", "HS256"] together
    audience="https://api.example.com"
)
```
The algorithm confusion attack tricks a server using an asymmetric key into accepting a token
signed with `HS256` using the public key as the HMAC secret. Prevent it by hardcoding the allowed
algorithm(s) in the verification call.

## Configuration

```yaml
jwt:
  algorithm: ES256
  access_token_ttl: 900        # 15 minutes
  refresh_token_ttl: 2592000   # 30 days
  issuer: https://auth.example.com
  audience: https://api.example.com
  clock_skew_tolerance: 10     # seconds — accommodate minor clock differences
```

## Performance

- ES256 validation is ~10x faster than RS256 2048-bit — prefer ES256 for high-throughput APIs.
- Cache JWKS response (TTL 1 hour); re-fetch only on `kid` not found in cache.
- `jti` uniqueness enforcement requires a DB lookup — only enforce on sensitive operations or use short TTLs instead.

## Security

- Set `exp` short (15 minutes for access tokens) — JWTs cannot be revoked server-side without infrastructure.
- Always validate `iss`, `aud`, `exp`, `nbf` and reject tokens with unexpected `alg`.
- Store refresh tokens hashed in the database — the raw value is a bearer credential.
- Detect refresh token reuse and treat it as a security incident (revoke all user tokens).
- Never log JWT payload — it contains PII and auth claims.

## Testing

```python
def make_test_jwt(sub="user-1", exp_offset=900, **extra_claims) -> str:
    return jwt.encode(
        {"sub": sub, "iss": TEST_ISSUER, "aud": TEST_AUDIENCE,
         "exp": time() + exp_offset, "iat": time(), **extra_claims},
        TEST_PRIVATE_KEY, algorithm="ES256"
    )

def test_expired_token_rejected(client):
    token = make_test_jwt(exp_offset=-1)   # already expired
    response = client.get("/api/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 401
```

## Dos
- Use ES256 or RS256 — never HS256 for distributed systems where multiple services validate tokens.
- Include `kid` in token header and publish corresponding public key via JWKS endpoint.
- Rotate signing keys regularly (every 90 days) using a phased rollover strategy.
- Keep access tokens short-lived (15 minutes); use rotating, single-use refresh tokens for longer sessions.
- Validate `aud` explicitly — prevents token reuse across different services.

## Don'ts
- Don't allow `alg: none` — it skips signature verification entirely.
- Don't mix symmetric (HS256) and asymmetric (RS256/ES256) algorithms in the same allowed list.
- Don't put sensitive data (passwords, card numbers, SSNs) in JWT payload — it is base64-encoded, not encrypted.
- Don't use JWTs as session tokens for single-service web apps — server-side sessions are simpler and revocable.
- Don't skip `jti` validation when replay prevention is a requirement (e.g., payment initiation).
