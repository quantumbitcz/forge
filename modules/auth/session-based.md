# Session-Based Authentication — Best Practices

## Overview

Session-based authentication stores user state server-side and identifies users via a session ID
cookie. Use it for traditional web applications, server-rendered pages, or any scenario where
token revocation, centralized session management, and server-side session inspection matter.
Session auth is simpler to implement correctly than JWT-based auth for single-service applications
because sessions are revocable, auditable, and require no cryptographic key management. For
distributed microservices requiring stateless token validation, prefer JWTs with short TTLs.

## Architecture Patterns

### Session Storage — Redis (Distributed)
```python
# FastAPI + Redis session (itsdangerous signing for session ID)
from fastapi import FastAPI, Request, Response
import redis.asyncio as redis
import secrets, json

SESSION_TTL = 1800   # 30 minutes idle timeout

async def create_session(response: Response, user_id: str, metadata: dict) -> str:
    session_id = secrets.token_urlsafe(32)
    session_data = {"user_id": user_id, "created_at": time(), **metadata}
    await redis_client.setex(f"session:{session_id}", SESSION_TTL, json.dumps(session_data))
    response.set_cookie(
        key="session_id",
        value=session_id,
        httponly=True,
        secure=True,         # HTTPS only
        samesite="lax",      # CSRF protection
        max_age=SESSION_TTL,
        path="/"
    )
    return session_id

async def get_session(request: Request) -> dict | None:
    session_id = request.cookies.get("session_id")
    if not session_id:
        return None
    data = await redis_client.getex(f"session:{session_id}", ex=SESSION_TTL)  # rolling expiry
    return json.loads(data) if data else None
```

### Session Fixation Prevention (Regenerate on Login)
```python
async def login(request: Request, response: Response, credentials: LoginForm) -> User:
    user = authenticate(credentials.username, credentials.password)
    # Invalidate any existing session before creating a new one
    old_session_id = request.cookies.get("session_id")
    if old_session_id:
        await redis_client.delete(f"session:{old_session_id}")
    # Issue a new session ID — prevents session fixation
    await create_session(response, user.id, {"ip": request.client.host})
    return user
```
Session fixation: an attacker pre-sets a known session ID, the victim logs in, and the attacker now
has an authenticated session. Prevent by always issuing a new session ID on authentication.

### CSRF Protection

**SameSite=Lax (primary defense):**
SameSite=Lax blocks cookies on cross-site POST requests — sufficient protection for most applications.
Upgrade to `SameSite=Strict` for banking/admin applications.

**Double-Submit Cookie (defense-in-depth for SameSite=None scenarios):**
```python
def generate_csrf_token(session_id: str) -> str:
    # HMAC-sign the session ID with a server secret — stateless CSRF token
    return hmac.new(SECRET_KEY, session_id.encode(), hashlib.sha256).hexdigest()

async def verify_csrf(request: Request) -> None:
    session_id = request.cookies.get("session_id")
    csrf_cookie = request.cookies.get("csrf_token")
    csrf_header = request.headers.get("X-CSRF-Token")
    expected = generate_csrf_token(session_id)
    if not (csrf_cookie == expected and csrf_header == expected):
        raise ForbiddenException("CSRF verification failed")
```

### Cookie Security Configuration
```python
# Full production cookie settings
response.set_cookie(
    key="session_id",
    value=session_id,
    httponly=True,      # inaccessible to JavaScript — prevents XSS token theft
    secure=True,        # sent over HTTPS only — never over HTTP
    samesite="lax",     # blocks CSRF on cross-site navigation POST; use "strict" for high-security
    max_age=1800,       # absolute expiry in seconds
    path="/",           # restrict to application path
    domain=None         # do not set domain — prevents subdomain sharing
)
```

### Idle and Absolute Timeouts
```python
SESSION_IDLE_TIMEOUT = 1800      # 30 minutes of inactivity
SESSION_ABSOLUTE_TIMEOUT = 28800  # 8 hours maximum regardless of activity

async def validate_and_refresh_session(session_id: str) -> dict:
    data = await redis_client.get(f"session:{session_id}")
    if not data:
        raise UnauthorizedException("Session expired or invalid")
    session = json.loads(data)

    # Absolute timeout check (idle refresh cannot extend past this)
    if time() - session["created_at"] > SESSION_ABSOLUTE_TIMEOUT:
        await redis_client.delete(f"session:{session_id}")
        raise UnauthorizedException("Session absolute timeout reached")

    # Idle timeout: extend TTL on activity (rolling window)
    await redis_client.expire(f"session:{session_id}", SESSION_IDLE_TIMEOUT)
    return session
```

