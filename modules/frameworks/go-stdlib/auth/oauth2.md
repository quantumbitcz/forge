# Go stdlib + OAuth2 / JWT

> Go stdlib OAuth2 and JWT patterns using `golang.org/x/oauth2` and `go-jose`.
> Extends generic Go conventions.

## Integration Setup

```go
// go.mod
require (
    golang.org/x/oauth2 v0.21.0
    github.com/go-jose/go-jose/v4 v4.0.1
)
```

## JWT Validation with go-jose

```go
import (
    "github.com/go-jose/go-jose/v4"
    "github.com/go-jose/go-jose/v4/jwt"
)

type Claims struct {
    jwt.Claims                        // sub, iss, aud, exp, nbf, iat, jti
    Email  string `json:"email"`
    Roles  []string `json:"roles"`
}

type JWTValidator struct {
    keySet jose.JSONWebKeySet
}

func (v *JWTValidator) Validate(ctx context.Context, tokenStr string) (*Claims, error) {
    tok, err := jwt.ParseSigned(tokenStr, []jose.SignatureAlgorithm{jose.RS256, jose.ES256})
    if err != nil {
        return nil, fmt.Errorf("parse token: %w", err)
    }

    var claims Claims
    if err := tok.Claims(v.keySet, &claims); err != nil {
        return nil, fmt.Errorf("verify claims: %w", err)
    }

    expected := jwt.Expected{
        Issuer:      "https://auth.example.com",
        AudienceAny: jwt.Audience{"my-service"},
        Time:        time.Now(),
    }
    if err := claims.ValidateWithLeeway(expected, time.Minute); err != nil {
        return nil, fmt.Errorf("claims validation: %w", err)
    }

    return &claims, nil
}
```

## JWKS Fetching

```go
func FetchJWKS(ctx context.Context, jwksURL string) (jose.JSONWebKeySet, error) {
    req, _ := http.NewRequestWithContext(ctx, http.MethodGet, jwksURL, nil)
    resp, err := http.DefaultClient.Do(req)
    if err != nil {
        return jose.JSONWebKeySet{}, err
    }
    defer resp.Body.Close()

    var ks jose.JSONWebKeySet
    return ks, json.NewDecoder(resp.Body).Decode(&ks)
}
```

Cache the JWKS and refresh on a background goroutine (e.g., every 12 hours) or on key-not-found errors.

## Middleware Pattern

```go
type contextKey string
const claimsKey contextKey = "claims"

func AuthMiddleware(validator *JWTValidator) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            header := r.Header.Get("Authorization")
            if !strings.HasPrefix(header, "Bearer ") {
                http.Error(w, "unauthorized", http.StatusUnauthorized)
                return
            }
            token := strings.TrimPrefix(header, "Bearer ")

            claims, err := validator.Validate(r.Context(), token)
            if err != nil {
                http.Error(w, "forbidden", http.StatusForbidden)
                return
            }

            ctx := context.WithValue(r.Context(), claimsKey, claims)
            next.ServeHTTP(w, r.WithContext(ctx))
        })
    }
}

func ClaimsFromContext(ctx context.Context) (*Claims, bool) {
    c, ok := ctx.Value(claimsKey).(*Claims)
    return c, ok
}
```

## OAuth2 Client Credentials Flow

```go
func NewOAuth2TokenSource(cfg *oauth2.Config, clientSecret string) oauth2.TokenSource {
    return cfg.TokenSource(context.Background(), &oauth2.Token{})
    // For client_credentials use oauth2.ClientCredentials config
}
```

## Scaffolder Patterns

```yaml
patterns:
  jwt_validator: "internal/auth/jwt.go"
  jwks_fetcher: "internal/auth/jwks.go"
  middleware: "internal/middleware/auth.go"
  context_helpers: "internal/auth/context.go"
```

## Additional Dos/Don'ts

- DO cache the JWKS in memory and refresh it on a schedule or on unknown `kid` — fetching on every request is too slow
- DO validate `iss`, `aud`, and `exp` explicitly — never trust unsigned or unvalidated tokens
- DO use a typed `contextKey` (not a plain string) to avoid key collisions in `context.WithValue`
- DO list the exact allowed algorithms (`RS256`, `ES256`) — never accept `none`
- DON'T log or expose token strings — log the `sub` claim only
- DON'T perform authorization (role checks) inside the auth middleware — do it in the handler or a separate policy layer
- DON'T use `http.DefaultClient` without a timeout for JWKS fetches — add a `Timeout` or use a context-bound request
