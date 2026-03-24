# FastAPI + OAuth2 / JWT

> FastAPI-specific patterns for JWT-based OAuth2 authentication. Extends generic FastAPI conventions.

## Integration Setup

```bash
python-jose[cryptography]==3.3.0
```

```python
# app/config.py (extends existing Settings)
class Settings(BaseSettings):
    oauth2_issuer: str
    oauth2_audience: str
    oauth2_jwks_uri: str      # {issuer}/.well-known/jwks.json
    oauth2_algorithms: list[str] = ["RS256"]
```

## Framework-Specific Patterns

### OAuth2PasswordBearer scheme

```python
# app/auth/dependencies.py
from fastapi.security import OAuth2PasswordBearer

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/token")
```

### JWT dependency with scope validation

```python
from jose import JWTError, jwt
from fastapi import Depends, HTTPException, Security
from fastapi.security import SecurityScopes
import httpx, functools

@functools.lru_cache
def _get_jwks() -> dict:
    """Cached JWKS fetch — refreshed on process restart."""
    return httpx.get(settings.oauth2_jwks_uri).json()

async def get_current_user(
    security_scopes: SecurityScopes,
    token: str = Depends(oauth2_scheme),
) -> dict:
    try:
        payload = jwt.decode(
            token,
            _get_jwks(),
            algorithms=settings.oauth2_algorithms,
            audience=settings.oauth2_audience,
            issuer=settings.oauth2_issuer,
        )
    except JWTError as exc:
        raise HTTPException(401, detail="Invalid token") from exc

    token_scopes: list[str] = payload.get("scope", "").split()
    for scope in security_scopes.scopes:
        if scope not in token_scopes:
            raise HTTPException(403, detail=f"Scope '{scope}' required")

    return payload

CurrentUser = Annotated[dict, Depends(get_current_user)]
```

### Protected endpoints

```python
@router.get("/me")
async def get_me(user: CurrentUser) -> UserResponse:
    return UserResponse(id=user["sub"], email=user.get("email"))

@router.delete("/admin/users/{user_id}")
async def delete_user(
    user_id: UUID,
    user: Annotated[dict, Security(get_current_user, scopes=["admin"])],
) -> None:
    await user_service.delete(user_id)
```

### Sub-user extraction helper

```python
# app/auth/current_user.py
def get_subject(user: CurrentUser) -> str:
    sub = user.get("sub")
    if not sub:
        raise HTTPException(401, detail="Token missing 'sub' claim")
    return sub
```

## Scaffolder Patterns

```yaml
patterns:
  auth_deps:    "app/auth/dependencies.py"   # oauth2_scheme, get_current_user
  current_user: "app/auth/current_user.py"   # CurrentUser type alias
  auth_router:  "app/routers/auth.py"        # /auth/token for password flow (if internal IdP)
```

## Additional Dos/Don'ts

- DO validate `aud` and `iss` claims in `jwt.decode` — never skip issuer/audience verification
- DO use `Security(get_current_user, scopes=[...])` for scope-gated endpoints
- DO use `RS256` (asymmetric) in production; only use `HS256` for internal service-to-service tokens with shared secrets
- DON'T store tokens in `localStorage` on the client — use `HttpOnly` cookies for web clients
- DON'T implement your own JWT signature verification — delegate to `python-jose` or `authlib`
- DON'T hardcode `SECRET_KEY` — read from environment; rotate on compromise