### Logout (Session Destruction)
```python
async def logout(request: Request, response: Response) -> None:
    session_id = request.cookies.get("session_id")
    if session_id:
        await redis_client.delete(f"session:{session_id}")
    # Expire the cookie — set max_age=0
    response.set_cookie(key="session_id", value="", httponly=True, secure=True,
                        samesite="lax", max_age=0)
```

### Concurrent Session Management
```python
# Track all sessions for a user (for forced logout / "logout all devices")
async def create_session(response: Response, user_id: str) -> str:
    session_id = secrets.token_urlsafe(32)
    await redis_client.setex(f"session:{session_id}", SESSION_IDLE_TIMEOUT, json.dumps(data))
    await redis_client.sadd(f"user:{user_id}:sessions", session_id)
    await redis_client.expire(f"user:{user_id}:sessions", SESSION_ABSOLUTE_TIMEOUT)
    return session_id

async def logout_all_sessions(user_id: str) -> None:
    session_ids = await redis_client.smembers(f"user:{user_id}:sessions")
    keys = [f"session:{sid}" for sid in session_ids] + [f"user:{user_id}:sessions"]
    await redis_client.delete(*keys)
```

## Configuration

```yaml
session:
  idle_timeout_seconds: 1800      # 30 minutes
  absolute_timeout_seconds: 28800 # 8 hours
  cookie_name: session_id
  cookie_secure: true
  cookie_httponly: true
  cookie_samesite: lax
  redis_key_prefix: "session:"
  id_bytes: 32                    # 256 bits of randomness
```

## Performance

- Use Redis GETEX (Redis 6.2+) to get and refresh TTL atomically — eliminates a separate EXPIRE call.
- Store only essential data in the session (user_id, roles, tenant); fetch the full profile from DB/cache.
- Use Redis pipelining when validating sessions with multiple Redis operations per request.

## Security

- Use `cryptographically random` session IDs (32+ bytes / 256 bits) — `secrets.token_urlsafe(32)` in Python.
- Always regenerate session ID on privilege elevation (login, sudo mode, password change).
- Implement both idle and absolute timeouts — idle alone allows indefinitely active sessions.
- SameSite=Lax is the minimum; Strict for admin portals and banking applications.
- Log session creation, destruction, and timeout events for security audit trails.

## Testing

```python
def test_session_fixation_prevented(client, db):
    # Pre-set a session ID (fixation attempt)
    old_id = "attacker-known-session-id"
    client.cookies["session_id"] = old_id
    # Login
    response = client.post("/auth/login", json={"username": "user", "password": "pass"})
    new_session_id = response.cookies["session_id"]
    assert new_session_id != old_id   # session ID must change on login

def test_idle_timeout(client, redis_client, freeze_time):
    session_id = create_authenticated_session(client)
    freeze_time.move_to(SESSION_IDLE_TIMEOUT + 1)
    response = client.get("/api/me", cookies={"session_id": session_id})
    assert response.status_code == 401
```

## Dos
- Regenerate session ID on every authentication event (login, privilege escalation).
- Set HttpOnly, Secure, and SameSite=Lax on all session cookies — no exceptions in production.
- Implement both idle and absolute timeouts; enforce server-side via session store TTL.
- Use Redis with persistence or a replicated backend to avoid session loss on server restart.
- Provide "logout all devices" functionality for security-sensitive applications.

## Don'ts
- Don't store sensitive data (passwords, card numbers) in the session — store minimal claims only.
- Don't rely solely on cookie expiry for session invalidation — always delete server-side session on logout.
- Don't use sequential or predictable session IDs — always use cryptographically random values.
- Don't set `domain=.example.com` on session cookies — it shares the session across all subdomains.
- Don't skip CSRF protection because you use SameSite cookies — it is defense-in-depth, not a guarantee.
