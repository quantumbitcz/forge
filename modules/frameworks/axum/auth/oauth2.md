# Axum + OAuth2 / JWT

> Axum-specific JWT validation patterns using Tower layers and custom extractors.
> Extends generic Axum conventions.

## Integration Setup

```toml
# Cargo.toml
[dependencies]
axum = "0.8"
tower = "0.5"
jsonwebtoken = "9.3"
serde = { version = "1", features = ["derive"] }
reqwest = { version = "0.12", features = ["json"] }
tokio = { version = "1", features = ["full"] }
```

## Claims and JWKS

```rust
use jsonwebtoken::{decode, DecodingKey, Validation, Algorithm};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Claims {
    pub sub: String,
    pub iss: String,
    pub aud: Vec<String>,
    pub exp: usize,
    pub roles: Vec<String>,
}

#[derive(Clone)]
pub struct JwtState {
    pub decoding_key: DecodingKey,
    pub validation: Validation,
}

impl JwtState {
    pub fn from_rsa_pem(pem: &[u8], issuer: &str, audience: &str) -> anyhow::Result<Self> {
        let mut validation = Validation::new(Algorithm::RS256);
        validation.set_issuer(&[issuer]);
        validation.set_audience(&[audience]);
        Ok(Self {
            decoding_key: DecodingKey::from_rsa_pem(pem)?,
            validation,
        })
    }
}
```

## Custom Extractor for Claims

```rust
use axum::{async_trait, extract::FromRequestParts, http::request::Parts, RequestPartsExt};
use axum_extra::TypedHeader;
use headers::{Authorization, authorization::Bearer};

#[async_trait]
impl<S> FromRequestParts<S> for Claims
where
    S: Send + Sync,
    JwtState: axum::extract::FromRef<S>,
{
    type Rejection = AppError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        let TypedHeader(Authorization(bearer)) = parts
            .extract::<TypedHeader<Authorization<Bearer>>>()
            .await
            .map_err(|_| AppError::Unauthorized)?;

        let jwt_state = JwtState::from_ref(state);
        let token_data = decode::<Claims>(
            bearer.token(),
            &jwt_state.decoding_key,
            &jwt_state.validation,
        )
        .map_err(|_| AppError::Forbidden)?;

        Ok(token_data.claims)
    }
}
```

## Using the Extractor in Handlers

```rust
async fn get_profile(
    State(state): State<AppState>,
    claims: Claims,   // extracted automatically via FromRequestParts
) -> Result<Json<Profile>, AppError> {
    let profile = state.user_service.get_by_subject(&claims.sub).await?;
    Ok(Json(profile))
}
```

## Role Guard as Tower Layer

```rust
use axum::middleware::{self, Next};
use axum::http::Request;

pub async fn require_role(
    claims: Claims,
    required: &'static str,
    request: Request,
    next: Next,
) -> Result<axum::response::Response, AppError> {
    if !claims.roles.contains(&required.to_string()) {
        return Err(AppError::Forbidden);
    }
    Ok(next.run(request).await)
}

// Wire per route group
let admin_routes = Router::new()
    .route("/admin/users", delete(delete_user))
    .layer(middleware::from_fn_with_state(state.clone(),
        |State(s): State<AppState>, req, next| async move {
            require_role(/* extract claims from req */, "admin", req, next).await
        }
    ));
```

## Scaffolder Patterns

```yaml
patterns:
  jwt_state: "src/auth/jwt.rs"
  claims_extractor: "src/auth/extractor.rs"
  role_middleware: "src/auth/middleware.rs"
  state: "src/state.rs"   # JwtState added to AppState
```

## Additional Dos/Don'ts

- DO implement `FromRequestParts` for `Claims` — it gives clean handler signatures without boilerplate extraction
- DO cache the `DecodingKey` in `AppState` — parsing PEM on every request is expensive
- DO validate `iss`, `aud`, and expiry inside `Validation` — not manually in the handler
- DO refresh JWKS on a background task when using asymmetric keys from a remote JWKS endpoint
- DON'T log or store the JWT token string — log only the `sub` claim
- DON'T perform role authorization inside the extractor — keep auth (token validity) and authz (permissions) separate
- DON'T use `Algorithm::HS256` with a weak or guessable secret — use RS256/ES256 in production
