# Gin + OAuth2 / JWT

> Gin-specific JWT and OAuth2 patterns using `go-jose`.
> Generic JWT validation is in `modules/frameworks/go-stdlib/auth/oauth2.md`.

## Integration Setup

```go
// go.mod
require (
    github.com/gin-gonic/gin v1.10.0
    github.com/go-jose/go-jose/v4 v4.0.1
    github.com/golang-jwt/jwt/v5 v5.2.1  // alternative for simpler HS256 setups
)
```

## JWT Middleware

```go
const ginClaimsKey = "claims"

func JWTMiddleware(validator *auth.JWTValidator) gin.HandlerFunc {
    return func(c *gin.Context) {
        header := c.GetHeader("Authorization")
        if !strings.HasPrefix(header, "Bearer ") {
            c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "missing token"})
            return
        }
        token := strings.TrimPrefix(header, "Bearer ")

        claims, err := validator.Validate(c.Request.Context(), token)
        if err != nil {
            c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "invalid token"})
            return
        }

        c.Set(ginClaimsKey, claims)
        c.Next()
    }
}
```

## Claims Extraction in Handlers

```go
func GetCurrentUserHandler(svc UserService) gin.HandlerFunc {
    return func(c *gin.Context) {
        claims := MustGetClaims(c)
        user, err := svc.GetBySubject(c.Request.Context(), claims.Subject)
        if err != nil {
            c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
            return
        }
        c.JSON(http.StatusOK, user)
    }
}

func MustGetClaims(c *gin.Context) *auth.Claims {
    v, _ := c.Get(ginClaimsKey)
    return v.(*auth.Claims)
}
```

## Role-Based Access Control

```go
func RequireRole(role string) gin.HandlerFunc {
    return func(c *gin.Context) {
        claims := MustGetClaims(c)
        for _, r := range claims.Roles {
            if r == role {
                c.Next()
                return
            }
        }
        c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "insufficient permissions"})
    }
}

// Route wiring
protected := r.Group("/api/v1")
protected.Use(JWTMiddleware(validator))
{
    protected.GET("/users/me", GetCurrentUserHandler(svc))
    admin := protected.Group("/admin")
    admin.Use(RequireRole("admin"))
    admin.DELETE("/users/:id", DeleteUserHandler(svc))
}
```

## Scaffolder Patterns

```yaml
patterns:
  jwt_middleware: "internal/middleware/auth.go"
  claims_helper: "internal/middleware/claims.go"
  rbac_middleware: "internal/middleware/rbac.go"
  validator: "internal/auth/jwt.go"
```

## Additional Dos/Don'ts

- DO use `c.AbortWithStatusJSON` in middleware to halt the chain and avoid calling the handler
- DO separate authentication (JWT middleware) from authorization (role middleware) into distinct middleware functions
- DO validate `iss`, `aud`, and `exp` inside the validator, not in the Gin middleware
- DO store only typed claims structs in the Gin context — never raw `map[string]interface{}`
- DON'T log the token string — log only the `sub` claim for audit purposes
- DON'T perform JWKS fetches inside the middleware on every request — cache and refresh in background
