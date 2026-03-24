# OAuth2 / OIDC — Best Practices

## Overview

OAuth2 is the industry-standard authorization framework; OpenID Connect (OIDC) adds an identity
layer on top for authentication. Use OAuth2/OIDC when delegating authorization to a trusted
identity provider (IdP), implementing single sign-on (SSO), or enabling third-party application
access to your APIs. Always use PKCE for public clients (SPAs, mobile apps). Never implement
OAuth2 flows from scratch — use a well-audited library or identity provider SDK.

## Architecture Patterns

### Authorization Code Flow with PKCE (Required for All Public Clients)
```python
import secrets, hashlib, base64

# Step 1: Generate PKCE code verifier and challenge
code_verifier = base64.urlsafe_b64encode(secrets.token_bytes(32)).rstrip(b"=").decode()
code_challenge = base64.urlsafe_b64encode(
    hashlib.sha256(code_verifier.encode()).digest()
).rstrip(b"=").decode()

# Step 2: Redirect to authorization endpoint
auth_url = (
    f"{AUTH_SERVER}/authorize"
    f"?response_type=code"
    f"&client_id={CLIENT_ID}"
    f"&redirect_uri={REDIRECT_URI}"
    f"&scope=openid+profile+email"
    f"&state={secrets.token_urlsafe(16)}"   # CSRF protection
    f"&code_challenge={code_challenge}"
    f"&code_challenge_method=S256"
)

# Step 3: Exchange code for tokens (server-side, code_verifier sent)
token_response = requests.post(f"{AUTH_SERVER}/token", data={
    "grant_type": "authorization_code",
    "code": authorization_code,
    "redirect_uri": REDIRECT_URI,
    "client_id": CLIENT_ID,
    "code_verifier": code_verifier   # verifies the PKCE challenge
})
```
PKCE prevents authorization code interception attacks — mandatory for mobile apps and SPAs, and
recommended for confidential clients too (OAuth2.1 requires it universally).

### Token Refresh
```python
def refresh_access_token(refresh_token: str) -> dict:
    response = requests.post(f"{AUTH_SERVER}/token", data={
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET   # confidential client only
    })
    if response.status_code == 400:
        # Refresh token expired or revoked — redirect to login
        raise RefreshTokenExpiredError()
    return response.json()
```
Refresh tokens should be rotated on each use. Store refresh tokens in HttpOnly cookies or
encrypted server-side session, never in localStorage.

### Scope Design (Least Privilege)
```
# Scope naming: {resource}:{action} or {resource}.{action}
openid                      # OIDC — get identity claims
profile                     # basic profile (name, picture)
email                       # email address
offline_access              # refresh token issuance

# Application-specific scopes
api:read                    # read-only API access
api:write                   # write access to API
orders:read                 # order history
payments:initiate           # initiate payment (requires explicit user consent)
admin:users                 # administrative user management (narrow audience)
```
Request only the scopes required for the current action. Offer incremental authorization — request
sensitive scopes when the user actually needs them, not at initial login.

### Resource Server — JWT Validation
```python
from jose import jwt, JWTError
import httpx

# Fetch JWKS from discovery endpoint and cache keys
def get_jwks():
    discovery = httpx.get(f"{AUTH_SERVER}/.well-known/openid-configuration").json()
    return httpx.get(discovery["jwks_uri"]).json()

def validate_token(token: str, audience: str) -> dict:
    try:
        return jwt.decode(
            token,
            key=get_jwks(),        # cached, refreshed on key rotation
            algorithms=["RS256"],
            audience=audience,     # validate aud claim — prevents token reuse across services
            issuer=AUTH_SERVER
        )
    except JWTError as e:
        raise UnauthorizedException(f"Invalid token: {e}")
```
Always validate `iss`, `aud`, `exp`, and `nbf`. Reject tokens with unexpected algorithms (algorithm
confusion attacks). Cache JWKS and refresh on verification failure (key rotation).

### OIDC Discovery Endpoint
```python
# Retrieve all endpoint URLs from the discovery document — never hardcode
discovery = httpx.get(f"{ISSUER}/.well-known/openid-configuration").json()
# Contains: authorization_endpoint, token_endpoint, userinfo_endpoint, jwks_uri,
#           revocation_endpoint, introspection_endpoint, etc.
```

### Token Introspection (Opaque Tokens)
```python
# For opaque (reference) tokens — check with the authorization server
introspect = requests.post(f"{AUTH_SERVER}/introspect",
    data={"token": access_token},
    auth=(CLIENT_ID, CLIENT_SECRET)
).json()

if not introspect.get("active"):
    raise UnauthorizedException("Token is not active")
```
Introspection is network-bound — cache results for short durations (30–60 seconds) for high-traffic
APIs. JWT validation is stateless and preferred over introspection at scale.

### OIDC Claims Mapping
```python
# Standard OIDC claims
sub   = claims["sub"]           # unique user identifier — use this as the internal user ID
email = claims["email"]
name  = claims["name"]
roles = claims.get("roles", []) # custom claim — configure in IdP claim mapping
```
Never use `email` as the primary key — it can change. Always use `sub` (subject) as the canonical
user identifier. Map custom claims (roles, tenant_id) in the IdP claim transformation rules.

## Configuration

```yaml
# Example resource server config
oauth2:
  issuer: https://auth.example.com
  audience: https://api.example.com
  jwks_cache_ttl: 3600      # seconds
  algorithms: [RS256]
  leeway: 10                # seconds of clock skew tolerance for exp/nbf
```

## Performance

- Cache the JWKS response (1 hour TTL) — re-fetch only on signature verification failure.
- Use JWT access tokens for stateless validation; reserve introspection for revocation-sensitive paths.
- Prefer short-lived access tokens (15 minutes) with refresh tokens over long-lived access tokens.

## Security

- Always use PKCE — implicit flow is deprecated in OAuth2.1; never use it.
- Validate `state` parameter on redirect to prevent CSRF.
- Validate `aud` claim in JWTs — missing aud validation allows token reuse across services.
- Never log access tokens or refresh tokens — treat them as credentials.
- Use `nonce` in OIDC flows to prevent replay attacks.
- Implement token revocation for refresh tokens on logout.

## Testing

```python
# Mock the OIDC provider in tests using a local JWKS endpoint
def create_test_token(sub: str, roles: list) -> str:
    return jwt.encode(
        {"sub": sub, "aud": TEST_AUDIENCE, "iss": TEST_ISSUER,
         "exp": datetime.utcnow() + timedelta(hours=1), "roles": roles},
        test_private_key, algorithm="RS256"
    )
```

## Dos
- Always use PKCE — for all client types in new implementations (OAuth2.1 mandates it).
- Validate `iss`, `aud`, `exp`, `nbf`, and algorithm on every JWT.
- Design scopes around resources and actions at least-privilege granularity.
- Cache JWKS keys with a short TTL and refresh on verification failure for key rotation support.
- Use `sub` as the immutable user identifier; never `email` or `username`.

## Don'ts
- Don't use implicit flow — it is deprecated and exposes tokens in the URL fragment.
- Don't skip `state` parameter validation — it is the CSRF protection for the redirect.
- Don't store refresh tokens in localStorage — use HttpOnly cookies or server-side sessions.
- Don't request `offline_access` (refresh tokens) unless the application genuinely needs background access.
- Don't hardcode authorization/token endpoint URLs — always derive from the discovery document.
